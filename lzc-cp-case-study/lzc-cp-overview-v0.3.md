# lzc-cp — 異質邊緣節點的控制平面（LinkEazyCenter Control Plane）

> 版本：v0.3（修正 AI-Operator 定位 + 信任模型轉願景 + 用詞精確化）
> 建立：2026-08-29
> 狀態：內部 review 稿，尚未對外

---

## Pitch（30 秒版）

> **lzc-cp：異質邊緣節點的控制平面。**
> 不管你底下多亂（實體機、VM、邊緣裝置，k8s / docker / 原生程序），
> 上面看是一張乾淨的拓撲圖。
> AI agent 幫你操作，不用學 k3s。
> 加再多機器，語言不壞、agent 記得住。
> 不走樣、不離職、不變回一團亂。

---

## 它不是「邊緣運算控制平面」，是四個 UX 承諾

### ① 異質是現實，不是例外

真實世界的邊緣部署：舊 x86 伺服器跑 legacy、Jetson 做影像辨識、mini-PC 跑 docker。OS、算力、部署方式完全不同。傳統做法是**每種機器一套腳本，維運靠人記**。

→ **lzc-cp 的命題：不管你底下多亂，上面看是一張乾淨的拓撲圖。**

### ② 兩軸命名 — 語言永遠不壞

傳統「Type 編號」把兩種資訊硬塞進一個數字：「這是什麼機器」＋「上面怎麼部署」。久了語意一定打結（實例：某個 Type 從「第二台實體機」漂移成「VM 裡跑 hermes＋docker」，沒人說得清）。

lzc-cp 拆成兩個正交維度：

| 軸 | 問的問題 | 選項 |
|:---|:---------|:-----|
| **Node Type** | 節點「本體」是什麼？ | 實體機 / 虛擬機 / 邊緣裝置 |
| **Workload Method** | 上面「怎麼」跑服務？ | K8s Pod / KubeEdge Pod / 容器 / 原生程序 / 本地 LLM |

任何新組合（例如「VM 上跑 ollama」）都不需要發明新編號，寫 `vm_node + ollama_service` 就完成。**語言永遠不壞** — 這是 scale 不犧牲 manageability 的根基。

### ③ AI ops — 複雜性隔離在 agent 後面

使用者**不需要學 k3s / KubeEdge**。AI agent 看得懂兩軸語言、聽得懂自然語言。你問「edge node 上的服務掛了」，它知道去找哪台機器、看 log、給結果 — 甚至能分層定位問題（是 VM 層的資源問題，還是程序層的 bug）。

→ **把基礎設施的複雜性隔離在 agent 後面。使用者只需知道兩件事：什麼機器、什麼服務。**

### ④ 知識留在系統裡，不會離職

邊緣維運知識傳統上長在人身上，人走知識沒了。lzc-cp 讓知識長在系統裡：

```
兩軸命名（活的架構語言）+ SOP（操作手冊）
+ agent 操作記錄（維運記憶）+ 決策紀錄（ADR）
→ 交接不斷層，不會變回一團亂
```

---

## 架構總覽：三平面

```
┌────────────────────────────────────────────────┐
│ Control Plane（控制面）                         │
│ k3s + KubeEdge cloudCore + Ansible + AI ops     │
├────────────────────────────────────────────────┤
│ Data Plane（資料面 = workload 實際跑的地方）    │
│ 實體機 / 虛擬機 / 邊緣裝置（Jetson 等）         │
├────────────────────────────────────────────────┤
│ Network Plane（網路面）                         │
│ Tailscale Mesh VPN → 跨場域安全內網             │
└────────────────────────────────────────────────┘
```

## 目前能力矩陣

| 節點 × 部署方式 | 狀態 | 典型應用 |
|:----------------|:-----|:---------|
| 虛擬機 + 容器服務 | ✅ 已實作 | AI agent 服務、資料庫 |
| 虛擬機 + 原生程序 | ✅ 已實作 | 單一 AI agent 實例 |
| 邊緣裝置 + KubeEdge Pod | ✅ 已實作（VM 模擬）＋ 🔜 真機驗證 | 影像辨識、邊緣 AI 推論 |
| 實體機 + K8s Pod | 📋 藍圖 | 運算擴充節點 |
| 實體機 + 本地 LLM | 📋 藍圖 | 離線 / 低延遲 AI 推論 |

> 真機：Jetson Orin Nano Super 8GB（67 TOPS）已下單，作為邊緣裝置真機，補足 VM 模擬之外的 real-device case。

