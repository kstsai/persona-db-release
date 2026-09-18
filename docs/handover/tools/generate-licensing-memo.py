#!/usr/bin/env python3
"""產生一頁式「第三方資料來源與授權事項」memo（A4、中文）。

相依：reportlab（pip install reportlab）
字型：/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc（文泉驛正黑，系統字型）

用法：python3 generate-licensing-memo.py [輸出目錄]
"""
import sys, os, datetime

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, Table,
                                TableStyle, KeepTogether)

FONT_PATH = "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc"
OUT_DIR = sys.argv[1] if len(sys.argv) > 1 else "."
OUT = os.path.join(OUT_DIR, "SOURCE-LICENSING-MEMO.pdf")
VERSION = os.environ.get("PDB_VERSION", "v5.18")
DATE = os.environ.get("PDB_DATE", "2026-09-17")

pdfmetrics.registerFont(TTFont("WQY", FONT_PATH))
pdfmetrics.registerFontFamily("WQY", normal="WQY", bold="WQY", italic="WQY", boldItalic="WQY")

TITLE = ParagraphStyle("t", fontName="WQY", fontSize=15, leading=19, spaceAfter=2)
SUB = ParagraphStyle("s", fontName="WQY", fontSize=8, leading=11,
                     textColor=colors.HexColor("#555555"), spaceAfter=7)
H = ParagraphStyle("h", fontName="WQY", fontSize=10, leading=13,
                   textColor=colors.HexColor("#123a6b"), spaceBefore=6, spaceAfter=2)
BODY = ParagraphStyle("b", fontName="WQY", fontSize=8, leading=11.4)
CELL = ParagraphStyle("c", fontName="WQY", fontSize=7.4, leading=10)
CELLB = ParagraphStyle("cb", fontName="WQY", fontSize=7.4, leading=10,
                       textColor=colors.HexColor("#8a1c1c"))
FOOT = ParagraphStyle("f", fontName="WQY", fontSize=6.8, leading=9,
                      textColor=colors.HexColor("#666666"))

story = []
story.append(Paragraph("Persona DB — 第三方資料來源與授權事項（法務 review 用）", TITLE))
story.append(Paragraph(
    f"交付版本 <b>{VERSION}</b>　·　memo 日期 {DATE}　·　完整清單：交付包 <font face='WQY'>THIRD-PARTY-DATA.md</font>"
    "　·　本檔為一頁摘要，逐條明細以完整清單為準", SUB))

# ── 1. 結論 ───────────────────────────────────────────────
story.append(Paragraph("一、結論（三句話）", H))
story.append(Paragraph(
    "① 22 個維度中 <b>18 個</b>來自台灣<b>政府開放資料</b>（可再散布，<b>只需註明出處</b>，無需取得授權）；"
    "② <b>2 個</b>來自<b>非開放授權來源</b>（JCIC 聯徵中心、ISAPS 商業報告）—— <b>請確認授權</b>，"
    "且其原始檔／報告原文<b>已自本次交付移除</b>；"
    "③ <b>3 個</b>維度（政治傾向、媒體習慣、興趣嗜好）<b>沒有外部來源</b>，為交付方的方法論<b>假設值</b>。"
    "姓名、地點、校名<b>全部虛構</b>。", BODY))

# ── 2. 政府開放資料 ───────────────────────────────────────
story.append(Paragraph("二、政府開放資料（可再散布，須註明出處）", H))
rows = [[Paragraph("來源機關", CELL), Paragraph("資料集（年度）", CELL), Paragraph("對應維度", CELL)]]
for a, b, c in [
    ("內政部戶政司", "113 年人口統計／各縣市人口分布／戶口統計", "年齡、性別、區域、戶籍地、家庭口數、婚姻狀況"),
    ("行政院主計總處（DGBAS）", "113 年家庭收支調查（所得面／消費面）", "個人收入、家庭可支配所得、家戶所得分級、物價分級、居住支出、服飾消費"),
    ("行政院主計總處（DGBAS）", "113 年人力資源調查統計年報（表 47／48）", "教育、職業、失業率、從業身分"),
    ("交通部", "2024 年運具分配調查", "通勤方式"),
    ("中央銀行", "不動產信用管制措施（政策參照）", "居住支出上限規則之對照依據（非資料引用）"),
]:
    rows.append([Paragraph(a, CELL), Paragraph(b, CELL), Paragraph(c, CELL)])
t = Table(rows, colWidths=[32 * mm, 62 * mm, 82 * mm])
t.setStyle(TableStyle([
    ("GRID", (0, 0), (-1, -1), 0.3, colors.HexColor("#b8c6da")),
    ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#eef3fa")),
    ("VALIGN", (0, 0), (-1, -1), "TOP"),
    ("LEFTPADDING", (0, 0), (-1, -1), 3), ("RIGHTPADDING", (0, 0), (-1, -1), 3),
    ("TOPPADDING", (0, 0), (-1, -1), 2), ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
]))
story.append(t)

# ── 3. 需確認授權 ─────────────────────────────────────────
story.append(Paragraph("三、需確認授權的來源（2 項）", H))
rows = [[Paragraph("來源", CELL), Paragraph("對應維度／我們實際使用的內容", CELL),
         Paragraph("本次交付", CELL), Paragraph("建議動作", CELLB)]]
