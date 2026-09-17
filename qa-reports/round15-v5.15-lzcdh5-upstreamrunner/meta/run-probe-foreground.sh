#!/bin/bash
# Run round15 probe suite in WSL FOREGROUND (keeps wsl.exe alive). Evidence -> /mnt/c.
set -u
D="/mnt/c/Users/is830/qa-round15-v5.15-lzcdh5-upstreamrunner"
cd "$D" || exit 1
rm -f probe/PROBE_DONE
BASE_URL=http://100.96.79.33:8000 OUT="$D" bash "$D/probe/run-probe.sh"
echo "PROBE_EXIT=$?"
touch "$D/probe/PROBE_DONE"
