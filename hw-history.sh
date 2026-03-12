#!/usr/bin/env bash
# hw-history.sh — Append hardware snapshot to history file (rolling 60 entries = 2 hrs)
set -euo pipefail
DASH="/tmp/dashboard-site"
HIST="$DASH/hw-history.json"

CPU_LOAD=$(awk '{print $1}' /proc/loadavg)
NPROC=$(nproc)
CPU=$(awk "BEGIN{v=int(($CPU_LOAD/$NPROC)*100);if(v>100)v=100;print v}")
CPU_T=$(cat /sys/class/hwmon/hwmon7/temp1_input 2>/dev/null | awk '{printf "%.0f",$1/1000}' || echo "0")
RAM_U=$(free -m | awk '/Mem:/{print $3}')
RAM_T=$(free -m | awk '/Mem:/{print $2}')
RAM=$(( RAM_U * 100 / RAM_T ))
GPU=$(cat /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | head -1 || echo "0")
GPU_T=$(cat /sys/class/hwmon/hwmon4/temp1_input 2>/dev/null | awk '{printf "%.0f",$1/1000}' || echo "0")
VRAM_U=$(cat /sys/class/drm/card*/device/mem_info_vram_used 2>/dev/null | head -1 || echo "0")
VRAM_T=$(cat /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null | head -1 || echo "1")
VRAM=$(awk "BEGIN{printf \"%.0f\",$VRAM_U*100/$VRAM_T}")
DISK=$(df / | awk 'NR==2{gsub(/%/,"",$5);print $5}')
TIME=$(date '+%H:%M')

ENTRY="{\"t\":\"$TIME\",\"cpu\":$CPU,\"cpuT\":$CPU_T,\"ram\":$RAM,\"gpu\":${GPU:-0},\"gpuT\":$GPU_T,\"vram\":$VRAM,\"disk\":$DISK}"

# Append to history, keep last 60
if [ -f "$HIST" ]; then
  python3 -c "
import json,sys
try:
    d=json.load(open('$HIST'))
except: d=[]
d.append($ENTRY)
d=d[-60:]
json.dump(d,open('$HIST','w'))
print(f'History: {len(d)} entries')
"
else
  echo "[$ENTRY]" > "$HIST"
  echo "History: 1 entry (new)"
fi