rows.append([Paragraph("<b>JCIC 聯徵中心</b><br/>個人授信統計（2026-03/04）", CELL),
             Paragraph("維度 21 債務背貸狀態。<b>只用人數比例</b>：信貸借款人 188 萬（年齡×性別）、"
                       "房貸 226 萬、車貸 36 萬、卡債 11.27%、房貸×信貸交叉 18.7%。<b>金額欄位完全未使用</b>。", CELL),
             Paragraph("未附原始 CSV（僅交付衍生比率）", CELL),
             Paragraph("若貴方需以原始資料重建資料庫，請依 JCIC 條款自行取得", CELLB)])
rows.append([Paragraph("<b>ISAPS Global Survey 2024</b><br/>（原始資料為貴方提供）", CELL),
             Paragraph("維度 20 醫美療程經歷。<b>只引用統計數字</b>：年療程 658,320 例、"
                       "手術型 39%／非手術型 61%（→ 年盛行率 ~2.8%）。", CELL),
             Paragraph("未附報告 PDF", CELL),
             Paragraph("若後續要引用報告<b>圖表</b>，請依報告授權條款確認", CELLB)])
t = Table(rows, colWidths=[38 * mm, 74 * mm, 33 * mm, 31 * mm])
t.setStyle(TableStyle([
    ("GRID", (0, 0), (-1, -1), 0.3, colors.HexColor("#d9b8b8")),
    ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#fbeeee")),
    ("VALIGN", (0, 0), (-1, -1), "TOP"),
    ("LEFTPADDING", (0, 0), (-1, -1), 3), ("RIGHTPADDING", (0, 0), (-1, -1), 3),
    ("TOPPADDING", (0, 0), (-1, -1), 2), ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
]))
story.append(t)

# ── 4. 假設值 ────────────────────────────────────────────
story.append(Paragraph("四、無外部來源 → 方法論假設值（無授權問題，但應知悉）", H))
story.append(Paragraph(
    "政治傾向的地區比例、媒體習慣的比例、興趣嗜好的分布，均為<b>交付方的設計假設</b>（未引用任何民調或媒體調查資料集）。"
    "醫美的<b>分段</b>盛行率（女 19-24 2%／25-44 6%／45-64 3%／65+ 0.5%／男 0.5%）同為假設值，"
    "已於製作階段<b>經貴方確認</b>；ISAPS 僅提供總量率。若貴方希望為上述項目補上正式來源，"
    "可採<b>就地補註（in-place annotate）</b>方式更新，無須重建整份資料庫。", BODY))

# ── 5. 授權狀態與已處置 ───────────────────────────────────
story.append(Paragraph("五、本交付內容的授權狀態與已完成處置", H))
story.append(Paragraph(
    "<b>授權狀態</b>：本交付內容目前<b>未附授權條款</b>（未附授權＝保留所有權利）。"
    "除交付合約／書面同意所授予者外，未授予使用、修改或再散布的權利。"
    "若貴方需要明確的授權範圍（內部修改、再部署、轉授權），請以書面確認 —— 建議於合約或另附授權書載明。", BODY))
story.append(Paragraph(
    "<b>已完成處置</b>：自 {v} 起，交付包<b>不再包含</b> JCIC 原始 CSV、ISAPS 報告 PDF、"
    "以及交付方的內部工作文件；交付包僅保留衍生結果與來源說明。"
    "<b>先前版本的殘留</b>：{v} 之前交付的壓縮檔內曾含上述受限制資料，該些檔案仍存在於交付 repo 的版本歷史中"
    "（未改寫歷史，因既有驗證紀錄引用其版本識別）。".format(v=VERSION), BODY))

# ── 6. review 檢查表 ─────────────────────────────────────
story.append(Paragraph("六、建議 review 檢查表", H))
for x in [
    "政府開放資料：確認出處標註位置可接受（README、規格書、權重表 _meta）→ 無需授權",
    "JCIC：確認貴方是否已／需要取得授權；若需原始資料請自行依其條款下載",
    "ISAPS：確認採購條件是否涵蓋本用途；後續引用圖表需另取得授權",
    "假設值（政治傾向／媒體習慣／興趣嗜好／醫美分段率）：確認可接受，或指定要補的正式來源",
    "本交付內容授權：確認合約已載明使用／修改／再散布範圍（或指定加上正式授權條款）",
]:
    story.append(Paragraph(f"☐　{x}", BODY))

story.append(Spacer(1, 3 * mm))
story.append(Paragraph(
    "逐條明細（22 個維度逐一對照、含年度與使用的具體數字）：交付包 <b>THIRD-PARTY-DATA.md</b>；"
    "資料來源的實作對照另見 <b>dim_weights.json → _meta.data_sources</b> 與規格書「維度設計」章。"
    "本 memo 為摘要，如有疑義以完整清單為準。", FOOT))

doc = SimpleDocTemplate(OUT, pagesize=A4, topMargin=13 * mm, bottomMargin=11 * mm,
                        leftMargin=13 * mm, rightMargin=13 * mm,
                        title="Persona DB 第三方資料來源與授權事項", author="Persona DB 交付方")
doc.build(story)
print(f"✅ {OUT}")
