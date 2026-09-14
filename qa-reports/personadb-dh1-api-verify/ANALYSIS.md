# persona-db API 實測分析報告 — NODE-B (v5.2)

**受測 instance**：`NODE-B` (tailscale `NODE-B`, `NODE-B.[tailnet]`)
**測試腳本**：`kstsai/persona-db-release` → `upDockerVerHermes/test-persona-db-api.sh`（**與 NODE-A 那次同一份，sha256 相同**）
**執行時間**：2026-09-12 02:53 – 03:17 UTC（≈ 24 分鐘）
**執行結果**：9 / 9 請求 HTTP 200，0 錯誤
**證據目錄**：`/Users/kstsai/Documents/personadb-dh1-api-verify/`
**對照組**：`/Users/kstsai/Documents/personadb-NODE-A-api-verify/`（Persona DB **v4.9.2**）

> **版本確認**：`NODE-B` 執行的是 **Persona DB v5.2**（NODE-A 為 v4.9.2）。這不是小改版 —— v5.2 **新增了 3 個 persona 維度**，正好是 NODE-A 上缺失、而測試腳本案例標籤所宣稱的那 3 個。詳見 §2。

> ### 📌 量測範圍與判讀修正（2026-09-14 補記 — 僅附加，原文未改）
>
> **判讀修正請先看 [`../CORRECTIONS.md`](../CORRECTIONS.md)**：本報告是「**執行當時的判讀**」，
> 原文與原始證據保留不動（可追溯性）；後續取得新證據而推翻某條判讀時，修正記於該檔。
>
> | 項目 | 值 |
> |:---|:---|
> | runner sha256 | `ffc7b10642f72f4120a43b77848ed722c6cf865c23b3267a3eb87bd48c74695d`（**五輪完全相同** ⇒ 跨輪可比）|
> | runner 取得日期 | **2026-09-12**（第一輪取得；第 2–5 輪沿用**同一份凍結版**）|
> | 上游 upstream 副本 sha256 | `33749d4e5218f3860f15f4296c5fc5ea90f0fa93f441bc4eba9faf2274dad2e3`（**凍結版，90 行**）|
> | **現行 upstream**（2026-09-14） | `9a29a8ef3bc553a334b1865c792d4f0f17e60ce15f93a46fe9f8ac9b684edbd8`（**223 行**）|
>
> **⚠️ 覆蓋缺口（務必先讀）**：本輪 runner 的案例集取自第一輪的凍結版，**不含「業主本人」語意案例**。
> 其中**案例 08 是「顧客語意」**（問攤商的顧客），依現行設計**本就不該**套用 `employment_status=雇主`；
> 現行 upstream 亦已在標籤上註明「【顧客語意】不應套 employment_status」，並新增**案例 9「業主本人
> — dimension 22: employment_status（issue #34）」**。
>
> → 因此本報告中**任何「某維度從未被套用」的敘述，都必須先確認案例集有無該語意的案例**；
> 沒有案例即為**量測工件（coverage gap），不是產品缺陷**。詳見 `CORRECTIONS.md` 修正③ 與 issue #51。


---

## 1. 執行摘要

| # | 案例 | HTTP | 耗時(s) | bytes | total_matched | 回傳 | top score | v4.9.2 top |
|---|------|------|---------|-------|---------------|------|-----------|------------|
| 0 | `00_status` | 200 | 1.46 | 790 | — | — | — | — |
| 1 | `01_kangshimei` | 200 | 57.14 | 2746 | 62 | 3 | 5.2606 | 6.5499 |
| 2 | `02_tesla` | 200 | 176.33 | 3249 | 20 | 3 | 6.7397 | 7.7196 |
| 3 | `03_fashion` | 200 | 201.17 | 6470 | 11 | 10 | 7.1747 | 7.4629 |
| 4 | `04_role_fangzhong` | 200 | 244.83 | 4696 | 27 | 5 | 5.5692 | 5.7728 |
| 5 | `05_role_banker` | 200 | 178.28 | 4490 | 9 | 5 | 4.1771 | 5.6547 |
| 6 | `06_aesthetic` | 200 | 339.93 | 6722 | 11 | 10 | 5.6709 | 5.0374 |
| 7 | `07_debt` | 200 | 365.24 | 6600 | 23 | 10 | 4.3476 | 5.2411 |
| 8 | `08_boss` | 200 | 65.22 | 6272 | 25 | 10 | 5.6095 | 4.0163 |

