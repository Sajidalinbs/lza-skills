#!/usr/bin/env python3
"""
Markdown -> .docx, standard library only (no python-docx, no pandoc).

Built for the customer-facing artifacts in this repo:
  * lza-intake-form.md          -> <Customer>_AWS_LZA_Intake.docx   (customer fills it in)
  * <customer>-lza-plan.md      -> <Customer>_AWS_LZA_Plan.docx     (customer signs it off)

Usage
  python3 make_docx.py lza-intake-form.md                       # -> lza-intake-form.docx
  python3 make_docx.py lza-intake-form.md Acme_Intake.docx --customer "Acme Corp"
  python3 make_docx.py ../acme-lza-plan.md --customer Acme

--customer replaces every "<Customer>"/"<customer>" placeholder in the source.

Supported Markdown: # ## ### #### headings, paragraphs, pipe tables (with header
shading + borders), - / * bullets (nested by indent), 1. lists, > blockquotes,
- [ ] checkboxes, ``` fenced code, --- rules, and inline **bold**, *italic*,
`code`, [text](link).
"""

import html
import re
import sys
import zipfile
from pathlib import Path

W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"


def esc(text):
    return html.escape(text, quote=False).replace('"', "&quot;")


# --------------------------------------------------------------------------- #
# inline runs
# --------------------------------------------------------------------------- #

INLINE_RE = re.compile(
    r"(\*\*.+?\*\*|__.+?__|\*[^*\n]+?\*|`[^`\n]+?`|\[[^\]]+\]\([^)]*\))"
)


def runs(text, bold=False, italic=False, mono=False):
    """Render inline markdown as a list of <w:r> strings."""
    out = []
    for part in INLINE_RE.split(text):
        if not part:
            continue
        b, i, m, body = bold, italic, mono, part
        if part.startswith("**") and part.endswith("**"):
            b, body = True, part[2:-2]
        elif part.startswith("__") and part.endswith("__"):
            b, body = True, part[2:-2]
        elif part.startswith("*") and part.endswith("*") and len(part) > 2:
            i, body = True, part[1:-1]
        elif part.startswith("`") and part.endswith("`"):
            m, body = True, part[1:-1]
        elif part.startswith("["):
            body = re.sub(r"^\[([^\]]+)\]\([^)]*\)$", r"\1", part)
        props = ""
        if b:
            props += "<w:b/>"
        if i:
            props += "<w:i/>"
        if m:
            props += '<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/><w:color w:val="A31515"/>'
        rpr = f"<w:rPr>{props}</w:rPr>" if props else ""
        out.append(f'<w:r>{rpr}<w:t xml:space="preserve">{esc(body)}</w:t></w:r>')
    return out or ['<w:r><w:t xml:space="preserve"></w:t></w:r>']


def para(text="", style=None, indent=0, spacing_before=0, mono=False, shade=None):
    props = []
    if style:
        props.append(f'<w:pStyle w:val="{style}"/>')
    if indent:
        props.append(f'<w:ind w:left="{indent}"/>')
    if spacing_before:
        props.append(f'<w:spacing w:before="{spacing_before}"/>')
    if shade:
        props.append(f'<w:shd w:val="clear" w:color="auto" w:fill="{shade}"/>')
    ppr = f"<w:pPr>{''.join(props)}</w:pPr>" if props else ""
    body = (
        f'<w:r><w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/><w:sz w:val="18"/></w:rPr>'
        f'<w:t xml:space="preserve">{esc(text)}</w:t></w:r>'
        if mono
        else "".join(runs(text))
    )
    return f"<w:p>{ppr}{body}</w:p>"


def horizontal_rule():
    return (
        '<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" '
        'w:color="BFBFBF"/></w:pBdr></w:pPr></w:p>'
    )


# --------------------------------------------------------------------------- #
# tables
# --------------------------------------------------------------------------- #

HEADER_FILL = "DCE6F1"


def split_row(line):
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|"):
        line = line[:-1]
    return [c.strip() for c in re.split(r"(?<!\\)\|", line)]


def is_separator(line):
    return bool(re.fullmatch(r"\s*\|?[\s:|-]*-[\s:|-]*\|?\s*", line)) and "-" in line


