# Persona DB Release — Docker 容器部署版

Persona DB（台灣人口加權合成人設資料庫）的 Docker 容器化部署版本，包含：

- **Hermes Agent** — AI 代理容器 (optional)
- **Persona DB API** — REST API 服務（FastAPI）

## 快速開始

```bash
# 完整部署（含 Hermes 容器）
cd upDockerVerHermes
bash deploy-persona-db-compose.sh

# API-only 部署（無 Hermes，適合 edge VM 或空間不足）
bash deploy-persona-db-compose.sh --skip-hermes

# 測試 API
bash test-persona-db-api.sh
```

## 產品文件

- [persona-db.md](persona-db.md) — 產品規格與版本演進（1069 人設 / 19 維度 / 23 QA rules，v3.7 → v4.9.1）

## 目錄結構

```
upDockerVerHermes/
├── deploy-persona-db-compose.sh   # 主部署腳本
├── docker-compose.yml             # Docker Compose（可選，腳本已內建邏輯）
├── test-persona-db-api.sh         # API 測試腳本
├── pocDemo.env                    # Demo 環境變數範本
├── persona-db.md                  # 產品文件（規格 + 版本演進）
├── persona-db-rel-v3.2.tar.gz      # Versioned release (persona-db-rel-<VERSION>.tar.gz)
├── RELEASE-VERSION                 # Current release tag (e.g., v3.2)
└── deploy-persona-db-api.sh       # 舊版單容器部署腳本
```

## 環境變數

| 變數 | 預設值 | 說明 |
|:----|:-------|:-----|
| `PERSONA_DB_DATA` | `/srv/persona-db-data` | 共享資料目錄（JSON + API code） |
| `HERMES_HOME` | `/home/ubuntu/.hermes` | Hermes 設定目錄 |
| `API_PORT` | `8000` | API 連接埠 |
| `SUDO_PASSWORD` | (unset) | sudo 密碼（如 VM 沒有 passwordless sudo） |

## API 端點

| 端點 | 方法 | 說明 |
|:----|:----|:------|
| `/health` | GET | 健康檢查 |
| `/personadb/status` | GET | 完整狀態（版本、QA、LLM 狀態） |
| `/personadb/candidates` | GET | 人設篩選（支援自然語言查詢） |

### 測試 API

```bash
# 狀態
curl http://localhost:8000/personadb/status

# 篩選人設
curl --get "http://localhost:8000/personadb/candidates" \
  --data-urlencode "questions=康是美的目標客戶" \
  --data-urlencode "top_k=3" \
  --data-urlencode "opMode=僅篩選"
```

---

## Troubleshooting

### 1. 磁碟空間不足

**症狀：** `No space left on device` 或 deploy 腳本在 Step 4 失敗

**解法：**
```bash
# 清 Docker 無用資源
sudo docker system prune -af

# 清 apt cache + journal
sudo apt-get clean
sudo journalctl --vacuum-time=1d

# 檢查空間
df -h /
```

API-only 模式只需 ~1GB，強烈建議 **edge VM 用 `--skip-hermes`**。

### 2. Sudo 需要密碼

**症狀：** `sudo: a terminal is required to read the password` 或 `sudo: a password is required`

**解法 A — 設定 SUDO_PASSWORD：**
```bash
export SUDO_PASSWORD=your_password
bash deploy-persona-db-compose.sh
```

**解法 B — 先手動建目錄：**
```bash
sudo mkdir -p /srv/persona-db-data
sudo chown ubuntu:ubuntu /srv/persona-db-data
sudo mkdir -p /home/ubuntu/.hermes/{cron,sessions,memories,skills,persona,persona-tools,logs}
sudo chown -R ubuntu:ubuntu /home/ubuntu/.hermes
```

**解法 C — 設定 passwordless sudo：**
```bash
echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$USER
```

### 3. Docker 權限不足

**症狀：** `permission denied while trying to connect to the Docker daemon socket`

**解法：**
```bash
# 將使用者加入 docker group
sudo usermod -aG docker $USER
newgrp docker  # 或重新登入
```

### 4. Docker Hub 超慢或無法連線

**症狀：** `docker pull` 卡很久或 timeout

**原因：** 部分 edge VM 到 Docker Hub 的頻寬極低（曾觀測到 <100 B/s）

