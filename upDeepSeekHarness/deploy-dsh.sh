#!/bin/bash
# =============================================================
# dsh pod instance — 一鍵部署 script（public 版）
# 位置: upDeepSeekHarness/deploy-dsh.sh
# 用途: 在 k8s host 上建立 dsh pod + port-forward service + nginx HTTPS
# 用法: bash deploy-dsh.sh [--skip-apply] [--skip-key]
# 依賴: kubectl, 本目錄的 yaml 檔（00/10/20/30/40/50）
#
# ⚠️ 甲方必改（3 個值）:
#   1. NODE_HOSTNAME / NODE_IP — 你的機器 hostname / IP（nginx HTTPS 存取用）
#   2. 20-secret.yaml 的 DEEPSEEK_API_KEY（或用 --skip-key + 手動 patch）
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DSH_DIR="$SCRIPT_DIR"
NS="dsh"
NODE_PORT_HOST="13082"   # 本機 port-forward 用的 localhost port
NODE_HOSTNAME="YOUR_HOSTNAME"   # ← 改成你的 hostname（如 mynode.corp.net）
NODE_IP="YOUR_NODE_IP"          # ← 改成你的 k8s node IP
DO_APPLY="yes"
DO_KEY="yes"

for arg in "$@"; do
  case "$arg" in
    --skip-apply) DO_APPLY="no" ;;
    --skip-key) DO_KEY="no" ;;
  esac
done

echo "=== [1/5] 前置檢查 ==="
command -v kubectl >/dev/null || { echo "X kubectl 未安裝"; exit 1; }
kubectl get nodes >/dev/null 2>&1 || { echo "X k3s 不可用"; exit 1; }
[ -d "$DSH_DIR" ] || { echo "X 找不到 dsh/ 目錄: $DSH_DIR"; exit 1; }
echo "OK kubectl + k3s + dsh/ 就緒"

echo "=== [2/5] apply 套件 (namespace -> pvc/secret -> deployment/service) ==="
if [ "$DO_APPLY" = "no" ]; then
  echo "  (--skip-apply，跳過)"
else
  kubectl apply -f "$DSH_DIR/00-namespace.yaml"
  kubectl apply -f "$DSH_DIR/10-pvc.yaml" -f "$DSH_DIR/20-secret.yaml"
  kubectl apply -f "$DSH_DIR/30-deployment.yaml" -f "$DSH_DIR/40-service.yaml"
  echo "OK apply 完成"
fi

echo "=== [3/5] API key 注入 (k8s secret) ==="
if [ "$DO_KEY" = "no" ]; then
  echo "  (--skip-key，跳過)"
else
  # 從 gitignored 的 dsh-secret.yaml 讀真 key（若有）
  REAL_KEY=""
  if [ -f "$SCRIPT_DIR/../dsh-secret.yaml" ]; then
    REAL_KEY=$(grep '^  DEEPSEEK_API_KEY:' "$SCRIPT_DIR/../dsh-secret.yaml" | head -1 | awk '{print $2}' | tr -d '"')
  fi
  if [ -z "$REAL_KEY" ] || [ "$REAL_KEY" = "REPLACE_ME_WHEN_KEY_ARRIVES" ]; then
    echo "  ! 無真 key（dsh-secret.yaml 缺或 placeholder），跳過注入"
    echo "     kubectl patch secret dsh-api-key -n dsh --type merge -p '{\"stringData\":{\"DEEPSEEK_API_KEY\":\"<YOUR_KEY>\"}}'"
  else
    kubectl patch secret dsh-api-key -n $NS --type merge -p "{\"stringData\":{\"DEEPSEEK_API_KEY\":\"$REAL_KEY\"}}" >/dev/null
    echo "  OK k8s secret patched (len=${#REAL_KEY})"
  fi
fi

echo "=== [4/5] 等 pod Ready (首次 initContainer 安裝需 5-10 分鐘) ==="
kubectl get pods -n $NS 2>/dev/null || true
echo "  (若尚未 ready，kubectl get pods -n dsh -w 觀察)"

echo "=== [5/5] port-forward systemd service ==="
SERVICE_FILE="$HOME/.config/systemd/user/dsh-portforward.service"
if systemctl --user is-active dsh-portforward.service >/dev/null 2>&1; then
  echo "  OK service 已 active"
else
  mkdir -p "$HOME/.config/systemd/user"
  cat > "$SERVICE_FILE" << EOF
[Unit]
Description=dsh Web UI port-forward ($NODE_PORT_HOST -> 3080)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/kubectl port-forward -n $NS svc/dsh-web $NODE_PORT_HOST:3080
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable dsh-portforward.service
  systemctl --user restart dsh-portforward.service
  echo "  OK service 安裝並啟動"
fi
sleep 4
ss -tlnp 2>/dev/null | grep -q "$NODE_PORT_HOST" && echo "  OK $NODE_PORT_HOST LISTENING" || echo "  ! 尚未監聽"

echo "=== [5b] nginx HTTPS pod（遠端存取，取代 SSH tunnel）==="
if kubectl get deploy dsh-nginx -n $NS >/dev/null 2>&1; then
  echo "  OK nginx pod 已存在"
else
  # 產生自簽憑證（若 certs/ 不存在）
  CERT_DIR="$SCRIPT_DIR/../certs"
  if [ ! -f "$CERT_DIR/dsh-cert.pem" ]; then
    mkdir -p "$CERT_DIR"
    echo "  產生自簽憑證 (CN=${NODE_HOSTNAME})..."
    openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
      -keyout "$CERT_DIR/dsh-key.pem" -out "$CERT_DIR/dsh-cert.pem" \
      -subj "/CN=${NODE_HOSTNAME}" \
      -addext "subjectAltName=DNS:${NODE_HOSTNAME},IP:${NODE_IP},IP:127.0.0.1" 2>/dev/null
    echo "  OK 憑證產生"
  fi
  # 注入憑證 secret（delete + create，避免 placeholder merge 問題）
  kubectl delete secret dsh-nginx-certs -n $NS --ignore-not-found >/dev/null 2>&1
  kubectl create secret generic dsh-nginx-certs -n $NS \
    --from-file=dsh-cert.pem="$CERT_DIR/dsh-cert.pem" \
    --from-file=dsh-key.pem="$CERT_DIR/dsh-key.pem" >/dev/null
  echo "  OK 憑證 secret 注入"
  # apply nginx pod
  kubectl apply -f "$SCRIPT_DIR/50-nginx-reverse-proxy.yaml" >/dev/null
  echo "  OK nginx pod applied"
fi
# 等 nginx 綁 443（hostNetwork）
sleep 8
ss -tlnp 2>/dev/null | grep -q ":443 " && echo "  OK 443 LISTENING (nginx HTTPS)" || echo "  ! 443 尚未監聽"

echo
echo "======================================================"
echo " OK dsh setup 完成"
echo "    本機:         http://localhost:$NODE_PORT_HOST/"
echo "    遠端 (tailnet/內網):  https://${NODE_IP}/"
echo "                  （自簽憑證首次按「進階 -> 繼續前往」）"
echo "    UI 填 key:    Settings -> Models -> DeepSeek（或已由 secret 注入）"
echo "======================================================"
