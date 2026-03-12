#!/usr/bin/env bash
# update-full.sh — Comprehensive dashboard data: HW + build + architecture + agent feedback
set -euo pipefail

NEXUS="/home/madhur/Documents/nexus-ide-share"
DASH="/tmp/dashboard-site"
export PATH="$HOME/.cargo/bin:$HOME/.nvm/versions/node/v22.22.1/bin:$HOME/.local/bin:$HOME/go/bin:$PATH"
cd "$NEXUS"

# ── Hardware ──
LOAD=$(awk '{print $1}' /proc/loadavg)
NPROC=$(nproc)
CPU_PCT=$(awk "BEGIN{v=int(($LOAD/$NPROC)*100); if(v>100)v=100; print v}")
CPU_TEMP=$(cat /sys/class/hwmon/hwmon7/temp1_input 2>/dev/null | awk '{printf "%.0f",$1/1000}' || echo "0")
RAM_TOTAL=$(free -m | awk '/Mem:/{print $2}')
RAM_USED=$(free -m | awk '/Mem:/{print $3}')
RAM_PCT=$((RAM_USED * 100 / RAM_TOTAL))
GPU_PCT=$(cat /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | head -1 || echo "0")
GPU_TEMP=$(cat /sys/class/hwmon/hwmon4/temp1_input 2>/dev/null | awk '{printf "%.0f",$1/1000}' || echo "0")
DISK_PCT=$(df / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}')
DISK_USED=$(df -h / 2>/dev/null | awk 'NR==2{print $3}')
DISK_TOTAL=$(df -h / 2>/dev/null | awk 'NR==2{print $2}')
VRAM_USED=$(cat /sys/class/drm/card*/device/mem_info_vram_used 2>/dev/null | head -1 || echo "0")
VRAM_TOTAL=$(cat /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null | head -1 || echo "1")
VRAM_U_GB=$(awk "BEGIN{printf \"%.1f\",$VRAM_USED/1073741824}")
VRAM_T_GB=$(awk "BEGIN{printf \"%.0f\",$VRAM_TOTAL/1073741824}")

# ── Tests ──
VITEST=$(npx vitest run 2>&1)
VT_PASS=$(echo "$VITEST" | grep "Tests" | grep -oP '\d+ passed' | grep -oP '\d+' | head -1 || echo "0")
VT_FAIL=$(echo "$VITEST" | grep "Tests" | grep -oP '\d+ failed' | grep -oP '\d+' | head -1 || echo "0")
VT_FILES=$(echo "$VITEST" | grep "Test Files" | grep -oP '\d+ passed' | grep -oP '\d+' | head -1 || echo "0")
RT_PASS=$(cd rust && cargo test -p nexus-core --lib ai::tools 2>&1 | grep -oP '(\d+) passed' | grep -oP '\d+' || echo "0")

# ── Build ──
TS_ERR=$(npx tsc --noEmit 2>&1 | grep -c "error TS"; true)
BUILD_OUT=$(npm run build 2>&1)
BUILD_TIME=$(echo "$BUILD_OUT" | grep -oP 'built in \K[0-9.]+' || echo "0")
BUNDLE_KB=$(ls -la dist/assets/index-*.js 2>/dev/null | awk '{printf "%.0f",$5/1024}' || echo "0")

