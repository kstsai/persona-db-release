# Persona DB — Release

台灣人口加權合成人設資料庫（1069 人設）的釋出版本。

## 內容

- **`upDockerVerHermes/`** — Docker 容器部署版（含 Hermes Agent + Persona DB API）
  - [部署說明](upDockerVerHermes/README.md)
  - `deploy-persona-db-compose.sh` — 一鍵部署腳本
  - `test-persona-db-api.sh` — API 測試腳本
- **`qa-reports/`** — LLM Verify QA：同一測試腳本對多版本的跨版本實測報告（**byte 級證據，可複驗**）
  - [報告索引](qa-reports/README.md)
  - 涵蓋 v4.9.2 / v5.2 / v5.3.1 / v5.4 / v5.6，共 4 種 API 契約
  - 每包含 `ANALYSIS.md`（主報告）、`README.md`（可執行複驗指令）、原始 evidence（`raw/` `headers/` `meta/`）

- **`docs/`** — 交付參考文件
  - [AI Agent 上線參考文件](docs/agent-onboarding-reference.md) — 交付體系中 always-on QA agent 的上線／交接程序（九條 gate、能力授予治理、WSL 宿主實戰案例）
