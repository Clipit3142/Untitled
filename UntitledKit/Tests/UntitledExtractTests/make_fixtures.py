#!/usr/bin/env python3
"""Builds the E1/E2 extraction fixtures: one file per allowed type, each carrying the key phrase
"Alpine Ledger". Needs ImageMagick, LibreOffice, reportlab and pypdf. HEIC and the iWork formats
(Pages, Numbers, Keynote) can't be written on Linux: the macOS tests make the HEIC with ImageIO,
and the iWork fixtures must be saved from the apps into Fixtures/iwork/.

Run from this directory:  python3 make_fixtures.py
"""
import os
import shutil
import subprocess
import tempfile

from pypdf import PdfReader, PdfWriter
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "Fixtures")
PHRASE = "Alpine Ledger"
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def run(*args, cwd=None):
    subprocess.run(args, check=True, cwd=cwd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def images():
    png = os.path.join(OUT, "image.png")
    run("convert", "-size", "1600x500", "xc:white", "-font", FONT, "-pointsize", "130", "-fill", "black",
        "-gravity", "center", "-annotate", "+0+0", PHRASE, png)
    for ext in ("jpg", "tiff", "gif", "webp"):
        run("convert", png, os.path.join(OUT, f"image.{ext}"))
    return png


def pdfs(png):
    # Text PDF: the phrase on page 1 (E1).
    path = os.path.join(OUT, "document.pdf")
    c = canvas.Canvas(path, pagesize=A4)
    c.setFont("Helvetica-Bold", 28)
    c.drawString(72, 760, f"{PHRASE} quarterly statement")
    c.setFont("Helvetica", 12)
    c.drawString(72, 730, "Statement date: 27 November 2026")
    c.save()
    # Five pages, the phrase only on page 3 (E2: only the configured number of pages is read).
    path = os.path.join(OUT, "five-pages.pdf")
    c = canvas.Canvas(path, pagesize=A4)
    for page in range(1, 6):
        c.setFont("Helvetica", 14)
        text = f"{PHRASE} appears on this page" if page == 3 else f"Page {page} of a long report with ordinary filler text"
        c.drawString(72, 760, text)
        c.showPage()
    c.save()
    # A scan: an image-only page, read with OCR (3.7).
    run("convert", png, "-background", "white", "-gravity", "center", "-extent", "1700x2200", "-units", "PixelsPerInch",
        "-density", "200", os.path.join(OUT, "scanned.pdf"))
    # Password protected: metadata only, never a prompt (E2).
    writer = PdfWriter()
    for page in PdfReader(os.path.join(OUT, "document.pdf")).pages:
        writer.add_page(page)
    writer.encrypt(user_password="secret", owner_password="owner-secret")
    with open(os.path.join(OUT, "protected.pdf"), "wb") as handle:
        writer.write(handle)


def text_documents():
    with open(os.path.join(OUT, "document.txt"), "w") as handle:
        handle.write(f"{PHRASE}\nPlain text fixture for extraction.\n")
    with open(os.path.join(OUT, "document.md"), "w") as handle:
        handle.write(f"# {PHRASE}\n\nMarkdown fixture for extraction.\n")
    html = os.path.join(OUT, "document.html")
    with open(html, "w") as handle:
        handle.write(f"<!doctype html><html><head><meta charset='utf-8'><title>{PHRASE}</title></head>"
                     f"<body><h1>{PHRASE}</h1><p>HTML fixture for extraction.</p></body></html>\n")
    with open(os.path.join(OUT, "document.rtf"), "w") as handle:
        handle.write("{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Helvetica;}}\\f0\\fs48 " + PHRASE + "\\par\\fs24 RTF fixture for extraction.\\par}\n")
    work = tempfile.mkdtemp()
    try:
        shutil.copy(html, os.path.join(work, "document.html"))
        for target, name in (("docx:MS Word 2007 XML", "document.docx"), ("doc:MS Word 97", "document.doc")):
            run("soffice", "--headless", "--convert-to", target, "--outdir", work, os.path.join(work, "document.html"))
            shutil.move(os.path.join(work, name), os.path.join(OUT, name))
        # A spreadsheet with the phrase in large type, so the Quick Look thumbnail OCR can read it.
        sheet = os.path.join(work, "sheet.fods")
        with open(sheet, "w") as handle:
            handle.write(f"""<?xml version="1.0" encoding="UTF-8"?>
<office:document xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
 xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
 xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
 office:version="1.3" office:mimetype="application/vnd.oasis.opendocument.spreadsheet">
 <office:automatic-styles>
  <style:style style:name="wide" style:family="table-column"><style:table-column-properties style:column-width="12cm"/></style:style>
  <style:style style:name="tall" style:family="table-row"><style:table-row-properties style:row-height="2cm"/></style:style>
  <style:style style:name="big" style:family="table-cell"><style:text-properties fo:font-size="36pt" fo:font-weight="bold"/></style:style>
 </office:automatic-styles>
 <office:body><office:spreadsheet><table:table table:name="Sheet1">
  <table:table-column table:style-name="wide"/>
  <table:table-row table:style-name="tall"><table:table-cell table:style-name="big" office:value-type="string"><text:p>{PHRASE}</text:p></table:table-cell></table:table-row>
  <table:table-row><table:table-cell office:value-type="string"><text:p>Spreadsheet fixture</text:p></table:table-cell></table:table-row>
 </table:table></office:spreadsheet></office:body></office:document>
""")
        run("soffice", "--headless", "--convert-to", "xlsx:Calc MS Excel 2007 XML", "--outdir", work, sheet, cwd=work)
        shutil.move(os.path.join(work, "sheet.xlsx"), os.path.join(OUT, "sheet.xlsx"))
        # A one-slide presentation with the phrase as its title.
        fodp = os.path.join(work, "slides.fodp")
        with open(fodp, "w") as handle:
            handle.write(f"""<?xml version="1.0" encoding="UTF-8"?>
<office:document xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
 xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
 xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
 xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" office:version="1.3" office:mimetype="application/vnd.oasis.opendocument.presentation">
 <office:automatic-styles><style:style style:name="big" style:family="paragraph"><style:text-properties fo:font-size="60pt" fo:font-weight="bold"/></style:style></office:automatic-styles>
 <office:body><office:presentation><draw:page draw:name="page1">
  <draw:frame svg:x="1cm" svg:y="4cm" svg:width="26cm" svg:height="6cm"><draw:text-box><text:p text:style-name="big">{PHRASE}</text:p></draw:text-box></draw:frame>
 </draw:page></office:presentation></office:body></office:document>
""")
        run("soffice", "--headless", "--convert-to", "pptx:Impress MS PowerPoint 2007 XML", "--outdir", work, fodp, cwd=work)
        shutil.move(os.path.join(work, "slides.pptx"), os.path.join(OUT, "slides.pptx"))
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    png = images()
    pdfs(png)
    text_documents()
    for name in sorted(os.listdir(OUT)):
        print(f"{os.path.getsize(os.path.join(OUT, name)):>8}  {name}")


main()
