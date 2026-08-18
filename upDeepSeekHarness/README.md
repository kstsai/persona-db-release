# upDeepSeekHarness — DeepSeek Harness (dsh) 一鍵部署套件（k8s PaaS 版）

> DeepSeek AI 的 agent harness（`dsh`）部署到你的 Kubernetes PaaS。
> 甲方/使用者只需改 **3 個值**，`kubectl apply` 即可帶起持久化、防誤殺的 dsh Web UI，並從遠端存取。

---

## 📖 給甲方的一頁導讀（這是什麼、怎麼運作）

**upDeepSeekHarness** 把 DeepSeek 官方的 AI agent 工作台（**DeepSeek Harness**，簡稱 **dsh**）打包成一個**邊緣應用程式**，部署在你們的 Kubernetes 平台上（lzc-cp **type 1 edge app**）——它跑在一個 **pod** 裡，由平台統一管理：可持久化、可防誤刪、可遠端存取。

### 三句話看懂架構

1. **dsh = 一個有網頁介面的 AI agent 工作台** — 在瀏覽器裡操作 AI agent：開工作區、跑任務、看執行紀錄。
2. **dsh 的安全設計只允許「本機」開啟**（只能從它自己所在的節點連）— 這是 DeepSeek 官方的保護機制（agent 有執行工具的能力，不能直接暴露到網路），**不是缺陷**。
3. **我們加了一個 nginx pod 當「中介」** — 它站在 dsh 前面，把「只限本機」的 dsh 變成「任何地方都能開」的遠端網頁，並加上 HTTPS 加密。

```
你的瀏覽器 ──HTTPS──> 節點:443（nginx pod = 中介 + 加密）
                        └──> dsh Web UI（AI agent 工作台，pod 內）
```

### 你只需要知道的三件事

| 事項 | 說明 |
|------|------|
| **部署** | 改 3 個值（API key、存取網址、節點 IP）→ 一鍵 script 或 `kubectl apply` |
| **資料** | 資料存在獨立儲存（PVC）— **pod 重啟或刪除，資料不丟**；只有刪儲存才會 |
| **存取** | 瀏覽器直接開 `https://<節點IP>/` — 免 SSH、免登入節點本機 |

### 常見疑問

- **為什麼瀏覽器有憑證警告？** 目前用自簽憑證（沒有第三方認證），按「進階 → 繼續前往」即可；正式上線可換正式 HTTPS 憑證。
- **dsh 的 port 為什麼不能直接連？** dsh 刻意只綁本機（127.0.0.1）— 這是它的安全設計（agent harness 能執行工具，不該暴露給網路）。nginx pod 是正規解法。
- **pod 掛了資料會不見嗎？** 不會。資料在 PVC（`/harness-home`），pod 重建後自動接回。

### 技術架構（給想進一步了解的人）

```
[你的瀏覽器] ──HTTPS──> [nginx pod：中介/反向代理] ──hostNetwork──> [節點本機 127.0.0.1:13082]
                                                                      └─ port-forward ──> [dsh pod 127.0.0.1:3080]
```

| 元件 | 角色 | 說明 |
|------|------|------|
| **dsh pod** | type 1 edge app | DeepSeek Harness Web UI，綁 pod 內 `127.0.0.1:3080`（官方安全設計，runtime 拒絕 `--host 0.0.0.0`） |
| **port-forward** | 常駐通道 | k8s 節點上的 systemd service，把 `13082` 接到 dsh pod 的 `3080`（唯一官方通道） |
| **nginx pod** | 中介/守門員 | 提供遠端 HTTPS 存取；`hostNetwork` 才能連到節點本機的 `13082`；HTTPS 是必須的（dsh UI 的 `crypto.randomUUID()` 只在 secure context 可用） |

> 為什麼不能省掉 nginx、直接用 Service/NodePort？因為 dsh 只聽 pod 內的 127.0.0.1，kube-proxy 的流量打不進去——`kubectl port-forward`（kubelet 通道）是唯一入口，nginx pod 再用 `hostNetwork` 接上這個入口。

## 檔案

| 檔案 | 內容 | 要不要改 |
|:-----|:-----|:---------|
| `00-namespace.yaml` | namespace `dsh`（protected） | 不用 |
| `10-pvc.yaml` | PVC 5Gi（local-path）掛 `/harness-home` | 容量可改 |
| `20-secret.yaml` | **DEEPSEEK_API_KEY（填你的 LLM key）** | **必改 ①** |
| `30-deployment.client.yaml` | Deployment（initContainer 預裝 + protected）— **⚠️ 範本，編輯後才能 apply** | **改 ②**（trusted-host） |
| `40-service.yaml` | Service（3080） | 不用 |
| `50-nginx-reverse-proxy.yaml` | nginx pod（HTTPS 自簽，遠端存取） | 看情境 |

## 快速開始（甲方）

### 一鍵 script（最快）

```bash
# 改 deploy-dsh.sh 頂部 3 個值（NODE_HOSTNAME / NODE_IP / 20-secret.yaml 的 key）
bash deploy-dsh.sh
# → 自動: apply 套件 + 注入 key + port-forward service + nginx HTTPS
```

### 手動方式（了解每一步）

改 3 個值：

