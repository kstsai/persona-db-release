# False Positive 事例 — NODE-C「無 SSH 存取」的誤判

> **用途**：記錄一次**已發布報告中的誤判**，供其他 agent／讀者避免重犯。
> 對象：任何要對 NODE-C（或任何受測節點）做 QA／部署驗證的人。
> 相關輪次：**round15（Persona DB v5.15）**。維護：hermesa7（a7）。

---

## 一句話

round15 報告**初稿**把「a7 自己連不上 NODE-C」寫成「**NODE-C 無 SSH 存取** ⇒ 部署保真度無法驗證」，
並列為 §5 驗證限制。**這是 false positive（FP）** —— NODE-C 一直都可存取，
只是**帳號／認證方式用錯**（用了 OpenSSH key，實際要用 `ubuntu` 帳號＋密碼）。

---

## 原判讀（已發布初稿的原文）

> **⚠️ 部署保真度無法驗證**：NODE-C 無 SSH 存取（publickey/password 皆拒）→ 無法從節點內確認
> 執行中 code == v5.15 tarball（無 docker exec / 無 /app/VERSION 讀取）。→ 列為 §5 限制。

> ## 5. 驗證限制 / 未涵蓋範圍
> - **部署保真度無法驗證**：NODE-C 無 SSH → …
> - **docker 主機層斷言（#50/#55/#60）N/A**：遠端執行無 docker logs/exec 存取。

---

## 為什麼是 FP（root cause）

| # | 當時的做法 | 問題 |
|:--|:--|:--|
| 1 | 只從**一個環境**（Windows 側 git-bash）試 SSH | 沒試 WSL、沒試節點本機 |
| 2 | 只用**一種認證**（OpenSSH publickey）→ `Permission denied` | 沒試密碼認證、沒試其他帳號 |
| 3 | 把「**我沒試通**」寫成「**對方沒有**」 | **歸因錯誤**（skill §6.7：先取得那一側的證據） |
| 4 | 沒把「試過哪些環境／帳號／認證」寫進報告 | 讀者無法判斷這個 N/A 是「真的不可行」還是「我沒試對」 |
| 5 | （上游條件）任務交付時**未附登入方式** | 觸發因素，但**不能免除**「應窮盡探測再下結論」的責任 |

> 尤其：步驟 2 的 `Permission denied (publickey,password)` 訊息本身就列出了 `password` —— 它明示
> 「還有密碼這條路沒試」，我卻直接當成「無存取」。**訊息就在眼前，是我讀漏了。**

---

## 更正（取得正確存取後）

以 **`ssh ubuntu@NODE-C`（密碼認證）** 登入後：

| 項目 | 結果 |
|:--|:--|
| SSH 存取 | ✅ 可登入（`ubuntu` ∈ `docker` 群組，免 sudo 用 docker） |
| 部署保真度 | ✅ 容器 `/app/api/*.py` sha256 == v5.15 tarball 內 `api/*.py`（**byte 級**；`server.py` = `1ab44330…`） |
| 容器狀態 | `persona-db-api` Up (healthy)、RestartCount=0、StartedAt **早於**主套件 → 受測的就是發佈產物 |
| #50 部署版本一致性 | ✅（`/app/VERSION` = v5.15 == 節點 `RELEASE-VERSION`） |
| #55 例外型別診斷碼 | ✅ |
| #60 root logger | ✅（**實質**，見下「附帶發現」） |

→ 原先標為「無法驗證 / N/A」的三塊，**全部可驗證且全部通過**。詳見
[`extra/deployment-fidelity.txt`](extra/deployment-fidelity.txt)。

---

## 附帶發現（同一輪，非本次 FP 主體）

- **`docker logs` 會被 NUL hole 截斷**：容器 log 檔在重啟處有一塊 NUL(0x00) 區塊，docker 的
  json-file reader 讀到即停 ⇒ `docker logs` 只吐 **90 / 3077 行**，使上游 #60 斷言誤報 0。
  直接讀 raw log 檔得 `Protected dims`×15、`Broadening loop`×51（root logger **確實生效**）。
  → 凡「用 `docker logs` 取樣」的檢查，在此節點都可能誤報。
- **出貨 tarball 打包順序缺陷**：v5.15 tarball **內含**的 `RELEASE-VERSION` = v5.14（未 bump），
  節點工作目錄則為 v5.15。已由 **#74 守門斷言**（a3）與 pack 腳本修復（`f262bda`）接手防再發。

---

## 可複用教訓（for other agents）

1. **要對 NODE-C 做 QA／部署驗證**：用 `ubuntu` 帳號（**密碼認證**），不是 OpenSSH key；
   `ubuntu` 在 `docker` 群組可免 sudo。
2. **「無存取」是強主張，必須先試滿三種維度**並把結果寫進報告：
   ① 環境（Windows 側／WSL／節點本機）② 帳號 ③ 認證方式（key／密碼／私有 mesh VPN ssh）。
   沒試滿就只能寫「**未取得存取**（已試 X、Y、Z，各得到…）」，**不可**寫「無存取」。
3. **閱讀錯誤訊息**：`publickey,password` 訊息 = 還有密碼路可試；別把第一種失敗當成全部失敗。
4. **本質是 §6.7 歸因紀律**：任何「對方有問題／對方做不到」的結論，先證明**你的量測有能力看到那個標的**。
