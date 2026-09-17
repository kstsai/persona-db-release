# Swagger 快速上手 — 產生第一批人設

> 適用版本：**v5.15**（`/personadb/status` 可查現行版本）
> 本文給**操作者**看：用瀏覽器在 Swagger UI 上產出第一批人設。不需寫程式。

---

## 0. 前置

| 項目 | 值 |
|:--|:--|
| 服務位址 | `http://<節點位址>:8000`（以下以 `http://HOST:8000` 代稱） |
| 認證 | **不需要**（API 免認證；LLM 金鑰由服務端設定） |
| 介面 | Swagger UI：`http://HOST:8000/docs`（另有 ReDoc：`/redoc`） |

先用瀏覽器開 `http://HOST:8000/personadb/status`（或 `/health`）確認服務活著。

---

## 1. 打開 Swagger UI

瀏覽器前往 **`http://HOST:8000/docs`**。畫面由上而下會看到：

1. 標題區（`Persona DB API`）— 顯示 API 名稱、**版本**
2. 端點清單（可展開）：
   - `GET /personadb/candidates` — **產出第一批人設（主要入口）**
   - `GET /personadb/detail` — 取單一人設的完整內容
   - `GET /personadb/status` / `GET /health` — 服務狀態

> ⚠️ **標題區顯示的「版本」是 API 文件的版本欄位，可能與實際產品版號不同**。
> 要確認實際版本請看 `/personadb/status` 的 `version` 欄位（本批交付為 **v5.15**）。

---

## 2. 產出第一批人設：`GET /personadb/candidates`

1. 展開 `GET /personadb/candidates` → 按右側 **「Try it out」**
2. 填參數：

| 參數 | 必填 | 預設 | 說明 |
|:--|:-:|:--|:--|
| `questions` | ✅ | — | 你要找什麼樣的族群。**多題用 `|` 分隔**（例：`小資族通勤族|重視價格`） |
| `top_k` | | `20` | 要回傳幾個人設，**1–100** |
| `opMode` | | `僅篩選` | `僅篩選` / `篩選+模擬` / `模擬詢問`（**只能填這三個值**，否則回 400） |
| `role` | | 空 | 詢問者角色（例：`房仲業者`、`銀行業者`）→ 讓系統調整篩選方向；不需要就留空 |

3. 按 **「Execute」**

⏱ **重要：這個呼叫要 1–5 分鐘才回應**（系統要先做 LLM 分析，必要時最多再放寬 3 輪）。
Swagger 上會顯示 `Loading…`，**請不要關頁或重按**（重按 = 重新計費一次分析）。

4. 回應（Response body）看這幾個欄位：

| 欄位 | 意義 |
|:--|:--|
| `total_matched` | 符合條件的**總人數**（可能大於你要求的 `top_k`） |
| `summary[]` | **第一批人設的摘要表**（`id`/`name`/`age`/`occupation`/`income`/`residence`… ） |
| `persona_ids[]` | 符合條件的 ID 清單（可拿去 `/personadb/detail`） |
| `returned` | 實際回傳幾筆（**可能小於 `top_k`**，見下一列） |
| `pool_exhausted` | `true` = 符合條件的人數**不足** `top_k`。這是**設計行為**：系統不會為了湊數而放寬核心條件 |
| `llm_analysis.reasoning` | 系統怎麼理解你的問題（**建議先讀這段**，確認方向對不對） |
| `protected_dims` / `relaxed_dims` | 本輪被保護／被放寬的維度（稽核用，一般不用管） |

---

## 3. 取完整人設內容：`GET /personadb/detail`

拿到 `summary[].id`（或 `persona_ids[]`）後：

1. 展開 `GET /personadb/detail` → **Try it out**
2. `persona_id` 填 **`TW-P-0234`** 這種格式（也接受純數字）→ **Execute**
3. 回應 `persona` 內含完整人設：

| 欄位 | 內容 |
|:--|:--|
| `dimensions` | 全部維度（年齡/性別/地區/教育/職業/所得/家庭… 共 20+ 維度） |
| `name` / `type` | 姓名／類型（虛構人設） |
| `prompt_prefix` | **可直接餵給 LLM 的人設敘述**（一段文字） |
| `reference_pre_prompt` | 條列式輪廓（`年齡/地區/性別/婚姻/職業/…`） |

> 這個端點**不呼叫 LLM、回應很快**（毫秒級），可以放心對每個 ID 逐一取用。

---

## 4. 建議的第一批操作流程

1. **小額驗通**：`questions` 填一題（例：`都會區的上班族`）、`top_k=5`、`opMode=僅篩選` → 確認 ① 服務正常 ② `llm_analysis.reasoning` 的理解符合預期
2. **讀 reasoning 再調整**：若理解方向不對，改寫 `questions`（題目寫得越具體越好；需要時加 `role`）
3. **正式批次**：`top_k` 調到你要的數量（上限 100）→ 取 `summary[]` / `persona_ids[]`
4. **取內容**：對需要的 ID 逐一呼叫 `/personadb/detail` → 得到 `prompt_prefix` 可直接用於模擬對話

---

## 5. 常見狀況

| 現象 | 原因 | 處理 |
|:--|:--|:--|
| `Execute` 轉很久 | 正常（LLM 分析 + 最多 3 輪放寬，1–5 分鐘） | 等它；不要重複按 |
| HTTP 400 `INVALID_OPMODE` | `opMode` 填了三個值以外的字 | 用 `僅篩選` / `篩選+模擬` / `模擬詢問` |
| `returned < top_k` | 符合條件者不足（`pool_exhausted=true`） | 放寬題目或降低 `top_k`（系統不會硬湊） |
| `total_matched` 很大但 `summary` 很少 | 正常：`top_k` 只決定回傳幾筆 | 調高 `top_k`（≤100） |
| 想確認版本 | Swagger 標題的版本欄位≠產品版號 | 看 `/personadb/status` 的 `version` |

---

## 6. 想用程式呼叫（非瀏覽器）

同一個端點就是普通 HTTP GET，可直接以 curl／程式呼叫：

```bash
curl -G "http://HOST:8000/personadb/candidates" \
  --data-urlencode "questions=都會區的上班族" \
  --data-urlencode "top_k=5" \
  --data-urlencode "opMode=僅篩選" \
  --data-urlencode "role="

curl -G "http://HOST:8000/personadb/detail" \
  --data-urlencode "persona_id=TW-P-0234"
```

（中文參數請用 `--data-urlencode`，不要手動拼 URL。）
