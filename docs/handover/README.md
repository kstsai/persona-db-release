# Persona DB — 交接包（Handover Package）

> **給誰**：接手 Persona DB 後續 **RD / QA / 資料生產** 的團隊（人或 AI agent）。
> **目的**：讓你在**不接觸原開發團隊內部環境**的前提下，獨立完成
> ① 以新版規格與新資料集**重建／擴充人設資料庫** ② 執行**驗證** ③ **出貨**與部署。
> **形式**：`HANDOVER-PROMPT.md` 是一份可直接貼進 AI agent 的**前文（preamble）**；
> `skills/` 下三份是同一套流程的**可匯出技能文件**（Agent Skills 格式，也可當人工作業手冊）。

---

## 檔案清單與閱讀順序

| 順序 | 檔案 | 內容 | 什麼時候看 |
|:-:|:--|:--|:--|
| 1 | `HANDOVER-PROMPT.md` | **起始前文**：角色、環境、五條鐵則、兩個核心迴圈、任務範本 | 每次開新 session 先貼這段 |
| 2 | `DATA-CONTRACT.md` | 資料契約：persona JSON 結構、維度清單、一致性規則、權重表、資料來源 | 動任何資料前 |
| 3 | `skills/persona-db-regen/SKILL.md` | **重建／擴充資料庫**的完整流程與決策樹 | 要產出新一組人設時 |
| 4 | `skills/persona-db-qa/SKILL.md` | **驗證**：出貨驗證腳本、斷言設計規則、報告判讀紀律 | 驗證前後、判讀結果時 |
| 5 | `skills/persona-db-release/SKILL.md` | **出貨**：打包、去識別化守門、部署、版本一致性 | 要交付新版本時 |
| — | `../swagger-quickstart.md` | 用 Swagger 產出第一批人設（操作者用） | 第一次上手操作 API |
| — | `../../upDockerVerHermes/test-persona-db-api.sh` | 出貨驗證套件（9 案例 + 60+ 斷言） | 每次出貨前 |
| — | `../../THIRD-PARTY-DATA.md` | **第三方資料來源與授權清單**（22 維度逐一對照、哪些需授權） | 法務／授權 review 時 |
| — | `SOURCE-LICENSING-MEMO.md` / `.pdf` | **一頁摘要**（法務 review 用）：結論三句話、需授權來源、假設值、檢查表 | 開法務會時 |
| — | `../../../persona-db.md` | 產品全貌與版本演進 | 想了解歷史脈絡 |

> 交付包內的 `concepts/`（設計知識 14 篇）、`sources/`（原始統計資料）、
> `tw-persona-db-rfc.md`（規格書）是**規格的權威來源**；本交接包是「**怎麼用它**」的操作層。

---

## 你接手後的三個主要工作

| 工作 | 入口 | 產出 |
|:--|:--|:--|
| **A. 資料生產** | `skills/persona-db-regen` | 新的一組 persona dataset（`tw_persona_1069.json` 或新檔）＋ 權重表 |
| **B. 驗證** | `skills/persona-db-qa` | 驗證報告（含「空轉／未行使」如實標示）＋ 缺陷票 |
| **C. 出貨** | `skills/persona-db-release` | 版本化 tarball + 部署 + 出貨驗證全綠 |

---

## 邊界（本包**不**包含）

- 原團隊的內部環境細節（內部主機、憑證、內部協作工具與其設定）
- 內部人員／專案名稱對應、內部 issue 編號歷程（**功能內容**已留在 `RELEASE-*.md` 與 `persona-db.md`）
- 任何密鑰（本包經產物掃描：憑證 0、內部位址 0、agent 內部資料 0）

> 需要原團隊環境才能重現的項目，請以「**方法論**」取代「**特定主機**」來理解：
> 例如驗證報告提到「透過私有網路遠端存取受測節點」，那是**驗證方法**，不是對你環境的要求。

---

## 快速開始（三行）

```bash
# 1) 看規格與資料契約
sed -n '1,80p' tw-persona-db-rfc.md && cat docs/handover/DATA-CONTRACT.md

# 2) 跑一次現行版本的驗證（確認你手上的環境能動）
bash upDockerVerHermes/test-persona-db-api.sh      # 需服務已在跑

# 3) 要重建資料庫 → 開新 session，把 HANDOVER-PROMPT.md 貼進去，接任務範本 ①
```