**契約驗證（8/8 全部通過）**
- `top_k` 精確遵守；`persona_ids[i]` ↔ `summary[i].id` 對應一致
- `summary[].score` 單調遞減
- top-level 回應 key 集合與 v4.9.2 **完全相同**（10 個 key）
- `content-type`：candidates 8/8 `application/json`；status `text/plain`

**延遲**：candidates 總計 **1628.1s**，平均 **203.5s**（v4.9.2：1152.9s / 144.1s）→ **慢 41%**。最慢 365.2s（案例 7）。維度變多使 LLM 篩選合成更久。
**額外觀測**：同一請求（案例 1）另測 4 次，耗時為 57.1 / 297.2 / 256.3 / **>300（timeout）** 秒 —— 延遲變異極大。

---

## 2. 【核心發現】v5.2 新增 3 個維度，正好是腳本案例標籤宣稱的那 3 個

### 2.1 Persona schema：22 → 25 維

對 8 個 persona 抽樣（208/337/181/891/408/331/244/802）呼叫 `/personadb/detail`，兩版都是**每個 persona 恰好 N 維、且 8 個樣本維度集合完全一致**：

| | v4.9.2 (NODE-A) | v5.2 (NODE-B) |
|---|---|---|
| 維度數 | **22** | **25** |
| 新增 | — | **`aesthetic_procedure`, `debt_status`, `employment_status`** |
| 移除 | — | （無） |

**新增的正是這 3 個**。v5.2 的值域（實測）：
- `aesthetic_procedure`：`有` / `無`
- `debt_status`：`無` / `有房貸` / `有信貸或卡債` / `房貸+消費債`
- `employment_status`：`受僱者` / `雇主` / `自營作業者` / `不適用`

### 2.2 回應 schema 也隨之擴張

`summary[]` 每一列由 **14 欄 → 17 欄**，新增的正是這 3 個維度。**top-level key 不變** → 屬於**向後相容的欄位新增**（既有 consumer 不會壞，但若做嚴格 schema 驗證會失敗）。

### 2.3 這推翻了 NODE-A 報告中的一項判讀

NODE-A（v4.9.2）報告 §4.3 結論為「案例標籤宣稱的 dimension 20/21/22 不存在，測試覆蓋率被高估」。**在 v5.2 上該結論不成立**：

- 這 3 個維度**確實存在**，且**確實會被 API 使用**（見 §3）
- 正確的判讀是：**NODE-A 是落後的部署（v4.9.2），而測試腳本是為 v5.2 寫的**
- → 該問題應重新歸類為**「版本落差（version skew）」**，而非腳本標籤錯誤

**教訓**：在只有單一部署可測時，「腳本標籤與 schema 不符」容易誤判成腳本 bug；實際是**受測環境版本落後**。跨版本對照是唯一能區分兩者的方法。

---

## 3. 【核心發現】新維度確實被使用 —— 但 `employment_status` 例外

### 3.1 新維度在各案例的使用位置

| 案例 | `applied_filters`（實際篩選） | `dims_counted`（計分宣告） | `important_dimensions`（LLM 認為重要） |
|------|------------------------------|---------------------------|--------------------------------------|
| 01 康是美 | — | — | — |
| 02 TESLA | — | — | debt_status, employment_status |
| 03 時尚 | —（但**曾被套用後放寬**，見 §3.3） | — | debt_status |
| **04 房仲** | **`debt_status`=無/有房貸** | — | debt_status, employment_status |
| **05 銀行** | **`debt_status`=有房貸/房貸+消費債** | — | aesthetic_procedure, debt_status, employment_status |
| **06 醫美** | **`aesthetic_procedure`=有** | — | debt_status, employment_status |
| **07 債務整合** | **`debt_status`=有房貸/房貸+消費債** | — | aesthetic_procedure, debt_status, employment_status |
| 08 小吃攤 | **—（`employment_status` 未套用）** | — | debt_status, employment_status |

**結論**：
- ✅ **`aesthetic_procedure` 已實際生效**（案例 6 套用 `=["有"]`，回傳 **10/10 `aesthetic_procedure=有`**）
- ✅ **`debt_status` 已實際生效**（案例 4/5/7；案例 7 回傳 **10/10 符合**篩選值）
- ❌ **`employment_status` 從未被套用為篩選**（8/8 案例皆無），**包含案例 8 —— 也就是標籤宣稱測試 `dimension 22: employment_status` 的那個案例**

