#!/usr/bin/env python3
"""產出 summary-per-case.csv / summary-per-persona.csv / summary-all-cases.json。

標籤修復說明：主套件的 run.log 案例標題印成了 tmpname（例：`kangshimei`）而不是
標籤原文 —— 原因是我 case_run 的 `local label="$2"; shift` 位移錯誤（詳見
meta/known-defects.txt）。**請求本身不受影響**（已用 url_effective 逐案驗證）。
本腳本從（已修好的）run-test.sh 取回標籤原文，作為表格用的正確標籤。
"""
import csv
import json
import pathlib
import re

TOP_K = {"01_kangshimei": 3, "02_tesla": 3, "03_fashion": 10, "04_role_fangzhong": 5,
         "05_role_banker": 5, "06_aesthetic": 10, "07_debt": 10, "08_boss": 10, "09_owner": 10}
ORDER = ["00_status"] + list(TOP_K)

# 從 run-test.sh 取回標籤原文（案例順序即 CASE_ORDER）
runner = pathlib.Path("run-test.sh").read_text(encoding="utf-8")
labels = dict(re.findall(r'case_run "([^"]*)" "(.*?)" "', runner))
# upstream 的 echo 是 `=== <label> ===`；case_run 直接印 label，故此處即原文
assert len(labels) == 9, f"應取到 9 個標籤，實得 {len(labels)}"


def meta_val(cid, key):
    p = pathlib.Path(f"meta/{cid}.meta")
    if not p.exists():
        return ""
    for line in p.read_text(encoding="utf-8").split("\n"):
        if line.startswith(f"{key}="):
            return line.split("=", 1)[1]
    return ""


def main():
    cases = []
    personas = []
    for cid in ORDER:
        body = pathlib.Path(f"raw/{cid}.body")
        d = {}
        if body.exists() and cid != "00_status":
            try:
                d = json.loads(body.read_text(encoding="utf-8"))
            except Exception:
                d = {}
        ba = d.get("broadening_attempts") or []
        rows = d.get("summary") or []
        label = labels.get(cid, "0. /personadb/status（upstream 無標籤）")
        cases.append({
            "case": cid,
            "label": label,
            "http_code": meta_val(cid, "http_code"),
            "time_total_s": meta_val(cid, "time_total"),
            "bytes": meta_val(cid, "size_download"),
            "top_k": TOP_K.get(cid, ""),
            "total_matched": d.get("total_matched", ""),
            "returned": d.get("returned", ""),
            "len_summary": len(rows),
            "pool_exhausted": d.get("pool_exhausted", ""),
            "loops": len(ba),
            "no_op": sum(1 for b in ba if b.get("no_op")),
            "overshoot": sum(1 for b in ba if b.get("overshoot")),
            "stop_reason": d.get("broadening_stop_reason", ""),
            "relaxed_dims": "/".join(d.get("relaxed_dims") or []),
            "applied_filters": json.dumps(d.get("applied_filters") or {}, ensure_ascii=False),
            "domain": (d.get("llm_analysis") or {}).get("domain", ""),
        })
        for rank, r in enumerate(rows, 1):
            personas.append({
                "case": cid, "rank": rank, "id": r.get("id"), "name": r.get("name"),
                "score": r.get("score"), "sex": r.get("sex"), "age": r.get("age"),
                "employment_status": r.get("employment_status"),
                "aesthetic_procedure": r.get("aesthetic_procedure"),
                "debt_status": r.get("debt_status"),
                "housing_burden": r.get("housing_burden"),
                "region": r.get("region"),
            })

    with open("summary-per-case.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(cases[0].keys()))
        w.writeheader()
        w.writerows(cases)
    with open("summary-per-persona.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(personas[0].keys()))
        w.writeheader()
        w.writerows(personas)
    with open("summary-all-cases.json", "w", encoding="utf-8") as f:
        json.dump({"cases": cases, "labels_from": "run-test.sh（修復後）"}, f,
                  ensure_ascii=False, indent=2)

    print(f"✅ summary-per-case.csv      {len(cases)} 列")
    print(f"✅ summary-per-persona.csv   {len(personas)} 列")
    print(f"✅ summary-all-cases.json")
    tot = sum(float(c["time_total_s"] or 0) for c in cases if c["time_total_s"])
    llm = [float(c["time_total_s"]) for c in cases if c["http_code"] == "200" and c["case"] != "00_status"]
    print(f"\n  總耗時 {tot:.1f}s；9 個候選案例合計 {sum(llm):.1f}s，"
          f"平均 {sum(llm)/len(llm):.1f}s，最大 {max(llm):.1f}s")
    mx = max(cases, key=lambda c: float(c["time_total_s"] or 0))
    print(f"  最慢：{mx['case']} {float(mx['time_total_s']):.1f}s")


if __name__ == "__main__":
    main()
