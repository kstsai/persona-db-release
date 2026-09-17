#!/usr/bin/env bash
# ============================================================================
# scan-report-artifacts.sh — QA 報告產物「進 public repo 前」掃描
#
# 由來：#76（2026-09-17）—— round15 的去識別化 commit 移除了節點名／IP，
#       但留下**節點登入憑證**（帳號/密碼明文）與**公鑰檔**（含操作者本機識別）。
#       既有檢查只涵蓋「節點名／IP」→ 本腳本把「認證資訊／操作者識別／instrument 殘留」
#       一併納入，並要求**掃描整個報告目錄**（含 meta/），不只 ANALYSIS.md。
#
# 用法：
#   bash upDockerVerHermes/scan-report-artifacts.sh [目標目錄]      # 預設 qa-reports/
#   bash upDockerVerHermes/scan-report-artifacts.sh qa-reports/round15-v5.15-nodeC-upstreamrunner
#
# 退出碼：0 = 乾淨、1 = 有命中（CI/pre-commit 可直接用）
# ============================================================================
set -u
TARGET="${1:-.}"
EXCL_DIR="--exclude-dir=.git --exclude-dir=node_modules --exclude=.scan-allowlist --exclude=scan-report-artifacts.sh"
# 允許：文件中的範例位址（含「如」或 placeholder 語法）
ALLOW_EXAMPLE='如 https://10\.|如 10\.0\.0\.|YOUR_NODE_IP|example'
# 白名單（審計用；每行「regex＃理由」）
_ALLOW_FILE="$(dirname "$0")/../.scan-allowlist"
_ALLOW_PAT=""
if [ -f "$_ALLOW_FILE" ]; then
  _ALLOW_PAT=$(grep -v '^＃' "$_ALLOW_FILE" | sed 's/＃.*$//' | sed 's/[[:space:]]*$//' | grep -v '^$' | paste -sd '|' -)
fi
_allow() {  # stdin → 過濾白名單
  if [ -n "${_ALLOW_PAT}" ]; then grep -vE "$_ALLOW_PAT"; else cat; fi
}   # 預設整個 repo（2026-09-17：洩漏曾在 upDockerVerHermes/ 而非 qa-reports/）

if [ ! -e "$TARGET" ]; then
  echo "目標不存在：$TARGET" >&2
  exit 2
fi

FAIL=0
say() { printf "%s\n" "$*"; }

say "=== 掃描：$TARGET ==="

# ── 1. 密鑰／憑證樣式（真機密）──
CRIT_PATTERNS=(
  'PRIVATE KEY'
  'BEGIN OPENSSH'
  'ghp_[A-Za-z0-9]{20,}'
  'github_pat_[A-Za-z0-9_]{20,}'
  'AKIA[0-9A-Z]{16}'
  'sk-[A-Za-z0-9]{20,}'
  'xox[baprs]-[A-Za-z0-9-]{10,}'
  'password[[:space:]]*[=:]'
  'passwd[[:space:]]*[=:]'
)
for p in "${CRIT_PATTERNS[@]}"; do
  HITS=$(grep -rInE $EXCL_DIR "$p" "$TARGET" 2>/dev/null | grep -v 'sk-xxx' | grep -vE "$ALLOW_EXAMPLE" | _allow || true)
  if [ -n "$HITS" ]; then
    say "  ❌ [機密] /$p/"
    printf '%s\n' "$HITS" | head -5 | sed 's/^/       /'
    FAIL=1
  fi
done

# ── 2. 弱預設帳密對（round15 的實際外洩形態：ubuntu/ubuntu）──
for u in ubuntu root admin pi debian user test; do
  HITS=$(grep -rInE $EXCL_DIR "\\b${u}/${u}\\b|\\b${u}[[:space:]]*\\|[[:space:]]*密碼|帳號[：:][[:space:]]*${u}" "$TARGET" 2>/dev/null | _allow || true)
  if [ -n "$HITS" ]; then
    say "  ❌ [憑證] 疑似弱預設帳密（${u}/${u}）"
    printf '%s\n' "$HITS" | head -3 | sed 's/^/       /'
    FAIL=1
  fi