### 3.2 `dims_counted` 完全沒有納入新維度（8/8）

**沒有任何一個案例**的 `scoring_basis.dims_counted` 列出新維度 —— 即使該案例**正在用新維度做篩選**（如案例 6/7）。詳見 §5.3。

### 3.3 案例 3 提供了「新維度確實進入 LLM 詞彙表」的直接證據

案例 3 的 `relaxed_dims = [hobby, aesthetic_procedure]`，broadening 紀錄：

```
loop 1:  0 → 0   移除非核心維度 hobby（逛街購物）…限縮過嚴導致樣本數不足
loop 2:  0 → 0   放寬 commute_mode 維度，加入「機車」…預期可增加樣本數至 20 人以上
loop 3:  0 → 11  移除「aesthetic_procedure」此一非核心維度，以放寬樣本數
```

→ `aesthetic_procedure` **曾被納入篩選、再被放寬移除** → 證明它已在 filter 合成流程中。
**同時暴露一個異常**：初始篩選 **matched = 0**（無任何 persona 符合），需經 **2 次無效放寬（0→0）** 才在第 3 輪救回 11 筆。且 loop 2 自述「預期可增加樣本數至 **20 人以上**」，實際僅 **11** 筆 → **LLM 的數量預期不準**。

---

## 4. 逐案例要點（v5.2）

### 案例 1 — 康是美的目標客戶（top_k=3）
`total_matched=62`，回傳 3 筆 `178 愛莎 / 768 小艾 / 171 可恩`，**全部 19-24 歲、學生、無收入**，score `5.2606 / 4.871 / 4.6564`。
`applied_filters`：age `19-24,25-34,35-44`｜**sex `女`**｜occupation 5 類｜income `無收入,<3萬,3-8萬`｜clothing_spend 3 桶｜family_income `3-5萬,5-7萬`。**無 relaxed、無 broadening（0 輪）**。
→ 與 v4.9.2 完全反向（v4.9.2 為 3/3 `>8萬`）。此案例是 §5.1 收入飽和改善的最佳例證。
→ 但見 §5.2：**同一查詢重跑 3 次，結果完全不同，其中 2 次 matched 只有 1**。

### 案例 2 — TESLA的目標客戶（top_k=3）
`matched=20`，`234 艾力克 / 586 彩華 / 331 正雄`，score `6.7397 / 6.6786 / 6.209`。
3/3 `income=>8萬`；`important_dimensions` 含 `debt_status=有房貸,無` 與 `employment_status=受僱者,雇主`（但未套用）。

### 案例 3 — 時尚服裝設計師的目標客戶（top_k=10）
`matched=11`（v4.9.2：118），score `7.1747 → 4.9306`。
`applied_filters` 含 **`region=都會區(六都)`**；8/10 `income=>8萬`。
10/10 `aesthetic_procedure=無`。relaxed `hobby, aesthetic_procedure`；broadening 3 輪（見 §3.3）。

### 案例 4 — 房貸優惠 / role=房仲業者（top_k=5）
`matched=27`，`234 艾力克 / 275 米亞 / 484 慧君 / 248 小奈 / 798 麗卿`，score `5.5692 → 5.0506`。
**`debt_status = 無 / 有房貸`**｜`housing_burden = 低,中`｜`marriage=已婚`｜`family_size=3,4`｜occupation `科技,金融,服務,製造`。
→ 語意正確：找**沒有債務負擔或僅有房貸**、居住負擔輕的潛在購屋者。

### 案例 5 — 房貸優惠 / role=銀行業者（top_k=5）
`matched=9`（v4.9.2：26），`473 淑娟 / 331 正雄 / 811 志強 / 929 麗華 / 328 俊傑`，score `4.1771 → 4.1328`。
**`debt_status = 有房貸 / 房貸+消費債`**｜`housing_burden = 中,高`。
→ 語意正確且**與案例 4 方向相反**：找**已有房貸/消費債**、可轉貸整合的既有貸戶。

#### ★ Role 差異化（v5.2）

