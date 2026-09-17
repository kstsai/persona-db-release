#!/bin/bash
# Run round15 runner in WSL FOREGROUND (keeps wsl.exe alive -> WSL session persists).
# Invoked via terminal background=true so the wsl.exe process stays up for the whole run.
set -u
D="/mnt/c/Users/is830/qa-round15-v5.15-lzcdh5-upstreamrunner"
cd "$D" || exit 1
rm -f DONE
BASE_URL=http://100.96.79.33:8000 OUT="$D" bash "$D/run-test.sh"
echo "RUNNER_EXIT=$?"
touch "$D/DONE"
