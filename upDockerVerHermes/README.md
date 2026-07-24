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

## 目錄結構

```
upDockerVerHermes/
├── deploy-persona-db-compose.sh   # 主部署腳本
├── docker-compose.yml             # Docker Compose（可選，腳本已內建邏輯）
├── test-persona-db-api.sh         # API 測試腳本
├── pocDemo.env                    # Demo 環境變數範本
├── persona-db-rel-1.0.tar.gz      # Persona DB 資料 + API 程式碼壓縮檔
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