| 項目 | 房仲業者 (04) | 銀行業者 (05) |
|------|---------------|---------------|
| top-1 | **234**（25-34 金融） | **473**（45-54 其他） |
| top-5 集合 | {234,275,484,248,798} | {473,331,811,929,328} |
| **交集** | **0（完全不相交）** | |
| **`debt_status`** | **`無` / `有房貸`** | **`有房貸` / `房貸+消費債`** |
| housing_burden | `低,中` | `中,高` |
| `marriage` | `已婚`（有套用） | **未套用**（`applied_filters` 無此 key） |
| relaxed_dims | `[]`（無維度被移除） | `[]`（無維度被移除） |
| broadening | 3 輪 `11→11→11→27` | 3 輪 `6→6→7→9` |

→ **✅ DIFFERENT**，且比 v4.9.2 **更強**：v4.9.2 只能靠 `housing_burden` 區辨，v5.2 的 role 差異**直接體現在新維度 `debt_status` 上**，語意更精準。

### 案例 6 — 醫美診所的目標客戶（top_k=10）
`matched=11`（v4.9.2：69），score `5.6709 → 3.1087`。
**`aesthetic_procedure = ["有"]`**｜`sex = ["女","男"]`｜relaxed `family_income`。
**回傳 10/10 `aesthetic_procedure=有`**，且**10/10 皆為女性**（實查 detail：473/513/891/361/247/238/350/512/372/280 全女）。
`income` 分佈：`>8萬` 2 筆、`3-8萬` 8 筆 → 飽和問題改善。
→ **v4.9.2 的兩個問題都被修好**：v4.9.2 無 `aesthetic_procedure` 可用、無 sex 篩選、回傳 6 男/4 女；v5.2 有維度可用且結果 10/10 女性。
→ **細節校正**：v5.2 的 `sex` 篩選值為 `["女","男"]`（**兩個值都列，實質不構成限制**）。女性偏斜是**由 `aesthetic_procedure=有` 連帶產生的**，而非 sex 篩選所致。這點值得記錄，因為單看 `applied_filters.sex` 會誤以為性別被強制。

### 案例 7 — 債務整合的目標客戶（top_k=10）
`matched=23`，score `4.3476 → 2.1444`。
**`debt_status = ["有房貸","房貸+消費債"]`**｜relaxed `family_income`｜`applied_filters` 僅 4 個 key（`age, debt_status, housing_burden, income`）。
**回傳 10/10 符合 `debt_status`**（9 筆 `有房貸` + 1 筆 `房貸+消費債`）。
`income`：`>8萬` 8 筆、`3-8萬` 2 筆 → 飽和改善。
→ **本批次語意最精準的案例**：標籤宣稱測 `dimension 21: debt_status`，**v5.2 確實做到了**。

### 案例 8 — 小吃攤老闆的目標客群（top_k=10）
`matched=25`（v4.9.2：234），score `5.6095 → 4.5832`。
`applied_filters` 8 個 key：`age, clothing_spend, commute_mode, family_income, hobby, income, marriage, occupation` —— **無 `employment_status`**。
回傳 `employment_status`：`不適用` 5 筆、`受僱者` 5 筆；`occupation`：`學生` 5、`服務` 3、`製造` 2 —— **無 `雇主`／`自營作業者`**。
→ **標籤宣稱測 `dimension 22: employment_status`，但該維度仍未被套用**。v4.9.2 有同樣問題（當時 `debt_status` 等維度甚至不存在），**v5.2 修好了 20/21，獨漏 22**。「小吃攤老闆」的語意歧義（顧客 vs 攤商本身）依舊存在（詳見 v4.9.2 報告 §3 案例 8）。

---

## 5. 跨案例發現（含與 v4.9.2 對照）

### 5.1 【改善】收入桶飽和大幅緩解

| 案例 | v4.9.2 `income=>8萬` | v5.2 `income=>8萬` |
|------|---------------------|-------------------|
| 01 康是美 | **3/3** | **0/3** ✅ |
| 02 TESLA | 3/3 | 3/3 |
| 03 時尚 | **10/10** | 8/10 |
| 04 房仲 | 5/5 | 5/5 |
| 05 銀行 | 5/5 | 5/5 |
| 06 醫美 | **10/10** | **2/10** ✅ |
| 07 債務整合 | **10/10** | 8/10 |
| 08 小吃攤 | 0/10 | 0/10 |