# ── Code stats ──
TS_LINES=$(find src -name "*.ts" -o -name "*.tsx" | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
RS_LINES=$(find rust -name "*.rs" | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
NEW_FILES=$(git diff --name-only --diff-filter=A 77dee46..HEAD 2>/dev/null | grep -cv dashboard || echo "0")
LINES_ADD=$(git diff --stat 77dee46..HEAD 2>/dev/null | tail -1 | grep -oP '(\d+) insertion' | grep -oP '\d+' || echo "0")
LINES_DEL=$(git diff --stat 77dee46..HEAD 2>/dev/null | tail -1 | grep -oP '(\d+) deletion' | grep -oP '\d+' || echo "0")
TOTAL_COMMITS=$(git log --oneline 77dee46..HEAD 2>/dev/null | wc -l)

# ── Commits ──
COMMITS=$(git log --oneline -15 --format='{"hash":"%h","msg":"%s","time":"%cd","author":"%an"}' --date=format:'%H:%M' 2>/dev/null)

# ── File tree (architecture) ──
TREE=$(python3 << 'PYEOF'
import os, re, json
from collections import defaultdict
cats = defaultdict(lambda:{"count":0,"lines":0,"files":[]})
for root,dirs,files in os.walk("src"):
    dirs[:] = [d for d in dirs if d not in ("__tests__","__mocks__","node_modules")]
    for f in files:
        if not f.endswith(('.ts','.tsx')): continue
        path = os.path.join(root,f)
        rel = os.path.relpath(path,"src")
        lines = sum(1 for _ in open(path))
        if "store/" in rel: cat="Stores"
        elif "components/panels/" in rel: cat="Panels"
        elif "components/chat/" in rel: cat="Chat UI"
        elif "components/editor/" in rel: cat="Editor"
        elif "components/shell/" in rel: cat="Shell"
        elif "components/" in rel: cat="Components"
        elif "keybindings/" in rel or "context/" in rel or "lsp/" in rel or "editor/" in rel: cat="Core Systems"
        elif "hooks/" in rel: cat="Hooks"
        else: cat="Other"
        cats[cat]["count"]+=1
        cats[cat]["lines"]+=lines
        if lines>200: cats[cat]["files"].append({"name":f,"lines":lines})
for c in cats.values():
    c["files"].sort(key=lambda x:-x["lines"])
    c["files"]=c["files"][:5]
print(json.dumps(dict(cats)))
PYEOF
)

# ── Changed files tonight with line counts ──
CHANGED=$(git diff --numstat 77dee46..HEAD 2>/dev/null | awk '{print "{\"add\":" $1 ",\"del\":" $2 ",\"file\":\"" $3 "\"}"}' | head -20 | paste -sd, -)

# ── Qwen feedback (last review) ──
FEEDBACK='[
  {"bug":"LSP unavailableServers never expires","severity":"high","status":"fixed","commit":"7b958f0"},
  {"bug":"Ghost text cache shared across panes","severity":"medium","status":"fixed","commit":"7b958f0"},
  {"bug":"InlineEditWidget floats on scroll","severity":"medium","status":"fixed","commit":"7b958f0"},
  {"bug":"Context indexer blocks UI on large repos","severity":"low","status":"open","fix":"Use chunked async walk with requestAnimationFrame yields"},
  {"bug":"File watcher floods on git checkout","severity":"low","status":"open","fix":"Coalesce events with 500ms window before emitting"}
]'

# ── Write JSON ──
cat > "$DASH/data.json" << JSONEOF
{
  "updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "updatedIST": "$(TZ=Asia/Kolkata date '+%H:%M:%S %d %b')",
  "hw": {
    "cpuPct": $CPU_PCT, "cpuTemp": $CPU_TEMP,
    "ramPct": $RAM_PCT, "ramUsedMB": $RAM_USED, "ramTotalMB": $RAM_TOTAL,
    "gpuPct": ${GPU_PCT:-0}, "gpuTemp": $GPU_TEMP,
    "diskPct": $DISK_PCT, "diskUsed": "$DISK_USED", "diskTotal": "$DISK_TOTAL",
    "vramUsedGB": $VRAM_U_GB, "vramTotalGB": $VRAM_T_GB
  },
  "tests": { "vitest": $VT_PASS, "vitestFail": $VT_FAIL, "vitestFiles": $VT_FILES, "rust": $RT_PASS },
  "build": { "tsErrors": ${TS_ERR:-0}, "bundleKB": $BUNDLE_KB, "buildTime": "$BUILD_TIME" },
  "code": {
    "tsLines": $TS_LINES, "rsLines": $RS_LINES,
    "newFiles": $NEW_FILES, "linesAdded": ${LINES_ADD:-0}, "linesRemoved": ${LINES_DEL:-0},
    "totalCommits": $TOTAL_COMMITS
  },
  "architecture": $TREE,
  "changedFiles": [$CHANGED],
  "feedback": $FEEDBACK,
  "phases": [
    {"name":"A: Editor Polish","status":"done","items":5,"done":5},
    {"name":"B: LSP Completion","status":"done","items":7,"done":7},
    {"name":"C: File Ops & Nav","status":"done","items":5,"done":5},
    {"name":"D: Git Integration","status":"done","items":4,"done":4},
    {"name":"E: Preview System","status":"done","items":6,"done":4},
    {"name":"F: AI Completion","status":"done","items":4,"done":3},
    {"name":"G: Multi-Agent","status":"active","items":6,"done":0},
    {"name":"H: Polish","status":"pending","items":4,"done":0}
  ],
  "commits": [$(echo "$COMMITS" | paste -sd, -)]
}
JSONEOF

cd "$DASH"
git add -A
git diff --cached --quiet && { echo "[full] No changes"; exit 0; }
git commit -q -m "sync $(TZ=Asia/Kolkata date '+%H:%M')"
git push -q 2>/dev/null
echo "[full] Synced at $(TZ=Asia/Kolkata date '+%H:%M:%S')"
