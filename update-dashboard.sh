#!/usr/bin/env bash
# update-dashboard.sh — Gathers system + build stats, pushes to GitHub Pages
set -euo pipefail

NEXUS="/home/madhur/Documents/nexus-ide-share"
DASH="/tmp/dashboard-site"
export PATH="$HOME/.cargo/bin:$HOME/.nvm/versions/node/v22.22.1/bin:$HOME/.local/bin:$HOME/go/bin:$PATH"
cd "$NEXUS"

# ── Hardware ──
CPU_PCT=$(awk '{u=$2+$4; t=$2+$4+$5; if(t>0) printf "%.0f", u*100/t}' /proc/stat 2>/dev/null | head -c4 || echo "0")
# Better CPU: use loadavg / nproc
LOAD=$(awk '{print $1}' /proc/loadavg)
NPROC=$(nproc)
CPU_PCT=$(awk "BEGIN{printf \"%.0f\", ($LOAD/$NPROC)*100}")
[ "$CPU_PCT" -gt 100 ] 2>/dev/null && CPU_PCT=100

CPU_TEMP=$(cat /sys/class/hwmon/hwmon7/temp1_input 2>/dev/null | awk '{printf "%.0f", $1/1000}' || echo "0")

RAM_TOTAL=$(free -m | awk '/Mem:/{print $2}')
RAM_USED=$(free -m | awk '/Mem:/{print $3}')
RAM_PCT=$((RAM_USED * 100 / RAM_TOTAL))
RAM_DETAIL="${RAM_USED}MB / ${RAM_TOTAL}MB"

GPU_PCT=$(cat /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | head -1 || echo "0")
GPU_TEMP=$(cat /sys/class/hwmon/hwmon4/temp1_input 2>/dev/null | awk '{printf "%.0f", $1/1000}' || echo "0")

DISK_PCT=$(df / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}' || echo "0")
DISK_USED=$(df -h / 2>/dev/null | awk 'NR==2{print $3}' || echo "?")
DISK_TOTAL=$(df -h / 2>/dev/null | awk 'NR==2{print $2}' || echo "?")
DISK_DETAIL="${DISK_USED} / ${DISK_TOTAL}"

VRAM_USED=$(cat /sys/class/drm/card*/device/mem_info_vram_used 2>/dev/null | head -1 || echo "0")
VRAM_TOTAL=$(cat /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null | head -1 || echo "1")
VRAM_USED_GB=$(awk "BEGIN{printf \"%.1f\", $VRAM_USED/1073741824}")
VRAM_TOTAL_GB=$(awk "BEGIN{printf \"%.0f\", $VRAM_TOTAL/1073741824}")
VRAM_STR="${VRAM_USED_GB}GB / ${VRAM_TOTAL_GB}GB"

# ── Build Stats ──
TOTAL_TESTS=$(cd "$NEXUS" && npx vitest run --reporter=verbose 2>&1 | grep -c "✓" || echo "0")
RUST_TESTS=$(cd "$NEXUS/rust" && cargo test -p nexus-core --lib ai::tools 2>&1 | grep -oP '(\d+) passed' | grep -oP '\d+' || echo "0")
TS_ERRORS=$(cd "$NEXUS" && npx tsc --noEmit 2>&1 | grep -c "error TS"; true)
TS_ERRORS=${TS_ERRORS:-0}
NEW_FILES=$(cd "$NEXUS" && git diff --name-only --diff-filter=A 77dee46..HEAD 2>/dev/null | grep -cv dashboard || echo "0")
LINES_ADDED=$(cd "$NEXUS" && git diff --stat 77dee46..HEAD 2>/dev/null | tail -1 | grep -oP '(\d+) insertion' | grep -oP '\d+' || echo "0")
BUNDLE_KB=$(ls -la "$NEXUS/dist/assets/index-"*.js 2>/dev/null | awk '{printf "%.0f", $5/1024}' || echo "0")

# ── Commits ──
COMMIT_LOG=$(cd "$NEXUS" && git log --oneline -12 --format='{"hash":"%h","msg":"%s","time":"%cd"}' --date=format:'%H:%M' 2>/dev/null)

# ── Write JSON ──
cat > "$DASH/data.json" << JSONEOF
{
  "updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "updatedIST": "$(TZ=Asia/Calcutta date '+%H:%M:%S %d %b')",
  "hw": {
    "cpuPct": $CPU_PCT,
    "cpuTemp": $CPU_TEMP,
    "ramPct": $RAM_PCT,
    "ramDetail": "$RAM_DETAIL",
    "gpuPct": ${GPU_PCT:-0},
    "gpuTemp": "${GPU_TEMP:-0}",
    "diskPct": $DISK_PCT,
    "diskDetail": "$DISK_DETAIL",
    "vramUsed": "$VRAM_STR"
  },
  "tests": { "vitest": $TOTAL_TESTS, "rust": $RUST_TESTS },
  "files": { "new": $NEW_FILES, "linesAdded": ${LINES_ADDED:-0} },
  "build": { "ok": 1, "tsErrors": $TS_ERRORS, "bundleKB": ${BUNDLE_KB:-0} },
  "commits": [$(echo "$COMMIT_LOG" | paste -sd, -)]
}
JSONEOF

# ── Push ──
cd "$DASH"
git add -A
git diff --cached --quiet && { echo "[dashboard] No changes"; exit 0; }
git commit -q -m "sync $(TZ=Asia/Calcutta date '+%H:%M')"
git push -q 2>/dev/null
echo "[dashboard] Synced at $(TZ=Asia/Calcutta date '+%H:%M:%S')"