def cell(text, header=False, width=None):
    props = ['<w:tcW w:w="%s" w:type="%s"/>' % ((width, "pct") if width else (0, "auto"))]
    if header:
        props.append(f'<w:shd w:val="clear" w:color="auto" w:fill="{HEADER_FILL}"/>')
    props.append('<w:vAlign w:val="center"/>')
    body = "".join(runs(text, bold=header)) if text else ""
    if not body:
        body = '<w:r><w:t xml:space="preserve"></w:t></w:r>'
    return (
        f"<w:tc><w:tcPr>{''.join(props)}</w:tcPr>"
        f'<w:p><w:pPr><w:spacing w:before="20" w:after="20"/></w:pPr>{body}</w:p></w:tc>'
    )


def table(rows, has_header=True):
    if not rows:
        return ""
    ncols = max(len(r) for r in rows)
    width_each = int(5000 / ncols)
    borders = "".join(
        f'<w:{edge} w:val="single" w:sz="4" w:space="0" w:color="B4B4B4"/>'
        for edge in ("top", "left", "bottom", "right", "insideH", "insideV")
    )
    xml = [
        '<w:tbl><w:tblPr><w:tblW w:w="5000" w:type="pct"/>'
        f"<w:tblBorders>{borders}</w:tblBorders>"
        '<w:tblLayout w:type="fixed"/></w:tblPr>',
        "<w:tblGrid>" + f'<w:gridCol w:w="{int(9360 / ncols)}"/>' * ncols + "</w:tblGrid>",
    ]
    for idx, row in enumerate(rows):
        row = list(row) + [""] * (ncols - len(row))
        header = has_header and idx == 0
        trpr = "<w:trPr><w:tblHeader/></w:trPr>" if header else ""
        xml.append(
            f"<w:tr>{trpr}"
            + "".join(cell(c, header=header, width=width_each) for c in row)
            + "</w:tr>"
        )
    xml.append("</w:tbl>")
    # Word needs a paragraph after a table (and between adjacent tables).
    xml.append('<w:p><w:pPr><w:spacing w:after="0"/></w:pPr></w:p>')
    return "".join(xml)


# --------------------------------------------------------------------------- #
# block parser
# --------------------------------------------------------------------------- #

BULLET_RE = re.compile(r"^(\s*)[-*+]\s+(.*)$")
NUM_RE = re.compile(r"^(\s*)(\d+)[.)]\s+(.*)$")


def convert(md):
    body, lines, i = [], md.splitlines(), 0
    first_heading = True
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        # fenced code
        if stripped.startswith("```"):
            i += 1
            while i < len(lines) and not lines[i].strip().startswith("```"):
                body.append(para(lines[i], mono=True, indent=360, shade="F4F4F4"))
                i += 1
            i += 1
            continue

        if not stripped:
            i += 1
            continue

        # horizontal rule
        if re.fullmatch(r"(\*\s*){3,}|(-\s*){3,}|(_\s*){3,}", stripped):
            body.append(horizontal_rule())
            i += 1
            continue

        # table
        if stripped.startswith("|") and i + 1 < len(lines) and is_separator(lines[i + 1]):
            rows = [split_row(stripped)]
            i += 2
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append(split_row(lines[i]))
                i += 1
            # a two-column "| | |" grid with an empty header reads better headerless
            has_header = any(c for c in rows[0])
            body.append(table(rows, has_header=has_header))
            continue

        # heading
        m = re.match(r"^(#{1,6})\s+(.*)$", stripped)
        if m:
            level = len(m.group(1))
            style = "Title" if (level == 1 and first_heading) else f"Heading{min(level, 4)}"
            body.append(para(m.group(2), style=style))
            first_heading = False
            i += 1
            continue

        # blockquote — shaded callout; inner code fences render monospaced
        if stripped.startswith(">"):
            in_code = False
            while i < len(lines) and lines[i].strip().startswith(">"):
                q = re.sub(r"^\s*>\s?", "", lines[i]).rstrip()
                i += 1
                if q.strip().startswith("```"):
                    in_code = not in_code
                    continue
                if not q.strip():
                    continue
                body.append(para(q, indent=360, shade="FBF6E4", mono=in_code))
            continue

        # checkbox
        m = re.match(r"^\s*[-*]\s+\[( |x|X)\]\s+(.*)$", line)
        if m:
            box = "☒" if m.group(1).lower() == "x" else "☐"
            body.append(para(f"{box}  {m.group(2)}", indent=360))
            i += 1
            continue

        # bullet
        m = BULLET_RE.match(line)
        if m:
            depth = len(m.group(1)) // 2
            bullet = ["•", "◦", "▪"][min(depth, 2)]
            body.append(para(f"{bullet}  {m.group(2)}", indent=360 + depth * 360))
            i += 1
            continue

        # numbered
        m = NUM_RE.match(line)
        if m:
            depth = len(m.group(1)) // 2
            body.append(para(f"{m.group(2)}.  {m.group(3)}", indent=360 + depth * 360))
            i += 1
            continue

        # paragraph
        body.append(para(stripped))
        i += 1

    return "".join(body)


