#!/usr/bin/env python3
"""由 upstream test-persona-db-api.sh 機械組出 run-test.sh。

規則（skill Step 1）：
  可以改：輸出落盤、curl -s、runner 自己的標籤
  不可以改：請求參數、參數順序、斷言邏輯、案例標籤字面

忠實度做法：
  * 前段（L1–L14）與斷言段（L88–L301）以「原檔逐字切片」併入，不經人手轉錄。
  * 案例標籤直接從 upstream 的 echo 行抽取原文（連 `===` 的空白都照抄），
    避免我手寫時偷偷把 `）===` 寫成 `） ===`。
  * 請求參數由 verify-instrument.py 以 diff 機械證明與 upstream 完全相同。
"""
import pathlib
import re

UP = pathlib.Path("meta/original-upstream-fb2c2fda.sh")
OUT = pathlib.Path("run-test.sh")

src = UP.read_text(encoding="utf-8")
lines = src.split("\n")
assert lines[0].startswith("#!/bin/bash"), "upstream 開頭不是 shebang"
assert len(lines) == 580, f"upstream 應為 579 行（+尾端空行=580 元素），實得 {len(lines)}"

part_a = lines[:14]          # L1–L14：shebang、註解、jq 檢查、「正確版」註解
part_c = lines[87:]          # L88–L301：Role QA diff check + 全部斷言（含 #55/#50 主機層）

assert "jq install failed" in "\n".join(part_a), "part_a 沒涵蓋 jq 檢查"
assert part_c[0].strip() == 'echo ""', f"part_c 起點應為空 echo，實得 {part_c[0]!r}"
assert 'Role QA: diff check' in part_c[1], f"part_c[1] 應為 Role QA 標題，實得 {part_c[1]!r}"
assert part_c[-2].startswith("fi"), f"part_c 倒數第二行應為 fi，實得 {part_c[-2]!r}"
assert len(part_c) == 579 - 87 + 1, f"part_c 應為 493 元素（L88–L579 + 尾端空行），實得 {len(part_c)}"

# ── 案例標籤：直接從 upstream 抽原文（順序即案例順序）──────────────────
UP_LABELS = re.findall(r'^echo "(=== \d\..*)"$', src, re.M)
assert len(UP_LABELS) == 9, f"upstream 應有 9 個案例標籤，實得 {len(UP_LABELS)}"

# ── 案例定義：(id, /tmp 檔名或 None, [參數…]) ─────────────────────────
# ── OUT 預設值改為「自我定位」：runner 就在本輪目錄裡，用 dirname $0 推導 ──
# 歷史：第十輪我複製第九輪的工具時忘了改寫死的 `$HOME/qa-round9`，導致第十輪的證據
# **寫進第九輪的目錄、就地覆寫已發布的證據**。改成自我定位後，這條路徑不再需要人工維護 ——
# 不論目錄叫什麼名字、被複製到哪一輪，runner 永遠寫到它自己所在的那個目錄。
ROUND_TAG = pathlib.Path(".").resolve().name.split("-")[0]      # 例：round11（僅用於檢查）
OUT_EXPR = '$(cd "$(dirname "$0")" && pwd)'

CASES = [
    ("01_kangshimei",     "kangshimei",         ["questions=康是美的目標客戶", "top_k=3", "opMode=僅篩選"]),
    ("02_tesla",          "tesla",              ["questions=TESLA的目標客戶", "top_k=3", "opMode=僅篩選"]),
    ("03_fashion",        "fashion_closing",    ["questions=時尚服裝設計師的目標客戶", "top_k=10", "opMode=僅篩選"]),
    ("04_role_fangzhong", "role_fangzhong",     ["questions=房貸優惠方案", "role=房仲業者", "top_k=5", "opMode=僅篩選"]),
    ("05_role_banker",    "role_banker",        ["questions=房貸優惠方案", "role=銀行業者", "top_k=5", "opMode=僅篩選"]),
    ("06_aesthetic",      "aesthetic_closing",  ["questions=醫美診所的目標客戶", "role=醫美診所行銷主管", "top_k=10", "opMode=僅篩選"]),
    ("07_debt",           "debt_closing",       ["questions=債務整合貸款方案的目標客戶", "role=銀行債務整合專員", "top_k=10", "opMode=僅篩選"]),
    ("08_boss",           "boss_closing",       ["questions=小吃攤老闆的目標客群", "role=夜市商圈協會", "top_k=10", "opMode=僅篩選"]),
    ("09_owner",          "owner_closing",      ["questions=想找企業主或工廠老闆本人作為B2B問卷受訪者", "top_k=10", "opMode=僅篩選"]),
]
assert len(CASES) == len(UP_LABELS), f"案例數不符：{len(CASES)} vs {len(UP_LABELS)}"