done

# ── 3. 登入程序／金鑰安裝痕跡（基礎設施細節）──
for p in 'ssh-rsa' 'ssh-ed25519' 'authorized_keys' 'install-key' 'ssh-copy-id'; do
  HITS=$(grep -rIn $EXCL_DIR "$p" "$TARGET" 2>/dev/null | grep -v "scan-report-artifacts.sh" | _allow || true)
  if [ -n "$HITS" ]; then
    say "  ❌ [基礎設施] /$p/"
    printf '%s\n' "$HITS" | head -3 | sed 's/^/       /'
    FAIL=1
  fi
done

# ── 4. 操作者本機識別 user@host（排除公開信箱網域）──
HITS=$(grep -rInE $EXCL_DIR '\b[a-z0-9._-]+@[a-z0-9-]+\b' "$TARGET" 2>/dev/null \
  | grep -vE 'users\.noreply\.github\.com|example\.(com|org)|@localhost|@users|\.local\b|`user@host`|user@host（' | _allow || true)
if [ -n "$HITS" ]; then
  say "  ⚠️  [識別] 疑似 user@host（請確認是否為操作者本機識別）"
  printf '%s\n' "$HITS" | head -5 | sed 's/^/       /'
  FAIL=1
fi

# ── 5. 私網／tailnet IP（節點去識別化）──
HITS=$(grep -rInE $EXCL_DIR '\b(10|172\.(1[6-9]|2[0-9]|3[01])|192\.168)\.([0-9]{1,3}\.){2}[0-9]{1,3}\b|\b100\.([0-9]{1,3}\.){2}[0-9]{1,3}\b' "$TARGET" 2>/dev/null | grep -vE "$ALLOW_EXAMPLE" || true)
if [ -n "$HITS" ]; then
  say "  ❌ [識別] 私網／tailnet IP"
  printf '%s\n' "$HITS" | head -5 | sed 's/^/       /'
  FAIL=1
fi

# ── 5b. 內部節點識別（硬 ❌）──
for p in 'lzcdh' 'lzc-dh' '"PublicKey": *"nodekey:'; do
  HITS=$(grep -rIn $EXCL_DIR "$p" "$TARGET" 2>/dev/null | grep -v 'scan-report-artifacts.sh' || true)
  if [ -n "$HITS" ]; then
    say "  ❌ [內部識別] /$p/"
    printf '%s\n' "$HITS" | head -3 | sed 's/^/       /'
    FAIL=1
  fi
done

# ── 5c. 第三方程式名／網路拓樸（⚠️ 需泛化：可保留「私有網路」事實，不保留產品名）──
for p in 'tailscale' 'tailnet' 'headscale'; do
  HITS=$(grep -rIn $EXCL_DIR "$p" "$TARGET" 2>/dev/null | grep -v 'scan-report-artifacts.sh' || true)
  if [ -n "$HITS" ]; then
    say "  ⚠️  [需泛化] /$p/ —— 建議改寫為「私有網路／內網」，保留方法論事實、去掉產品名"
    printf '%s\n' "$HITS" | head -3 | sed 's/^/       /'
  fi
done

# ── 6. instrument 殘留檔（啟動腳本、裝 key 腳本等）──
for f in $(find "$TARGET" -type f \( -name 'install-key*' -o -name '*.pem' -o -name 'id_*' -o -name '*password*' \) 2>/dev/null); do
  say "  ❌ [殘留] 不應進公開報告的檔案：$f"
  FAIL=1
done

say ""
if [ "$FAIL" -eq 0 ]; then
  say "✅ 掃描通過（0 命中）—— 可進 public repo"
else
  say "❌ 掃描未通過 —— 修正後再提交（勿把修好的檔案留在 git 歷史：先修再 commit，不要先 commit 再修）"
fi
exit "$FAIL"
