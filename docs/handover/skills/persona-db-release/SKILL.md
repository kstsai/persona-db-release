---
name: persona-db-release
description: Persona DB 出貨與部署 — 版本規則、打包（去識別化＋守門掃描）、部署、出貨 SOP、交付產物一致性檢查。
tags: [persona-db, release, packaging, deployment, sop, deidentification]
---

# Persona DB — 出貨與部署

> 觸發時機：要交付新版本、部署到新環境、或重新打包。
> 前置：`persona-db-qa`（驗證）、`DATA-CONTRACT.md`（契約）。

## 1. 版本規則（四者必須一致）

```
VERSION（repo 根目錄） == RELEASE-VERSION（交付目錄） == git tag == tarball 檔名
```
且可再對上：`/app/VERSION`（容器內）、`/personadb/status`、`/openapi.json → info.version`（Swagger 頁首顯示）。

| 變更類型 | 是否 bump 版號 |
|:--|:--|
| `api/*.py`（行為／欄位） | **是** |
| dataset／權重表 | **是** |
| 純文件（`docs/`、`RELEASE-*.md`、註解） | 否 |
| 出貨腳本／斷言腳本 | 否（但要重跑驗證） |

## 2. 打包（含**去識別化與守門**，這是必經步驟）

```
① 寫入 RELEASE-VERSION（必須在 tar **之前** —— 否則 tarball 內會落後一版）
② 打包：排除 .git / .env / 內部工作檔 / agent 內部資料（memory、docs、scripts 等）
③ 去識別化（對**暫存目錄**）：
   內部主機名 → 代號（例 NODE-A/NODE-B）；私網 IP → [private-ip]；產品名／內部服務 → 泛化描述
④ 守門掃描（發現即**中止打包**，不產出有問題的包）：
   憑證樣式（`://<user>:<password>@`、`ghp_*`、`sk-*`、私鑰標頭（`BEGIN …` 系列））、
   內部識別（主機名、私網 IP、節點公鑰）、內部服務名
⑤ 產物自我檢查：tarball 內 `VERSION == RELEASE-VERSION`；解開後能跑起服務
```
> **為什麼要這樣**：交付產物是**對外**的。歷史上曾出現 tarball 內含登入憑證、內部主機名、
> 甚至整份 agent 內部資料（memory／內部文件）→ 因此「掃描」不是選配；
> 且**先修再 commit**（已 commit 的憑證會留在歷史，刪檔不等於移除）。

## 3. 部署

```bash
cd upDockerVerHermes
bash undeploy.sh                                  # 移除舊容器（保留資料）
bash deploy-hermes-personadb-containers.sh --skip-hermes   # 只部署 API（或全部署）
```
部署後必查：

- [ ] `docker exec persona-db-api cat /app/VERSION` == 目標版本
- [ ] `/app/RELEASE` == 目標版本
- [ ] 容器 `healthy`、`RestartCount` 合理
- [ ] **保真度**：tarball 內 `api/*.py` sha256 == 容器內 `/app/api/*.py`（byte 級）
- [ ] `/docs` 可開、`/openapi.json` 的 `info.version` == 部署版本
- [ ] `LOG_LEVEL=INFO` 且 app 的 INFO 行**確實進 log**（讀**原始 log 檔**，不要只看 `docker logs`）

## 4. 出貨 SOP（每次交付照跑）

```
1. 單元測試全綠（scripts/test_*_fixes.py；新增功能要有對應測試）
2. 合約檢查：check_dim_weights.py / check_response_schema.py
3. 真 LLM e2e：代表性案例（含邊界案例），確認 FAILED: 0
4. 出貨驗證套件：upDockerVerHermes/test-persona-db-api.sh → 0 紅旗
5. 產物掃描：憑證／內部識別／產品名 = 0 命中
6. 版本一致性：§1 的四項對齊
7. 寫 RELEASE-<ver>.md：修的項目（票號）、相容性（純新增 vs 行為變更）、驗證紀錄、已知限制
8. 交付：tarball + RELEASE-*.md + docs/handover/（若對方要接手 RD/QA）
```

## 5. 相容性聲明（`RELEASE-*.md` 必寫）

| 類型 | 說明方式 |
|:--|:--|
| 純新增欄位／端點 | 「純新增、有 default → 向後相容」 |
| enum 新增值 | 列出新增值；提醒消費端若有 white-list 需更新 |
| **行為變更** | 明寫「誰會受影響、要改什麼」（例：失敗輪現在會出現在 `broadening_attempts`，以 `len()` 推估成功輪數者需改看 `parse_error=false`） |
| 契約欄位語意變更 | 明寫新舊語意與切換版本 |

## 6. 已知的部署環境陷阱

| 陷阱 | 症狀 | 對策 |
|:--|:--|:--|
| `docker logs` 截斷（log 檔含 NUL hole） | 只吐出極少行、看似「沒有 log」 | 讀原始 log 檔；輸出標明來源 |
| re-deploy 沒生效 | 版本沒變 | 「資料已存在就跳過解壓」的守衛會導致舊碼續跑 → 先 `undeploy` 再 deploy |
| `.env` 被帶進產物 | 憑證外洩 | 打包排除 + 產物掃描（見 §2） |
| 容器讀不到 `VERSION` | 版本顯示不正確 | 確認掛載與工作目錄；`/app/VERSION` 必須存在 |
| 長請求被誤判逾時 | 前端／代理斷線 | `candidates` 需 1–5 分鐘 → 客戶端逾時要放大；Swagger 上不要重複按 |