W = ("http_code=%{http_code}\\ntime_total=%{time_total}\\n"
     "size_download=%{size_download}\\nurl_effective=%{url_effective}\\n")

mid = f'''
# ── runner 環境（不改請求，只決定證據落盤位置）──────────────────────────
BASE_URL="${{BASE_URL:-http://localhost:8000}}"
OUT="${{OUT:-{OUT_EXPR}}}"
mkdir -p "$OUT"/{{raw,json,headers,meta,extra,supplemental,probe}}
exec > >(tee -a "$OUT/run.log") 2>&1
echo "# run start $(date -u +%Y-%m-%dT%H:%M:%SZ)  BASE_URL=$BASE_URL  host=$(hostname)"

# ── helper：一個案例 = 完整證據（raw body + headers + meta）─────────────
case_run() {{   # case_run <id> <label 原文> <tmpname|-> <curl args...>
  local id="$1" label="$2" tmp="$3"
  shift 3
  echo ""
  echo "$label"
  time curl -s --get "${{BASE_URL}}/personadb/candidates" "$@" \\
    -D "$OUT/headers/${{id}}.headers" -o "$OUT/raw/${{id}}.body" \\
    -w '{W}' > "$OUT/meta/${{id}}.w"
  {{
    echo "# case  = ${{id}}"
    echo "# label = ${{label}}"
    echo "# cmd   = curl -s --get ${{BASE_URL}}/personadb/candidates $*"
    cat "$OUT/meta/${{id}}.w"
  }} > "$OUT/meta/${{id}}.meta"
  cat "$OUT/raw/${{id}}.body" | tee "/tmp/${{tmp}}.json"
  echo ""
  cp "$OUT/raw/${{id}}.body" "$OUT/json/${{id}}.json" 2>/dev/null || true
}}

# ── 案例 0：status（upstream 無標籤；此處僅為可讀性加一行）─────────────
echo ""
echo "=== 0. /personadb/status ==="
time curl -s --get "${{BASE_URL}}/personadb/status" \\
  -D "$OUT/headers/00_status.headers" -o "$OUT/raw/00_status.body" \\
  -w '{W}' > "$OUT/meta/00_status.w"
{{
  echo "# case  = 00_status"
  echo "# cmd   = curl -s --get ${{BASE_URL}}/personadb/status"
  cat "$OUT/meta/00_status.w"
}} > "$OUT/meta/00_status.meta"
cat "$OUT/raw/00_status.body"
'''

for (cid, tmp, params), label in zip(CASES, UP_LABELS):
    args = " ".join(f'--data-urlencode "{p}"' for p in params)
    mid += f'\ncase_run "{cid}" "{label}" "{tmp or "-"}" {args}\n'

mid += '''
# ── 契約快照（本 runner 追加，供解讀回應用；不涉請求）────────────────
curl -s -m 30 "${BASE_URL}/openapi.json" -o "$OUT/raw/openapi.json"
echo ""
echo "# contract sha256: $(shasum -a 256 "$OUT/raw/openapi.json" 2>/dev/null | cut -d' ' -f1)"
echo "# run end $(date -u +%Y-%m-%dT%H:%M:%SZ)"
'''

body = "\n".join(part_a) + mid + "\n".join(part_c)
OUT.write_text(body, encoding="utf-8")
print(f"✅ 產生 {OUT}（{len(body.splitlines())} 行）")
print(f"   part_a = upstream L1–L14（{len(part_a)} 元素）")
print(f"   mid    = 本輪案例呼叫（{len(mid.splitlines())} 行）")
print(f"   part_c = upstream L88–L579（{len(part_c)} 元素，逐字）")
print(f"   案例標籤 = 直接取自 upstream 原文（{len(UP_LABELS)} 個）")
_stale = set(re.findall(r"qa-round(\\d+)", body)) - {ROUND_TAG.replace("round", "")}
assert "dirname \"$0\"" in body, "❌ runner 內找不到自我定位的 OUT 推導"
assert not _stale, f"❌ runner 內殘留其他輪次的目錄名 qa-round{sorted(_stale)}"
print(f"   OUT 預設 = 自我定位（dirname $0）；殘留的其他輪次目錄名 = {sorted(_stale) or '無'}")
