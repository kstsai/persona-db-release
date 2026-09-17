---
name: persona-db-regen
description: 重建或擴充 Persona DB 人設資料庫 — 依 RFC 規格與 sources/ 資料來源產生／修正 dataset，含 in-place annotate vs full regen 決策樹、一致性驗證、權重表與契約檢查。
tags: [persona-db, data-generation, dgbas, jcic, coherence, dataset]
---

# Persona DB — 資料生產（重建／擴充）

> 觸發時機：要**產出新的一組人設資料庫**、**新增維度**、**修正基礎維度模型**、或**換用新資料集**。
> 前置：先讀 `DATA-CONTRACT.md`；規格細節回查 `tw-persona-db-rfc.md` 與 `concepts/`。

## 0. 鐵則（資料面）

1. **口徑一致**：`個人收入`≠`家庭可支配所得`；外部統計金額若口徑不同**不要硬套**。
2. **來源可回溯**：每個維度的值必須能指到 `sources/` 的某檔（或註明出處與年度）。
3. **抽樣變異要說**：n=1069 時佔比誤差約 ±1–3 個百分點 → 「佔比是否合理」的判定要帶容忍區間。
4. **虛構性**：姓名／地點／校名皆虛構，`note` 欄位聲明；不得對應真實人物。
5. **改資料＝改版本**：dataset 或權重變更 → bump 版號並重打包。

## 1. 決策樹（先決定「怎麼改」，再動手）

| 情況 | 做法 | 理由 |
|:--|:--|:--|
| **新增維度**（第 N 維） | **in-place annotate**：對現有 dataset 逐筆補值 | 保留既有已驗證分布；成本低、可回溯 |
| **基礎維度模型修正**（定義／級距改變） | **full regen**（整批重建）→ **完成後重跑所有 annotate 維度** | 基礎分布變了，補註維度必須在新基礎上重算 |
| **換資料來源／年度** | 先做**差異評估**（舊 vs 新分布）→ 再決定 annotate 或 regen | 有時只有單一維度受影響 |
| **只新增 coherence rule** | 不必重產；跑驗證找出違規者 → 針對違規者修正 | 規則變更不等於分布變更 |

> ⚠️ 歷史教訓：`occupation` 的「自營」值曾與「從業身分」重疊 → 修法是**值退役 + 身分剝離**，並在 regen 後
> **重跑依賴該基礎的其他 annotate 維度**（#32）。順序錯了，後補的維度會建在錯的基礎上。

## 2. 生產流程

```
① 規格對齊   讀 RFC（維度設計／級距／coherence rules／輸出格式／命名原則）＋ concepts/
② 來源盤點   sources/ 逐項確認年度與口徑；缺口要標明「用什麼替代或留空」
③ 產生 dataset
   - full regen：依 RFC 的維度分布與 coherence rules 產生 1069 筆
   - annotate  ：寫腳本對現有檔案逐筆補值（保留原檔為 backup）
④ 逐筆欄位完整：全部維度 + prompt_prefix + reference_pre_prompt（缺一不可）
⑤ 一致性驗證
   - 佔比對照表（新 vs 舊，含容忍區間）
   - contradiction hunt（scripts/contradiction_hunt/）
   - 抽樣 30 筆人工／LLM 覆核（看敘述與維度是否自洽）
⑥ 權重表
   - scripts/gen_dim_weights.py：**可計分維度清單要含新維度**，否則會被 fallback 1.0
   - scripts/check_dim_weights.py 驗證權重完整性
⑦ 契約檢查
   - scripts/check_response_schema.py（計分 18 ⊆ 可篩 20 ⊆ 可見 21）
   - 若動到 API 欄位 → 更新 api/models.py 與出貨斷言
⑧ 報告
   - REPORT-regen-<date>.md：來源、方法、驗證結果、**已知限制**（含抽樣變異）
⑨ 進版 + 出貨（見 persona-db-release）
```

## 3. 品質關卡（任一不過就不出貨）

- [ ] 每筆欄位完整（22 維度 + 雙 prompt），無空值
- [ ] 佔比對照表已產出，**所有顯著差異都有解釋**（來源變化？規則變化？）
- [ ] 矛盾獵捕 0 未解釋違規
- [ ] 權重表 `weight_version` 與資料年度已更新；可計分維度涵蓋新維度
- [ ] 可見／可篩／計分三層清單一致
- [ ] 抽樣 30 筆覆核通過
- [ ] 命名符合 RFC §命名原則（名字要對應人設屬性）
- [ ] **特定性原則**：興趣嗜好要具體（`登山`、`球類` yes；`運動` no）—— 泛化值會讓篩選與計分失真

## 4. 常見陷阱

| 陷阱 | 後果 | 對策 |
|:--|:--|:--|
| 把金額統計直接當收入用 | 分布看似合理但整體偏高／偏低 | 只用口徑相同的來源；否則留空或改用比例 |
| JCIC 金額欄位 | 聯徵金額≠個人實際負債（僅涵蓋金融機構） | **只用人數比例** |
| 新維度忘了加進可計分清單 | 該維度不影響排序（靜默 fallback 1.0） | 跑 `check_dim_weights.py` 會警告 → 補清單後重跑 |
| 新維度只加在 prompt、沒加進「可篩」 | 使用者篩了卻被丟棄（歷史事故 #54） | 更新 `check_response_schema.py` 的三層清單 |
| regen 後沒重跑 annotate 維度 | 補註維度與新基礎不一致 | 照 §1 決策樹順序執行 |
| 用「看過的印象」判斷佔比合理 | 錯判 bug／漏判缺陷 | 一律產**佔比表 + 容忍區間** |

## 5. 產出物清單

| 檔案 | 說明 |
|:--|:--|
| `tw_persona_1069.json` | 新 dataset（或規格允許的新檔名，需同步 API） |
| `dim_weights.json` | 權重表（`weight_version` 已更新） |
| `REPORT-regen-<date>.md` | 生產報告（來源／方法／驗證／已知限制） |
| `sources/<new>/README.md` | 新來源的出處、年度、口徑、抓取方式 |
| `RELEASE-<ver>.md` | 進版說明（見 persona-db-release） |
