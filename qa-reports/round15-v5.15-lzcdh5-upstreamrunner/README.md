# round15 — Persona DB v5.15 / lzcdh5 / upstream runner

**單版本 API 驗證與回應分析**（依 `api-version-sweep` skill **v2.7.0**）。
**本輪不做跨版本比對** —— 只分析 v5.15 這個版本的回應。

- 主報告：**[ANALYSIS.md](ANALYSIS.md)** ← 先讀這個
- 執行時間：主套件 2026-09-17 **03:27:07Z → 03:52Z**（約 24 分）；探針 **03:53:38Z → 04:18:42Z**
- 結果總覽：主套件 **10/10 HTTP 200**、斷言 **59 ✅ / 0 ❌ / 0 ⚠️**（含補跑的 docker 主機層 #50/#55/#60）；
  延伸自證（A–AF）**210 ✅ / 0 ❌**；探針 **10/10 HTTP 200**
- 受測節點：**lzcdh5**（tailscale `100.96.79.33`；`ubuntu` 帳號，密碼登入）；執行位置：BANGOO WSL2（遠端）
- **部署保真度已驗證（byte 級）**：容器 `api/*.py` sha256 == v5.15 tarball → 見 `extra/deployment-fidelity.txt`

---

## 探針題目原文（供查核；skill v2.4.0 規定必須寫出原文）

| 探針 | 題目原文 | 為什麼要這樣設計 | 本輪結果 |
|:--|:--|:--|:--|
| **`t1`** | `questions=想找同時擁有遊艇與私人飛機的45歲單身女性企業主` | **超出 schema、不可滿足**：24 欄位無「遊艇」／「私人飛機」⇒ 逼出 `pool_exhausted`。自第九輪起的**回歸哨兵** | ✅ `pe=True`（matched=5 < top_k=10）；**但 matched≠0**（本輪 LLM 未過度設限，round14 同題 matched=0） |
| **`t2`** | `questions=時尚服裝設計師的目標客戶`（`top_k=10`，= 主套件 case03 原參數） | **逼出 `overshoot_restore`（#70 A）**：需要某輪放寬後樣本數 **> 40** | ❌ **未達標**：matched=245 但無 broadening（初始即 ≥20 → 直接 target_reached）→ 分支未行使 |
| **`t3`** | `questions=想找做過醫美療程的45歲單身女性` | **逼出 `protection_saturated`（#66 C）**：收窄到讓「已套用維度 ⊆ 保護集」成立 | ✅ **觸發**：matched=1、`applied ⊆ protected`、stop=`protection_saturated` |
| `t4` | `questions=TESLA的目標客戶`（`top_k=20`） | #61 `commute_mode` 保護的回歸 | ✅ `commute_mode` 在 protected、不在 relaxed |

> ⚠️ **這些都是刻意設計的探針，不是業務案例，也不是產品缺陷主張**（「夜市小吃攤的老闆不會真的想找擁有遊艇的人」）。
> **限制**：人造查詢驗的是**分支機制**，不是真實流量。
> `r08`／`r06` 用的是主套件 case08／case06 的**完全相同參數**（`questions`／`role`／`top_k`／`opMode` 順序一致）。

---

## 目錄地圖

| 路徑 | 內容 |
|:--|:--|
| `ANALYSIS.md` | 主報告（§0 環境 / §1 儀器 / §2 執行摘要 / §3 斷言 / §4 回應分析 / §5 限制 / §6 結論 / §7 改動聲明） |
| `raw/` `headers/` `meta/` `json/` | 逐位元組 body、headers、量測欄位＋實際 curl 指令、body 副本 |
| `meta/original-upstream-e3d83cd2.sh` | **原版腳本逐字留存**（sha256 `e3d83cd2…`，609 行） |
| `run-test.sh` | 本輪 runner（sha256 `9cf5e88b…`，561 行；**執行前即記錄**） |
| `meta/script-provenance.txt` | 環境、部署保真度、儀器 sha、忠實度證明、改動清單 |
| `meta/harness-stub-server.py` / `meta/harness-out/` | 執行時行為單元測試（stub 網路） |
| `meta/launch-*.sh` / `meta/run-*-foreground.sh` / `meta/install-key.sh` | 啟動腳本（WSL 背景執行；install-key 裝公鑰免密） |
| `extra/assertions.txt` | 斷言輸出（runner 的 57 ✅ / 5 N/A） |
| `extra/verify-extended.txt` | 延伸自證輸出（210 ✅） |
| `extra/deployment-fidelity.txt` | **部署保真度 + 補跑的 docker 主機層斷言**（#50/#55/#60） |
| `probe/` | §6.8 重現性（r08/r06 各 3 次）+ §6.9 定向（t1–t4）+ `run-probe.sh` |
| `analyze.py` / `verify-extended.py` / `make-summaries.py` | 分析與檢查腳本 |