**完全飽和（100%）的案例由 7/8 降到 3/8**（02/04/05）。案例 01（3/3→0/3）與 06（10/10→2/10）改善最劇。
→ 推測主因：新維度（尤其 `aesthetic_procedure`、`debt_status`）加入後，**更多樣的維度分攤了收入維度的主導權**。
→ 但 02/04/05 仍 100% 飽和（房貸類 04/05 語意上合理；02 TESLA 高單價耐久財亦合理）。

### 5.2 【未改善，且更嚴重】端點不可重現

對**同一查詢**「康是美的目標客戶」（`top_k=3`, `opMode=僅篩選`）共 4 次觀測：

| 觀測 | total_matched | persona_ids | top score | `aesthetic_procedure` 篩選 |
|------|---------------|-------------|-----------|---------------------------|
| 主測試套件 run | **62** | 178, 768, 171 | 5.2606 | **未套用** |
| repeat #1 | **1** | 350 | 3.5562 | **`["有"]`** |
| repeat #2 | **1** | 350 | 3.3166 | **`["有"]`** |
| repeat #3 | — | — | — | **>300s timeout（HTTP 000）** |

**配對交集**：
- 主跑 vs repeat#1 → **0 / 3**
- 主跑 vs repeat#2 → **0 / 3**
- repeat#1 vs repeat#2 → 1 / 1

**觀察**：
1. `total_matched` 在 **1 ↔ 62** 之間擺盪（**62 倍差距**）
2. top score 3.3166 ↔ 5.2606
3. **`aesthetic_procedure` 這個新維度本身會隨機出現/不出現** —— 而一旦被套用成 `=["有"]`，"康是美（藥妝店）的目標客戶" 就被限縮到「**做過醫美療程**」的人，matched 崩到 **1**，回傳結果退化
4. 即使 repeat#1 與 #2 都回傳同一人（350），**分數與篩選條件仍不同**（3.5562 vs 3.3166；relaxed `commute_mode` vs `family_income,commute_mode`）
5. 第四次**直接超過 300s 客戶端逾時**

→ **判讀**：v4.9.2 的不可重現問題在 v5.2 **未改善**，且因為維度變多（可選維度 22→25），**篩選空間更大 → 變異來源更多**。`aesthetic_procedure=有` 用在藥妝零售語境是**語意不當的篩選**，卻會被隨機套用。
→ **對 QA 的意義**：`Role QA: diff check` 這類單次斷言**不具統計保證**。v5.2 的 role 檢查雖然通過（234 vs 473、交集 0），但必須理解它是在雜訊極大的系統上的一次抽樣。

### 5.3 【未改善】`scoring_basis.dims_counted` 仍低報計分維度

以「同分 ⇔ `dims_counted` 向量相同」為檢定，若宣告為真則兩者必須等價：

| 案例 | `dims_counted` | v4.9.2 反例 | v5.2 反例 |
|------|----------------|------------|-----------|
| 01 | age,occupation,sex,income,clothing_spend,family_income | 0 | **0** ✅ |
| 02 | age,occupation,income,family_income,commute_mode,clothing_spend | 0 | **0** ✅ |
| 03 | age,occupation,income,clothing_spend,family_income,commute_mode,region,education,family_size,hobby | 2 | **0** ✅ |
| 04 | age,occupation,income,marriage,family_size,family_income,housing_burden | 0 | **0** ✅ |
| 05 | age,income,housing_burden,family_income | 1 | **3** ⚠️ |
| 06 | age,occupation,sex,income,clothing_spend,family_income | 2 | **1** ⚠️ |
| 07 | age,income,family_income,housing_burden | 3 | **6** ⚠️ |
| 08 | age,occupation,income,marriage,clothing_spend,family_income,commute_mode,hobby | **25** | **1** ⚠️ |

**改善**：案例 08 由 25 組反例降到 1 組；01/02/03/04 完全一致。
**仍存在**：05/06/07/08 仍出現「`dims_counted` 值全同卻不同分」。
**最具體的 v5.2 反例（案例 07）**：`473 淑娟`(45-54 其他) 與 `811 志強`(45-54 科技) —— `dims_counted` = age/income/family_income/housing_burden 全同，分數 **4.3476 vs 4.2982**。差別在**未宣告**的 `occupation`（其他 vs 科技）與 `aesthetic_procedure`（有 vs 無）。
→ **且注意**：案例 07 正在用 `debt_status` 做篩選（回傳 9 筆 `有房貸` + 1 筆 `房貸+消費債`），但 `debt_status` **不在 `dims_counted`** —— 篩選值不同（房貸+消費債 vs 有房貸）很可能影響分數，卻未揭露。

