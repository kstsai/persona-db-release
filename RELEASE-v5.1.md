# Persona DB v5.1 Release Notes

> 日期: 2026-09-03 | 上一版: v5.0 | 類型: feature（dimension 21 債務背貸狀態 + L2 filterable）

## 重點：Dimension 21 — 債務背貸狀態

JCIC 聯徵中心個人授信統計（uid=213）資料，新增 4-tier 維度 `debt_status`：

- **Tiers**: 無 / 有房貸 / 有信貸或卡債 / 房貸+消費債（多重）
- **來源**: JCIC（2026-03/04）— 信貸借款人 188 萬 by 年齡×性別（fid=1300）、房貸 226 萬（fid=719）、房貸×信貸交叉（fid=1008: 房貸族 18.7% 也有信貸）
- **實作**: 混合路線（A3）— **房貸 tier = derive**（BG 房貸短語顯性化，不重抽）、**消費債 tier = annotate**（JCIC 信貸 by 年齡×性別 rates，seed 42 確定性）
- **結果**: 無 961 / 有房貸 39 / 有信貸或卡債 60 / 房貸+消費債 9（eligible 826 人中 13.1% 背債）
- **API**: L2 filterable（valid_dims + PersonaSummary + 兩處 prompt + domain reinforcement 債務/貸款整合/債務協商/卡債）
- **Coherence**: 0-18/無收入全無、房貸 tier 有 BG 短語佐證

## 已知限制（誠實記錄）

- **房貸盛行率低於 JCIC**：persona derive 只抓到 48/826（5.8%），JCIC 為 11.6% — persona 的 housing 模型（DGBAS 房價推）非貸款模型，A3 決策接受（房貸顯性化不動既有欄位）
- 卡債 11.3% 持卡人併入消費債 union 估計，未精確拆

## 版本鏈

```
v5.0 (dimension 20 醫美 + #31 determinism) → v5.1 (dimension 21 債務背貸)
```

## QA 狀態（2026-09-03 驗證通過 → 定版）

lzcdh1 pre-release SOP 全綠：7 cases LLM verify
- **case 7 債務整合（新維度驗收）**：domain=金融/銀行貸款/債務整合，applied_filters 含 `debt_status:[有房貸, 房貸+消費債]`，top 全背債 ✅
- cases 1-6 無回歸（康是美 52/時尚 88/醫美 11 等；Role QA DIFFERENT）
- 已知 flakiness：analysis 偶發暫時性失敗（FILTER_FAILED，重跑即過）+ 嚴格 query 需 ~5min（pro analysis + 多輪 broadening）— LLM 非確定性，非 code 問題