---

## 複驗指令（每一條都已實跑過）

### 1. 儀器忠實度（請求參數與上游一致）
```bash
diff <(grep -o 'data-urlencode "[^"]*"' run-test.sh) \
     <(grep -o 'data-urlencode "[^"]*"' meta/original-upstream-e3d83cd2.sh) && echo "✓ 請求參數一致"
```

### 2. §6.1–§6.6 回應分析
```bash
python3 analyze.py
```

### 3. 延伸自證檢查（A–AF；含由契約推導的來源鍵檢查）
```bash
python3 verify-extended.py
```

### 4. §6.8 重現性：r08/r06 主體護欄與核心維度
```bash
python3 - <<'PY'
import json, pathlib
def L(p): return json.loads(pathlib.Path(p).read_text(encoding="utf-8"))
for tag in ("r08_boss","r06_aesthetic"):
    for i in (1,2,3):
        d=L(f"probe/{tag}_{i}.body"); af=d.get("applied_filters") or {}
        print(f"  {tag}_{i}: matched={d['total_matched']:3d} subject={d.get('subject')!r:9s} "
              f"emp={af.get('employment_status')} aes={af.get('aesthetic_procedure')} "
              f"protected={d.get('protected_dims')}")
PY
```

### 5. §6.9 定向探針
```bash
python3 - <<'PY'
import json, pathlib
def L(p): return json.loads(pathlib.Path(p).read_text(encoding="utf-8"))
for t, want in (("t1_narrow_topk10","pool_exhausted"),
                ("t2_fashion_overshoot","overshoot_restore #70 A"),
                ("t3_aesthetic_narrow","protection_saturated #66 C"),
                ("t4_tesla_topk20","#61 commute_mode")):
    d=L(f"probe/{t}.body"); af=set(d["applied_filters"] or {}); pd=set(d["protected_dims"] or [])
    ba=d.get("broadening_attempts") or []
    print(f"  {t:22s} matched={d['total_matched']:3d} stop={d['broadening_stop_reason']!r:22s} 目標={want}")
    print(f"  {'':22s} applied⊆protected? {af<=pd}  overshoot={[b.get('overshoot') for b in ba]}  "
          f"restore={[b.get('overshoot_restore') for b in ba]}")
PY
```

### 6. `#72` llm_calls 揭露（v5.15 新斷言）
```bash
python3 - <<'PY'
import json, pathlib
for c in ("01_kangshimei","05_role_banker","07_debt"):
    d=json.loads(pathlib.Path(f"raw/{c}.body").read_text(encoding="utf-8"))
    print(f"  {c}: llm_calls={d.get('llm_calls')} attempts={len(d.get('broadening_attempts') or [])}")
PY
```

### 7. 部署保真度 + docker 主機層斷言（需 `ubuntu` SSH 存取）
```bash
LZ="ssh ubuntu@100.96.79.33"   # 密碼登入（已裝公鑰後免密）
# byte 級保真度：容器 api/*.py == tarball
$LZ 'docker exec persona-db-api sha256sum /app/api/server.py'
tar -xzf ~/repos/persona-db-release/upDockerVerHermes/persona-db-rel-v5.15.tar.gz \
    -O persona-db-rel-v5.15/api/server.py | sha256sum      # → 應相同（1ab44330…）
# #50 / #55 / #60
$LZ 'docker exec persona-db-api cat /app/VERSION; cat ~/persona-db-release/upDockerVerHermes/RELEASE-VERSION'
$LZ 'docker exec persona-db-api grep -c "LLM call failed \[" /app/api/llm.py'
# ⚠️ docker logs 會截斷（log 檔 NUL hole）→ 直接讀 log 檔：
$LZ 'CID=$(docker inspect persona-db-api --format "{{.Id}}"); sudo grep -c "Protected dims" \
     /var/lib/docker/containers/$CID/$CID-json.log'    # → 15（非 0）
```

### 8. 打包缺陷：tarball 內 RELEASE-VERSION 未 bump
```bash
tar -xzf ~/repos/persona-db-release/upDockerVerHermes/persona-db-rel-v5.15.tar.gz \
    -O persona-db-rel-v5.15/RELEASE-VERSION   # → v5.14（節點工作目錄為 v5.15）
```
