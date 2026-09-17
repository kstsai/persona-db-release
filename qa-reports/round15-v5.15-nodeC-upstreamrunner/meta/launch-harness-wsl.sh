#!/bin/bash
# Launch round15 runner in WSL (UTF-8 native curl). Evidence -> /mnt/c (Windows-visible).
set -u
D="/mnt/c/Users/is830/qa-round15-v5.15-NODE-C-upstreamrunner"
H="$D/meta/harness-wsl"
rm -rf "$H"
mkdir -p "$H"
cd "$H" || exit 1
BASE_URL=http://127.0.0.1:18099 OUT="$H" bash "$D/run-test.sh" > "$H/harness-wsl.log" 2>&1
echo "exit=$?"
echo "raw=$(ls "$H/raw" 2>/dev/null | wc -l) headers=$(ls "$H/headers" 2>/dev/null | wc -l) meta=$(ls "$H/meta" 2>/dev/null | wc -l)"
echo "--- tail ---"
tail -6 "$H/run.log"
