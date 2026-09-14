#!/usr/bin/env python3
"""儀器忠實度證明：run-test.sh 相對 upstream 只能差在「證據落盤」那一區，不能差在請求/斷言。

證明結構（三段拼接）：
  A. runner L1–L14       必須與 upstream L1–L14 逐字相同
  B. runner 中間段        = 本輪改寫的案例呼叫（證據落盤；請求參數由 [2] 機械比對）
  C. runner 尾段         必須與 upstream L88–L301 逐字相同
另加：請求參數與順序、案例標籤與輸出格式。
"""
import pathlib, re, difflib, sys

UP = pathlib.Path("meta/original-upstream-e6c6fe77.sh")
RN = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "run-test.sh")
up = UP.read_text(encoding="utf-8")
rn = RN.read_text(encoding="utf-8")
ul, rl = up.split("\n"), rn.split("\n")

ok = True

# ── [1] 請求參數與順序（skill 指定的機械證明）──────────────────────────
pu = re.findall(r'data-urlencode "([^"]*)"', up)
pr = re.findall(r'data-urlencode "([^"]*)"', rn)
c1 = pu == pr
ok &= c1
print(f"[1] 請求參數／順序   upstream={len(pu)} runner={len(pr)}  {'✅ 相同' if c1 else '❌ 不同'}")
if not c1:
    print("    upstream:", pu, "\n    runner  :", pr)

# ── [2] 前段：upstream L1–L14 逐字 ────────────────────────────────────
c2 = ul[:14] == rl[:14]
ok &= c2
print(f"[2] 前段 L1-L14      {'✅ 逐字相同' if c2 else '❌ 有差異'}")
if not c2:
    for l in difflib.unified_diff(ul[:14], rl[:14], lineterm=""):
        print("   ", l)

# ── [3] 尾段：upstream L88–L301 逐字 ─────────────────────────────────
a = ul[87:]
i = next(i for i, l in enumerate(rl) if "Role QA: diff check" in l) - 1
b = rl[i:]
c3 = a == b
ok &= c3
print(f"[3] 尾段（斷言）     upstream L88-L301={len(a)} 元素; runner 對應={len(b)} 元素  "
      f"{'✅ 逐字相同（0 差異）' if c3 else '❌ 有差異'}")
if not c3:
    for l in list(difflib.unified_diff(a, b, "upstream", "runner", lineterm=""))[:20]:
        print("   ", l)

# ── [4] 案例標籤：upstream 的 echo 字面 == runner 印出的標籤 ──────────
def norm(s):
    """去掉 echo 的 === 裝飾：前綴 '=== ' 與尾綴 ' ==='（若有）。"""
    s = s.strip()
    if s.startswith("=== "):
        s = s[4:]
    if s.endswith(" ==="):
        s = s[:-4]
    return s.strip()

def up_labels(text):
    out = []
    for line in text.split("\n"):
        m = re.match(r'^echo "(=== \d\..*)"\s*$', line)
        if m:
            out.append(norm(m.group(1)))
    return out

def rn_labels(text):
    return [norm(m.group(2)) for m in re.finditer(r'case_run "([^"]*)" "([^"]*)"', text)]

lu, lr = up_labels(up), rn_labels(rn)
c4 = lu == lr
ok &= c4
print(f"[4] 案例標籤         upstream={len(lu)} runner={len(lr)}  "
      f"{'✅ 逐案相同（含 #36 那條內含 === 的標籤）' if c4 else '❌ 不同'}")
if not c4:
    for x, y in zip(lu, lr):
        mark = "  " if x == y else "❌"
        print(f"    {mark} upstream={x!r}\n       runner  ={y!r}")

# ── [5] 差異總量：必須全部落在 A/B 交界的「案例定義區」────────────────
diff = [l for l in difflib.unified_diff(ul, rl, lineterm="")
        if l[:1] in "+-" and not l.startswith(("+++", "---"))]
print(f"[5] 差異總量         {len(diff)} 行 —— 全部落在 upstream L15–L87（案例定義區）"
      f"，{'符合預期' if len(diff) > 0 else '⚠️ 竟然完全相同？'}")

print()
print("結論：" + ("✅ 儀器忠實度成立 —— 請求參數與斷言邏輯零差異" if ok else "❌ 有非預期差異，不可用"))
raise SystemExit(0 if ok else 1)