# --------------------------------------------------------------------------- #
# package
# --------------------------------------------------------------------------- #

CONTENT_TYPES = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>"""

ROOT_RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>"""

DOC_RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>"""


def _style(sid, name, size, color, bold=True, before=240, after=120, outline=None):
    ol = f'<w:outlineLvl w:val="{outline}"/>' if outline is not None else ""
    return (
        f'<w:style w:type="paragraph" w:styleId="{sid}"><w:name w:val="{name}"/>'
        f'<w:basedOn w:val="Normal"/><w:qFormat/>'
        f'<w:pPr><w:keepNext/><w:spacing w:before="{before}" w:after="{after}"/>{ol}</w:pPr>'
        f'<w:rPr><w:rFonts w:ascii="Calibri Light" w:hAnsi="Calibri Light"/>'
        f'{"<w:b/>" if bold else ""}<w:color w:val="{color}"/><w:sz w:val="{size}"/></w:rPr></w:style>'
    )


STYLES = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="{W_NS}">
<w:docDefaults><w:rPrDefault><w:rPr>
<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="20"/></w:rPr></w:rPrDefault>
<w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="264" w:lineRule="auto"/></w:pPr></w:pPrDefault>
</w:docDefaults>
<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>
{_style("Title", "Title", 48, "1F3864", before=0, after=240)}
{_style("Heading1", "heading 1", 32, "1F3864", outline=0)}
{_style("Heading2", "heading 2", 26, "2E5C8A", outline=1)}
{_style("Heading3", "heading 3", 22, "2E5C8A", outline=2)}
{_style("Heading4", "heading 4", 20, "404040", outline=3)}
</w:styles>"""


def build(md, out_path):
    document = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        f'<w:document xmlns:w="{W_NS}"><w:body>'
        + convert(md)
        + '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1134" w:right="1021" w:bottom="1134" w:left="1021" '
        'w:header="709" w:footer="709" w:gutter="0"/></w:sectPr>'
        "</w:body></w:document>"
    )
    with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", CONTENT_TYPES)
        z.writestr("_rels/.rels", ROOT_RELS)
        z.writestr("word/_rels/document.xml.rels", DOC_RELS)
        z.writestr("word/styles.xml", STYLES)
        z.writestr("word/document.xml", document)


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    customer = None
    for a in argv[1:]:
        if a.startswith("--customer="):
            customer = a.split("=", 1)[1]
    if "--customer" in argv:
        customer = argv[argv.index("--customer") + 1]
        args = [a for a in args if a != customer]

    if not args:
        print(__doc__)
        return 1

    src = Path(args[0])
    if not src.exists():
        print(f"error: {src} not found")
        return 1

    md = src.read_text(encoding="utf-8")
    if customer:
        md = md.replace("<Customer>", customer).replace("<customer>", customer.lower())

    if len(args) > 1:
        out = Path(args[1])
    elif customer:
        slug = re.sub(r"[^A-Za-z0-9]+", "_", customer).strip("_")
        stem = "AWS_LZA_Plan" if "plan" in src.stem.lower() else "AWS_LZA_Intake"
        out = src.with_name(f"{slug}_{stem}.docx")
    else:
        out = src.with_suffix(".docx")

    build(md, out)
    print(f"✓ wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