### 5.4 【惡化】broadening 空轉率由 17% 升至 41%

「空轉迴圈」= `match_count_before == match_count_after`（放寬動作未改變樣本數）：

| 案例 | v4.9.2 序列 | 空轉 | v5.2 序列 | 空轉 |
|------|------------|------|-----------|------|
| 01 | 6→13→18→21 | 0/3 | （0 輪） | — |
| 02 | 9→21 | 0/1 | 10→16→20 | 0/2 |
| 03 | 1→1→11→118 | 1/3 | **0→0→0→11** | **2/3** |
| 04 | 4→8→14→32 | 0/3 | **11→11→11→27** | **2/3** |
| 05 | 17→17→26 | 1/2 | 6→6→7→9 | 1/3 |
| 06 | （0 輪） | — | 7→10→11→11 | 1/3 |
| 07 | （0 輪） | — | 6→6→14→23 | 1/3 |
| 08 | （0 輪） | — | （0 輪） | — |
| **合計** | | **2/12 = 17%** | | **7/17 = 41%** |

**v5.2 有 41% 的放寬迴圈完全沒有效果**（v4.9.2 為 17%）。
最極端是案例 04：`11→11→11→27` —— **連續 2 輪空轉**；案例 03：**起點 matched=0，且連續 2 輪 0→0**。

另有 **自述預期不準** 的問題（兩版皆有）：
- v5.2 案例 03 loop 2：「預期可增加樣本數至 **20 人以上**」→ 實際最終 **11**
- v5.2 案例 06 loop 2：「預期可增加樣本數至 **20 人以上**」→ 實際最終 **11**

→ 建議：broadening 迴圈應在「無變化」時提前中止（或換策略），而非消耗迴圈額度；`change` 文字中的數量預期應改為事後陳述或移除。

### 5.5 【改善】`llm_analysis.usage_suggestion` 開始有區辨力

| | v4.9.2 | v5.2 |
|---|---|---|
| `mode` | 8/8 皆 `問卷答題者`（常數） | `問卷答題者` ×6、`兩者皆可` ×2（案例 01/04/05） |
| `recommended_opMode` | 8/8 皆 `僅篩選`（= 請求值，回音） | `僅篩選` ×6、**`篩選+模擬` ×2（案例 04/05）** |

→ v5.2 此欄位**不再只是回音**，開始給出與請求不同的建議。這是正向改進（欄位有資訊量）。
→ 但需注意：這也意味著**回應的 `recommended_opMode` 不可用來確認「請求被正確理解」**（v4.9.2 可以）。

### 5.6 新維度的值域分佈（56 筆回傳 persona）

| 維度 | 值域分佈 |
|------|---------|
| `aesthetic_procedure` | `無` 44、`有` 12 |
| `debt_status` | `無` 31、`有房貸` 19、`有信貸或卡債` 4、`房貸+消費債` 2 |
| `employment_status` | `受僱者` 40、`不適用` 10、`雇主` 3、`自營作業者` 3 |

→ `employment_status = 不適用` 出現 10 次（多為 19-24 歲學生）—— 對學生而言就業狀態「不適用」語意合理。
→ 注意 `debt_status` 與 `employment_status` 在 `applied_filters` 中出現的值，都是 `important_dimensions` 值域的子集，無越界值。

### 5.7 跨案例 persona 重用（v5.2）

`473 淑娟` 同時是**案例 05、06、07 的 top-1**；`234 艾力克` 是案例 02/04 的 top-1、案例 07 的第 2；`331 正雄` 出現在案例 02/05/07。
→ 少數「高分 persona」在多個不同 domain 重複奪冠，與 v4.9.2 觀察到的現象一致（v4.9.2 為 `797 雅芳`、`337 建宏`）。**候選池的頭部集中問題跨版本持續存在**。

---

## 6. 驗證限制 / 未涵蓋範圍