**解法：**
```bash
# 改用 API-only 模式（跳過 hermes image pull）
bash deploy-persona-db-compose.sh --skip-hermes

# 事後想補 hermes 容器時，可從另一台機器拉好後 export/import：
# 有 Docker 的機器上：
docker save nousresearch/hermes-agent:latest | gzip > hermes-image.tar.gz
scp hermes-image.tar.gz user@edge-vm:~/
# edge VM 上：
docker load < hermes-image.tar.gz
```

### 5. 容器啟動後 API 沒回應

**解法：**
```bash
# 檢查容器狀態
docker ps -a | grep persona-db-api

# 看 logs
docker logs persona-db-api --tail 50

# 如果一直 restarting，可能是 .env 問題
cat /srv/persona-db-data/.env
```

---

## 完整部署 vs API-only 比較

| 項目 | 完整部署 | API-only (--skip-hermes) |
|:----|:--------:|:------------------------:|
| Container 數量 | 2 (hermes + api) | 1 (api) |
| Docker Hub pull | ~3.8GB (hermes image) | 無（API 從 Dockerfile 本地 build） |
| 所需磁碟空間 | ~5GB | ~1GB |
| 功能 | Hermes CLI + API | 僅 REST API |
| 部署時間 | 變數（取決於網路） | ~2 分鐘 |

---

## Hermes Container — 甲方啟用指南

Hermes container 啟動後預設已設定好 **custom:deepseek-pro** provider（指向 DeepSeek API）。甲方可選擇以下兩種方式啟用對話功能：

### 選項 A：使用 DeepSeek API Key（最簡單）

```bash
# 1. 將自己的 DeepSeek API Key 寫入 Hermes .env
echo "LLM_API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" | sudo tee /home/ubuntu/.hermes/.env

# 2. 重啟 Hermes container 載入新 key
docker restart hermes

# 3. 開始對話
docker exec -it hermes hermes chat
```

### 選項 B：使用 Nous Portal 訂閱（OAuth）

若甲方已有 Nous Research 的 Portal 訂閱，可透過 OAuth 登入使用：

```bash
# 1. 登入 Nous Portal（會印出一組 URL）
docker exec -it hermes hermes auth add nous
#    → Open: https://portal.nousresearch.com/manage-subscription?user_code=XXXX-XXXX
#       （在自己電腦的瀏覽器打開此 URL，登入授權）

# 2. 選取 provider 與 model
docker exec -it hermes hermes model --no-browser
#    → 選單會列出所有可用 provider（含 Nous Portal、DeepSeek 等）
#       方向鍵選擇，Enter 確認

# 3. 開始對話
docker exec -it hermes hermes chat
```

### 切換 provider

```bash
# 查看目前 provider 與 model
docker exec hermes hermes config get model

# 切到其他 provider（例如從 custom:deepseek-pro 改回 Nous）
docker exec hermes hermes config set model.default <model-name>
docker exec hermes hermes config set model.provider <provider-name>
docker restart hermes
```

### 內建已設定的 custom provider

部署腳本會自動在 config.yaml 寫入以下設定，讓 Hermes container 開箱即用 DeepSeek：

```yaml
custom_providers:
  - name: deepseek-pro
    base_url: https://api.deepseek.com
    api_key_env: LLM_API_KEY

model:
  default: deepseek-v4-flash
  provider: custom:deepseek-pro
```

---

## A3 克隆 SOP — 從零部署 persona-db-release 到新 VM

此 SOP 記錄從一台全新 Ubuntu VM 上完整部署 Hermes + Persona DB API 的標準流程。

### 前置作業

| 項目 | 需求 |
|:----|:-----|
| **OS** | Ubuntu 22.04+ |
| **磁碟** | 完整部署需 ≥10GB，API-only 需 ≥3GB |
| **網路** | 需能連 Docker Hub、GitHub、DeepSeek API |
| **Docker** | 24+ (建議使用 Ubuntu 內建 `docker.io`) |
| **API Key** | DeepSeek API key（寫入 `~/.env`） |

### Step-by-Step