---

## AI ops 現況：agent 當維運手

lzc-cp 現階段的 AI ops，核心是 **AI agent 擔任維運操作者**，而非 dashboard 展示：

- **自然語言操作** — 不寫 kubectl、不背 API，跟 agent 講需求即可
- **兩軸語言內建** — agent 聽得懂「vm_node + docker_service」這種架構語言，精準定位到機器
- **標準化 SOP** — 每種部署組合一份操作手冊，含驗證步驟與已知踩坑，agent 照手冊執行
- **分層診斷** — 出問題時 agent 會先分「是 VM 層資源問題，還是程序層 bug」，再逐層收斂，不盲目 restart
- **多 agent 協作** — 支援指派 → 執行 → review 的角色分工，維運流程可多人（agent）接力

---

## Roadmap

| 階段 | 內容 | 定位 |
|------|------|------|
| **Phase 0**（~90% 完成） | 單台主機：k3s + KubeEdge + AI ops + Tailscale | 中小企業平價入門 |
| **TODO 1** | 三節點 CP+Workload，提升 scale（非 HA） | 加機器不降 manageability |
| **TODO 2** | 三節點純控制面 HA（etcd quorum） | CP 故障不影響 worker 服務 |
| **TODO 3** | Headscale 取代 Tailscale SaaS | 控制平面完全自營、成本下降 |

### 🎯 規劃中的關鍵 feature：AI-Operator

> **Observability 深度整合，讓 AI ops 從「人工指派」進化到「自主洞察」。**（規劃中，未實作）

設計原則：**AI 不從 raw log 推論，而是查「已結構化的 insight」** — 更快、更便宜、更不容易錯。

```
Pod log → Fluent Bit（parse + label）→ Loki（低成本儲存）
              ├── Deterministic rules ─→ 告警（安全網，不靠 AI）
              └── AI ops agent ───→ PostgreSQL（insight）→ Slack / 看板
```

- **雙軌並行**：確定性規則（threshold 告警）＋ AI 推理（pattern 比對、異常判斷），互相備援，不單押 AI
- **事件記憶**：每次 root cause + 修復記錄寫進資料庫，成為 agent 的持久維運記憶

---

## 願景：多租戶與信任模型（架構藍圖，未全面實作）

從單一部署擴展到服務多個租戶的架構方向。核心原則：**語言統一、資料隔離**。

> **「我給你的是一台 black box。你的資料進去、結果出來。我在外面只能幫你升級語言層和 agent 本體，進不去你的 black box。而且你不是只能相信我 — 你可以自己驗證。」**

| 支柱 | 做法 | 對方怎麼驗證 |
|------|------|-------------|
| 機器具名制 | tenant 機器只在他們自己的網路，operator 網路分開，預設不通 | 看 ACL — 沒有 allow 就是不通 |
| Agent 只看自己 | agent 權限綁定單一 tenant，跨 tenant 工具未載入 | 問 agent「看得到隔壁嗎？」— 連工具都沒有 |
| 資料不出門 | log、記憶、SOP 全在 tenant 自己機器上 | 檢查目錄、network outbound |

- **語言層共用**（兩軸命名、SOP 模板、方法論）— 抽象的、不帶資料
- **資料層隔離**（k3s、網路、agent 記憶）— 一律獨立

---

## 適用場景

- **半導體設備自動化**（SECS/GEM 邊緣整合）
- **智慧製造 / 智慧零售**的邊緣應用管理
- **跨場域 AI 推論節點**（含 Jetson 邊緣 AI、本地 LLM）
- 需要「輕量、可客製、可交付、AI 維運」的邊緣控制平面

---

## 技術棧

`k3s` · `KubeEdge` · `KubeVirt` · `Ansible` · `Tailscale` · `Docker` · `Ollama` · `Hermes Agent`

---

## 內部備註（對外前移除）

- 已去內部代號（hermesa2 → 「AI agent」、lzc/mini-PC → 「單台主機」）
- **AI-Operator（Fluent Bit / Loki）** = 規劃中 feature，非現況；對外若談需標 roadmap
- **信任模型** = 願景藍圖，非已實作
- 待補：定價、SLA、部署規模上限、客戶案例
- 敘事主線取自 KB `lzc-cp-ux-positioning.md` + `lzc-cp-multi-tenant.md` + `observability-aiops-proposal.md`（後者重定位為 AI-Operator roadmap）+ `entities/lzc-cp.md`