1. **未測 `opMode` 其他值**：全部固定 `opMode=僅篩選`（與腳本一致）。
2. **未測 `top_k` 邊界**（1/100/0/>100）與錯誤路徑（400/500）。
3. **未測 `questions` 多題以 `|` 分隔**。
4. **`dims_counted` 不完整** → **分數無法獨立重算**，僅驗證單調性與同分結構。
5. **維度存在性**基於 8 個 persona 抽樣 + 56 筆回傳的 summary 欄位；未直接讀取 instance 上的 `tw_persona_1069.json`。
6. **重現性只測了案例 1**（4 次觀測，其中 1 次逾時）；其餘 7 案例各僅 1 次，未做變異估計。
7. **v4.9.2 與 v5.2 的結果差異混合了兩個因變數**：版本（維度集合）+ LLM 抽樣變異。由於 v5.2 自身的 case-01 變異就達 1↔62，**跨版本結果差異無法乾淨歸因於版本**。若要分離，需在同版本上多次取樣建立 baseline 分布。
8. **repeat#3 為客戶端 300s 逾時**，非伺服器錯誤；無法區分「伺服器仍在處理」與「失敗」。

---

## 7. 結論

**v5.2 相對 v4.9.2 的實質改進**
1. ✅ **新增 `aesthetic_procedure` / `debt_status` / `employment_status` 三個維度**，`summary[]` 同步擴張 14→17 欄，top-level 契約保持相容
2. ✅ **新維度確實投入使用**：案例 06 `aesthetic_procedure=有`（10/10 命中）、案例 04/05/07 `debt_status`（案例 07 10/10 命中）
3. ✅ **醫美案例（06）的兩個問題被修好**：v4.9.2 無維度可用、無 sex 篩選、6男/4女 → v5.2 有維度、結果 10/10 女性
4. ✅ **收入桶飽和大幅緩解**：完全飽和案例 7/8 → 3/8
5. ✅ **role 差異化更強**：v4.9.2 僅靠 `housing_burden`，v5.2 直接體現在 `debt_status`（房仲 `無/有房貸` vs 銀行 `有房貸/房貸+消費債`）
6. ✅ `usage_suggestion` 欄位開始有區辨力（v4.9.2 為常數/回音）
7. ✅ 案例 08 的 `dims_counted` 反例由 25 降到 1；01/02/03/04 完全一致

**v5.2 仍存在的問題（依嚴重度）**
1. **端點不可重現，且因維度變多而加劇**（§5.2）：同查詢 `total_matched` 1↔62、top-3 交集 0、同請求耗時 57s↔>300s 逾時
2. **`employment_status` 從未被套用**（§3.1）：8/8 案例皆無，**包含標籤宣稱測試該維度的案例 08** —— v5.2 補齊了 dimension 20/21，獨漏 22
3. **`dims_counted` 仍低報計分維度**（§5.3）：05/06/07/08 皆有反例，且案例 07 正用 `debt_status` 篩選卻未列入計分宣告
4. **新維度可能被套用到不當語境**（§5.2）：`aesthetic_procedure=有` 隨機套用於「康是美（藥妝店）目標客戶」，matched 崩到 1 —— 建議對新維度加上語意適用性約束
5. **broadening 空轉率由 17% 惡化至 41%**（7/17 迴圈零效果；案例 04 連續 2 輪空轉、案例 03 起點 matched=0），且 `change` 自述的數量預期不準（宣稱 20+，實際 11）（§5.4）
6. **延遲上升 41%**（平均 144.1s → 203.5s，最慢 365.2s），且有逾時風險
7. **候選池頭部集中**跨版本持續（§5.7）

**跨版本最重要的單一結論**
> `aesthetic_procedure` / `debt_status` / `employment_status` **不是腳本標籤的錯誤，而是 v5.2 的新增維度**。NODE-A（v4.9.2）是落後部署。此差異只能靠**跨版本對照**發現 —— 單一環境測試會把它誤判為腳本 bug。

---

## 8. 相對於原腳本的改動

與 NODE-A 那次**完全相同**：`run-test.sh` sha256 `ffc7b10642f72f4120a43b77848ed722c6cf865c23b3267a3eb87bd48c74695d`（與 NODE-A run 一致），上游腳本 sha256 `33749d4e…dad2e3`（相同）。
差異僅在 `BASE_URL=http://NODE-B:8000` 與 `OUT` 指向本目錄。**請求參數、順序、斷言邏輯 100% 未變**。
