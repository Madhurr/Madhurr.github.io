#!/usr/bin/env bash
# update-dashboard.sh — Generates fresh dashboard data and pushes to GitHub Pages
# Run: ./update-dashboard.sh (or via cron every 2 min)

set -euo pipefail
NEXUS="/home/madhur/Documents/nexus-ide-share"
DASH="/tmp/dashboard-site"
cd "$NEXUS"

# Gather data
COMMIT_LOG=$(git log --oneline -12 --format='{"hash":"%h","msg":"%s","time":"%cd"}' --date=format:'%H:%M' 2>/dev/null | head -12)
TOTAL_TESTS=$(cd "$NEXUS" && npx vitest run 2>/dev/null | grep "Tests" | grep -oP '\d+ passed' | grep -oP '\d+' || echo "?")
RUST_TESTS=$(cd "$NEXUS/rust" && export PATH="$HOME/.cargo/bin:$PATH" && cargo test -p nexus-core --lib ai::tools 2>/dev/null | grep "test result" | grep -oP '\d+ passed' | grep -oP '\d+' || echo "?")
NEW_FILES=$(git diff --name-only --diff-filter=A 77dee46..HEAD 2>/dev/null | grep -v dashboard | wc -l)
LINES_ADDED=$(git diff --stat 77dee46..HEAD 2>/dev/null | tail -1 | grep -oP '\d+ insertion' | grep -oP '\d+' || echo "?")
BUNDLE_KB=$(ls -la dist/assets/index-*.js 2>/dev/null | awk '{printf "%.0f", $5/1024}' || echo "571")
BUILD_OK=$(npm run build 2>/dev/null | grep -c "built in" || echo "0")
TS_ERRORS=$(npx tsc --noEmit 2>&1 | grep -c "error TS" || echo "0")

# Generate JSON data file
cat > "$DASH/data.json" << JSONEOF
{
  "updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "updatedIST": "$(TZ=Asia/Calcutta date '+%H:%M:%S %d %b')",
  "tests": { "vitest": $TOTAL_TESTS, "rust": $RUST_TESTS },
  "files": { "new": $NEW_FILES, "linesAdded": ${LINES_ADDED:-0} },
  "build": { "ok": $BUILD_OK, "tsErrors": $TS_ERRORS, "bundleKB": ${BUNDLE_KB:-571} },
  "commits": [$(echo "$COMMIT_LOG" | paste -sd, -)]
}
JSONEOF

cd "$DASH"
git add -A
git diff --cached --quiet || git commit -q -m "auto-update $(date +%H:%M)" && git push -q 2>/dev/null

echo "[dashboard] Updated at $(date '+%H:%M:%S')"
