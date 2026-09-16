#!/bin/bash
# runner / probe harness 的接線單元測試（不需要網路、不呼叫 LLM）
#
# 存在理由：2026-09-14 我因為
#     local id="$1"; shift; local label="$2"; shift      ← 位移後 $2 已不是 label
# 讓 run.log 印出 tmpname（"kangshimei"）而不是案例標籤原文。
# 當時沒有任何檢查會發現——因為我驗的是「腳本裡的標籤字面」，不是「執行時印出什麼」。
# 這支測試就是把「執行時印出什麼」變成可驗證的。
#
# 用法：bash meta/test-runner-harness.sh
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
TMPD=$(mktemp -d)
export OUT="$TMPD/out"
export BASE_URL="http://stub"   # case_run 會引用；set -u 下未設會直接中止
mkdir -p "$OUT"/{raw,json,headers,meta}
PASS=0; FAIL=0

check() {  # check <描述> <期望> <實際>
  if [ "$2" = "$3" ]; then
    printf '  ✅ %s\n' "$1"; PASS=$((PASS + 1))
  else
    printf '  ❌ %s\n     期望: %s\n     實際: %s\n' "$1" "$2" "$3"; FAIL=$((FAIL + 1))
  fi
}

contains() {  # contains <描述> <needle> <haystack>
  case "$3" in
    *"$2"*) printf '  ✅ %s\n' "$1"; PASS=$((PASS + 1)) ;;
    *) printf '  ❌ %s\n     找不到: %s\n     實際: %s\n' "$1" "$2" "$3"; FAIL=$((FAIL + 1)) ;;
  esac
}

# ── 抽出待測的 helper 函式（不執行整個 runner）────────────────────────
extract() { sed -n "/^$1() {/,/^}/p" "$2"; }

# stub curl：不連網，回假 body + -w 格式，並記錄收到的參數
curl() {
  local a=("$@") out="" i
  for i in "${!a[@]}"; do [ "${a[$i]}" = "-o" ] && out="${a[$((i + 1))]}"; done
  [ -n "$out" ] && printf '%s' '{"stub":true}' > "$out"
  printf '%s\n' "$*" >> "$TMPD/curl-args.txt"
  printf 'http_code=200\ntime_total=0.10\nsize_download=13\nurl_effective=http://stub/x\n'
}

eval "$(extract case_run run-test.sh)"
export P="$OUT/probe"; mkdir -p "$P"   # probe 腳本在函式外設定 P，抽函式時要自己補
eval "$(extract probe probe/run-probe.sh)"

echo "=== 1. case_run（run-test.sh）接線 ==="
LBL='=== 1. 康是美的目標客戶 ===（藥妝零售語意 — 不應套 aesthetic_procedure, #36）'
OUT1=$(case_run "01_kangshimei" "$LBL" "kangshimei" \
  --data-urlencode "questions=康是美的目標客戶" --data-urlencode "top_k=3" 2>"$TMPD/err1")
contains "印出的是『標籤原文』而不是 tmpname" "$LBL" "$OUT1"
contains "meta 的 # cmd 記錄了實際請求參數" 'questions=康是美的目標客戶' "$(grep '^# cmd' "$OUT/meta/01_kangshimei.meta")"
check "http_code 有寫進 meta" "200" "$(sed -n 's/^http_code=//p' "$OUT/meta/01_kangshimei.meta")"
check "/tmp 檔名用的是 tmpname" "kangshimei" "$(ls -1 /tmp/kangshimei.json >/dev/null 2>&1 && echo kangshimei || echo MISSING)"
check "raw body 落盤" '{"stub":true}' "$(cat "$OUT/raw/01_kangshimei.body")"
contains "curl 收到 questions 參數" 'questions=康是美的目標客戶' "$(cat "$TMPD/curl-args.txt")"
contains "curl 收到 top_k 參數" 'top_k=3' "$(cat "$TMPD/curl-args.txt")"
check "參數順序（questions 先於 top_k）" "yes" "$(awk '{i=index($0,"questions="); j=index($0,"top_k="); print (i>0 && j>i) ? "yes" : "no"}' "$TMPD/curl-args.txt")"

echo
echo "=== 2. probe（run-probe.sh）接線 ==="
OUT2=$(probe "r06_aesthetic_1" "§6.8 重現性 — case06 醫美 r1/3" \
  --data-urlencode "questions=醫美診所的目標客戶" --data-urlencode "top_k=10" 2>"$TMPD/err2")
contains "印出的是標籤原文" "§6.8 重現性 — case06 醫美 r1/3" "$OUT2"
check "探針 raw body 落盤" '{"stub":true}' "$(cat "$OUT/probe/r06_aesthetic_1.body")"
check "探針 meta 有 http_code" "200" "$(sed -n 's/^http_code=//p' "$OUT/probe/r06_aesthetic_1.meta")"

rm -f /tmp/kangshimei.json
rm -rf "$TMPD"

echo
printf '通過 %d 項，失敗 %d 項\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