```bash
# ① 你的 LLM API key
kubectl patch secret dsh-api-key -n dsh --type merge \
  -p '{"stringData":{"DEEPSEEK_API_KEY":"<YOUR_REAL_KEY>"}}'

# ② 30-deployment.client.yaml 的 --trusted-host（browser-trust fence 要認得你的存取網址）
#    填「你瀏覽器實際打的網址 host」— 不是 pod IP！
#    - localhost（永遠留，本機 port-forward 用）
#    - <BROWSER_ACCESS_HOSTNAME> = 瀏覽器開的 hostname（如 mynode.corp.net；沒有就刪掉這參數）
#    - <BROWSER_ACCESS_IP>       = 瀏覽器開的 IP（如 https://10.0.0.5/ 就填 10.0.0.5）
#    例: 瀏覽器開 https://mynode.corp.net/ → --trusted-host localhost --trusted-host mynode.corp.net

# ③ 若要遠端存取（非本機）→ 50-nginx-reverse-proxy.yaml 的憑證 CN 改你的 hostname
```

### apply

```bash
kubectl apply -f 00-namespace.yaml
kubectl apply -f 10-pvc.yaml -f 20-secret.yaml
kubectl apply -f 30-deployment.client.yaml -f 40-service.yaml
kubectl get pods -n dsh -w
# → 第一次 initContainer 安裝 dsh 需 5-10 分鐘（正常），之後秒起
```

### 本機存取

```bash
kubectl port-forward -n dsh svc/dsh-web 3080:3080
# → http://localhost:3080
```

### 遠端存取（nginx HTTPS pod）

```bash
# 1. 產生自簽憑證（CN 改你的 hostname）
openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -keyout certs/dsh-key.pem -out certs/dsh-cert.pem \
  -subj "/CN=<YOUR_HOSTNAME>" \
  -addext "subjectAltName=DNS:<YOUR_HOSTNAME>,IP:<YOUR_NODE_IP>,IP:127.0.0.1"

# 2. 注入憑證 secret
kubectl delete secret dsh-nginx-certs -n dsh 2>/dev/null
kubectl create secret generic dsh-nginx-certs -n dsh \
  --from-file=dsh-cert.pem=certs/dsh-cert.pem \
  --from-file=dsh-key.pem=certs/dsh-key.pem

# 3. 起 port-forward systemd service（k8s host 上，讓 nginx 有目標可 proxy）
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/dsh-portforward.service <<'EOF'
[Unit]
Description=dsh Web UI port-forward (13082 -> 3080)
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/kubectl port-forward -n dsh svc/dsh-web 13082:3080
Restart=always
RestartSec=5
[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload && systemctl --user enable --now dsh-portforward

# 4. 起 nginx pod
kubectl apply -f 50-nginx-reverse-proxy.yaml

# 5. 瀏覽器開（tailnet/內網）
# https://<YOUR_NODE_IP>/
# （自簽憑證首次按「進階 → 繼續前往」）
```

## 設計要點

### 1. 持久化（PVC）
- `HOME=/harness-home` → dsh 資料（SessionEvent log / profiles / storages）全在 PVC
- **殺 pod 沒關係，殺 PVC 才有事**

### 2. 防誤殺（4 層）
terminationGracePeriod 120s + protected label + PVC 獨立 + RBAC（正式化補）

### 3. 啟動策略（initContainer）
第一次 `npx @deepseek-ai/dsh` 冷安裝 5-10 分鐘 → initContainer 預裝（無 probe 干擾）→ main 秒起

### 4. 儲存選型
單節點 → `local-path`；多節點/HA → 改 `storageClassName: longhorn`

## 已知限制（重要）

- **dsh 刻意只綁 127.0.0.1**（agent harness RCE 安全設計，runtime 硬拒絕 `--host 0.0.0.0`）→
  `http://<node>:<nodePort>/` 連不上是**預期行為**。存取一律 port-forward 或 nginx 反向代理
- **為什麼要 HTTPS**：dsh UI 用 `crypto.randomUUID()`，只在 secure context（HTTPS/localhost）可用
- **browser-trust fence**：/api 檢查 Host + Origin + sec-fetch-site。新增存取 hostname 時，
  要加進 `--trusted-host`（30-deployment.client.yaml），否則 UI fetch 回 403
- **⚠️ Known issue：「設置 → 模型」頁面經遠端存取會 403**（`/api/settings.describe`）— dsh 設計上 settings API 是 **loopback-only**（安全考量，防遠端窺探 API key / 改設定）。**不是故障，不修**。UI 對話/agent 功能正常（key 已由 secret 注入）。模型設定請在本機（port-forward localhost）操作
- dsh 仍在 **developer preview**（breaking changes 風險）
- initContainer 首次安裝需外網（npm registry）；離線環境需先 build image

## 排錯

- **pod 0/1**：probe 必須 exec 型（tcpSocket 打 pod IP 會被 dsh 拒）。確認 deployment 的 readinessProbe 是 `curl -sf http://127.0.0.1:3080/`
- **添加工作區失敗 `crypto.randomUUID`**：你走 HTTP 了 → 用 HTTPS（nginx pod）或 localhost
- **UI fetch 403**：trusted-host 沒包含你的 hostname → 補進 30-deployment.client.yaml
- **nginx pod Pending（no free ports）**：舊 pod 佔 host port → `kubectl delete pod --force --grace-period=0`

## 來源

- lzc-cp 專案實作（lab-riscv/dsh/），由 hermesa2 依協作協定產出，2026-08-17
- 完整踩坑紀錄: lab-riscv `tutorlogs/dsh-pod-nginx-https-fence.md`
