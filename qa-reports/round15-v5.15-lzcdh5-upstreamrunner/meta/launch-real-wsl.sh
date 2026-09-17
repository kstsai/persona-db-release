#!/bin/bash
# Launch round15 REAL run in WSL, fully detached (setsid) so it survives wsl.exe exit.
set -u
D="/mnt/c/Users/is830/qa-round15-v5.15-lzcdh5-upstreamrunner"
cd "$D" || exit 1
rm -f DONE
setsid nohup env BASE_URL=http://100.96.79.33:8000 OUT="$D" bash "$D/run-test.sh" \
  > "$D/launch.log" 2>&1 < /dev/null &
echo "launched pid $!"
