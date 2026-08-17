#!/bin/bash
# =============================================================
# dsh pod — undeploy/cleanup script（lzc 專用）
# 用途: fresh verify issue #30 — 把 dsh 相關資源全部清掉，模擬甲方全新環境
# 用法: bash scripts/undeploy-dsh-pod.sh [--force]
#   --force: 跳過互動確認（用於 CI / 自動化）
#
# ⚠️ 警告（防誤殺設計，刻意要你確認）:
#   1. 這會刪掉 namespace dsh（含 PVC）→ dsh1 的 session / skills / credentials 全部清除！
#   2. 真 key 在 lab-riscv/dsh-secret.yaml（gitignored）→ 不會被刪，fresh 後可重新注入
#   3. 備份: 若要保留資料，先 kubectl exec ... tar /harness-home 再跑本 script
# =============================================================
set -euo pipefail

FORCE=0
for arg in "$@"; do
  [ "$arg" = "--force" ] && FORCE=1
done

echo "======================================================"
echo " dsh pod undeploy — 會刪除以下資源:"
echo "   - namespace dsh (含 PVC dsh-home-pvc → 資料全清!)"
echo "   - Deployment dsh-web / dsh-nginx"
echo "   - Service dsh-web"
echo "   - Secrets dsh-api-key / dsh-nginx-certs"
echo "   - ConfigMap dsh-nginx-conf"
echo "   - port-forward systemd service (dsh-portforward)"
echo "======================================================"

if [ "$FORCE" != "1" ]; then
  echo
  read -rp "確定要刪除 dsh 全部資源？（輸入 yes 確認）: " ans
  [ "$ans" = "yes" ] || { echo "已取消"; exit 1; }
fi

echo
echo "=== [1/5] 停 + 移除 port-forward systemd service ==="
if systemctl --user is-active dsh-portforward.service >/dev/null 2>&1; then
  systemctl --user stop dsh-portforward.service 2>/dev/null || true
  systemctl --user disable dsh-portforward.service 2>/dev/null || true
  rm -f "$HOME/.config/systemd/user/dsh-portforward.service"
  systemctl --user daemon-reload
  echo "  ✅ service 已停 + 移除"
else
  echo "  （service 不在，跳過）"
fi
# 清殘留 port-forward process（若有）
pkill -f "port-forward -n dsh" 2>/dev/null && echo "  ✅ 殘留 port-forward process 已清" || true

echo "=== [2/5] 刪 nginx pod 資源 ==="
kubectl delete deployment dsh-nginx -n dsh --ignore-not-found --wait=false 2>&1 | head -1
kubectl delete configmap dsh-nginx-conf -n dsh --ignore-not-found 2>&1 | head -1
kubectl delete secret dsh-nginx-certs -n dsh --ignore-not-found 2>&1 | head -1

echo "=== [3/5] 刪 dsh 核心資源 ==="
kubectl delete deployment dsh-web -n dsh --ignore-not-found --wait=false 2>&1 | head -1
kubectl delete service dsh-web -n dsh --ignore-not-found 2>&1 | head -1
kubectl delete secret dsh-api-key -n dsh --ignore-not-found 2>&1 | head -1

echo "=== [4/5] 刪 PVC（資料清除 — fresh verify 需要）==="
kubectl delete pvc dsh-home-pvc -n dsh --ignore-not-found 2>&1 | head -1

echo "=== [5/5] 刪 namespace dsh ==="
kubectl delete namespace dsh --ignore-not-found 2>&1 | head -1

echo
echo "=== 等待資源完全退場（最多 60s）==="
for i in $(seq 1 12); do
  if ! kubectl get namespace dsh >/dev/null 2>&1; then
    echo "  ✅ namespace dsh 已消失"
    break
  fi
  sleep 5
done

echo
echo "=== 驗證：全部清空 ==="
kubectl get ns dsh 2>&1 | head -2
kubectl get all -n dsh 2>&1 | head -3
ss -tlnp 2>/dev/null | grep -E ":13080 |:13082 |:443 " | grep -i kubectl && echo "  ⚠️ 還有殘留監聽" || echo "  ✅ 無殘留 port 監聽"

echo
echo "======================================================"
echo " ✅ dsh pod 已完全 undeploy"
echo "    接下來可以 fresh verify:"
echo "      bash scripts/setup-dsh-pod.sh"
echo "      （或照 README 手動 apply）"
echo "======================================================"