```bash
# 1. 安裝 Docker + 加入 docker group
sudo apt update && sudo apt install -y docker.io
sudo usermod -aG docker $USER
newgrp docker   # 或重新登入

# 2. 設定 DeepSeek API Key
cat > ~/.env << 'EOF'
LLM_API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
LLM_MODEL=deepseek-v4-flash
LLM_BASE_URL=https://api.deepseek.com
EOF

# 3. 克隆 repo
git clone https://github.com/kstsai/persona-db-release.git
cd ~/persona-db-release/upDockerVerHermes

# 4. 部署（完整版含 Hermes container）
bash deploy-hermes-personadb-containers.sh

# 5. 測試 API
bash test-persona-db-api.sh
```

### 部署模式

| 模式 | 指令 | 用途 |
|:----|:------|:------|
| **完整部署** | `bash deploy-hermes-personadb-containers.sh` | 含 Hermes CLI + API，適合完整交付 |
| **API-only** | `bash deploy-hermes-personadb-containers.sh --skip-hermes` | 僅 API，適合 edge VM 或空間有限 |
| **清除** | `bash undeploy.sh` | 停止容器 + 刪除資料 |

### 驗收檢查

每項結果都應為 ✅：

```bash
# (1) 容器狀態
docker ps --format 'table {{.Names}}\t{{.Status}}'

# (2) API 健康檢查
curl -s http://localhost:8000/health

# (3) API 完整狀態
curl -s http://localhost:8000/personadb/status

# (4) LLM 篩選測試
curl -s --get "http://localhost:8000/personadb/candidates" \
  --data-urlencode "questions=TESLA的目標客戶" \
  --data-urlencode "top_k=3" \
  --data-urlencode "opMode=僅篩選"

# (5) Hermes 自訂 provider 確認
docker exec hermes hermes config get model
# → default: deepseek-v4-flash, provider: custom:deepseek-pro

# (6) Hermes 對話測試
docker exec -it hermes hermes chat -q "persona-db status"
# → 應顯示 1069 personas, QA 23 rules ALL PASS, Version (read from data)
```

### 已知注意事項

| # | 事項 | 說明 |
|:--|:-----|:------|
| 1 | **`~/.env` 必須事先存在** | deploy 腳本會從這裡讀取 API key 注入 container |
| 2 | **磁碟空間** | `docker pull hermes-agent:latest` 約 3.8GB，API build 約 500MB |
| 3 | **Container 啟動順序** | API → 等 3s healthcheck → Hermes → 建立 symlink |
| 4 | **Hermes container 重新啟動** | `undeploy.sh` 再重新 deploy，或手動 `docker rm -f hermes; docker run ...` |
| 5 | **uid 10000 問題** | 如果 `.hermes/` 檔案變成 uid 10000，執行 `sudo chown -R ubuntu:ubuntu ~/.hermes/` |
| 6 | **Sudo 密碼** | 若 VM 無 passwordless sudo，設 `export SUDO_PASSWORD=...` 再執行 deploy |

---

## Release 版本管理

### Tarball 命名規則

```
persona-db-rel-<VERSION>.tar.gz     # e.g., persona-db-rel-v3.2.tar.gz
```

`VERSION` 來自 source repo 的 `hermesa3/persona/VERSION`，與 persona 資料版本同步。

### 發佈新版本流程

```bash
# 1. 在 persona-db repo 更新資料或 bump 版號
cd ~/persona-db
echo "v3.3" > VERSION

# 2. 打包（會自動讀取 VERSION）
bash pack-persona-db-release.sh
# → 產出 persona-db-rel-v3.3.tar.gz + RELEASE-VERSION

# 3. 複製到 persona-db-release repo
cp persona-db-rel-v3.3.tar.gz ~/persona-db-release/upDockerVerHermes/
cp RELEASE-VERSION ~/persona-db-release/upDockerVerHermes/
# 移除舊版 tarball（可選）
rm ~/persona-db-release/upDockerVerHermes/persona-db-rel-v3.2.tar.gz

# 4. Commit + push
cd ~/persona-db-release
git add -A
git commit -m "release: persona-db v3.3"
git push origin main

# 5. dh5 或其他部署端更新
cd ~/persona-db-release && git pull origin main
# deploy 腳本會自動找到最新 tarball
bash upDockerVerHermes/deploy-hermes-personadb-containers.sh
```

### Deploy 腳本行為

- 自動掃描 `upDockerVerHermes/` 下所有 `persona-db-rel-*.tar.gz`
- 若有多個，選 **版本號最高** 的那個
- 顯示選擇的 tarball 名稱與版本標籤
- 不再 hardcode VERSION — 版本完全由 tarball 內的資料決定
