#!/usr/bin/env python3
# Copyright (C) 2026 Wachirawich Kripindakul.
# SPDX-License-Identifier: AGPL-3.0-or-later. See ../LICENSE.
"""Render the repository's Markdown notices as static, readable website pages.

Run from any directory: python3 /path/to/website/scripts/render-docs.py
Uses only Python's standard library. Edit the Markdown originals, then rerun.
The small escaped renderer supports this project's headings, paragraphs, lists,
links, code spans, bold text, and pipe tables; it never passes through raw HTML.
"""

from html import escape
from pathlib import Path
import re
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
PAGES = [
    ('PROJECT-STATUS.md', 'project-status.html', 'Project status',
     'Current LunaV implementation, recorded validation results, and their limits. สถานะและขอบเขตการทดสอบโครงการ LunaV'),
    ('COMMERCIAL-LICENSE.md', 'licensing.html', 'Commercial licensing',
     'LunaV AGPL-3.0-or-later licensing and enquiries about an optional separate commercial agreement.'),
    ('ASSET-CREDITS.md', 'credits.html', 'Asset credits',
     'Sources and licence credits for LunaV lunar imagery, Simulator screenshots, and self-hosted fonts.'),
]
LINK_MAP = {source: target for source, target, _, _ in PAGES}
TOKEN = re.compile(r'(`[^`\n]+`|\*\*.+?\*\*|\[[^\]\n]+\]\([^\s)]+\)|<https?://[^>\n]+>)')


def safe_url(value):
    """Allow ordinary web, anchor and relative links, never script protocols."""
    value = LINK_MAP.get(value, value)
    scheme = urlsplit(value).scheme.lower()
    if scheme not in ('', 'http', 'https', 'mailto'):
        return '#'
    return escape(value, quote=True)


def inline(text):
    pieces = []
    position = 0
    for match in TOKEN.finditer(text):
        pieces.append(escape(text[position:match.start()]))
        token = match.group()
        if token.startswith('`'):
            rendered = '<code>' + escape(token[1:-1]) + '</code>'
        elif token.startswith('**'):
            rendered = '<strong>' + inline(token[2:-2]) + '</strong>'
        elif token.startswith('['):
            label, href = token[1:].split('](', 1)
            rendered = '<a href="' + safe_url(href[:-1]) + '">' + inline(label) + '</a>'
        else:
            href = token[1:-1]
            rendered = '<a href="' + safe_url(href) + '">' + escape(href) + '</a>'
        pieces.append(rendered)
        position = match.end()
    pieces.append(escape(text[position:]))
    return ''.join(pieces)


def language(text):
    return ' lang="th"' if re.search(r'[\u0E00-\u0E7F]', text) else ''


def table_cells(line):
    return [cell.strip() for cell in line.strip().strip('|').split('|')]


def render_markdown(source):
    lines = source.splitlines()
    output = []
    index = 0
    current_heading = 'Document'
    while index < len(lines):
        line = lines[index].strip()
        if not line:
            index += 1
            continue
        heading = re.match(r'^(#{1,3})\s+(.+)$', line)
        if heading:
            level, text = len(heading[1]), heading[2]
            current_heading = text
            output.append(f'<h{level}{language(text)}>{inline(text)}</h{level}>')
            index += 1
            continue
        if line.startswith('|') and index + 1 < len(lines) and re.match(r'^\s*\|[\s:|\-]+\|\s*$', lines[index + 1]):
            headers = table_cells(line)
            output.append('<div class="document-table" role="region" tabindex="0" aria-label="' + escape(current_heading + ' table', quote=True) + '"><table><thead><tr>')
            output.extend('<th scope="col">' + inline(cell) + '</th>' for cell in headers)
            output.append('</tr></thead><tbody>')
            index += 2
            while index < len(lines) and lines[index].strip().startswith('|'):
                output.append('<tr>')
                output.extend('<td>' + inline(cell) + '</td>' for cell in table_cells(lines[index]))
                output.append('</tr>')
                index += 1
            output.append('</tbody></table></div>')
            continue
        if line.startswith('- '):
            output.append('<ul>')
            while index < len(lines) and lines[index].strip().startswith('- '):
                item = lines[index].strip()[2:]
                index += 1
                while index < len(lines) and lines[index].startswith('  ') and not lines[index].strip().startswith('- '):
                    item += ' ' + lines[index].strip()
                    index += 1
                output.append('<li' + language(item) + '>' + inline(item) + '</li>')
            output.append('</ul>')
            continue
        paragraph = line
        index += 1
        while index < len(lines) and lines[index].strip() and not re.match(r'^(#{1,3}\s|\||- )', lines[index].strip()):
            paragraph += ' ' + lines[index].strip()
            index += 1
        output.append('<p' + language(paragraph) + '>' + inline(paragraph) + '</p>')
    return '\n'.join(output)


def render_page(source, target, title, description):
    navigation = []
    for _, href, label, _ in PAGES:
        current = ' aria-current="page"' if href == target else ''
        navigation.append(f'<a href="{href}"{current}>{escape(label)}</a>')
    body = render_markdown((ROOT / source).read_text())
    return f'''<!doctype html>
<!-- Generated by scripts/render-docs.py from {source}. Edit the Markdown source. -->
<!-- Copyright (C) 2026 Wachirawich Kripindakul. SPDX-License-Identifier: AGPL-3.0-or-later. See LICENSE. -->
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="theme-color" content="#080f20">
  <meta name="description" content="{escape(description, quote=True)}">
  <meta property="og:type" content="website">
  <meta property="og:title" content="{escape(title, quote=True)} — LunaV">
  <meta property="og:description" content="{escape(description, quote=True)}">
  <meta property="og:url" content="https://visionassistant.koomean.com/{target}">
  <link rel="canonical" href="https://visionassistant.koomean.com/{target}">
  <link rel="icon" href="assets/favicon.svg" type="image/svg+xml">
  <link rel="preload" href="assets/fonts/manrope.woff2" as="font" type="font/woff2" crossorigin>
  <link rel="preload" href="assets/fonts/noto-sans-thai.woff2" as="font" type="font/woff2" crossorigin>
  <link rel="stylesheet" href="styles.css?v=luna-20261021">
  <link rel="stylesheet" href="docs.css?v=luna-20261021">
  <title>{escape(title)} — LunaV</title>
</head>
<body class="document-page">
  <a href="#main" class="skip-link">Skip to content</a>
  <header class="document-header">
    <div class="wrap document-header-inner">
      <a class="brand" href="./" aria-label="LunaV home"><img class="document-brand-icon" src="assets/favicon.svg" width="34" height="34" alt=""><span>LunaV<span class="brand-dot">.</span></span></a>
      <nav aria-label="Project documents">{''.join(navigation)}</nav>
    </div>
  </header>
  <main id="main" class="wrap document-main">
    <a class="document-back" href="./"><span aria-hidden="true">←</span> Back to LunaV <span lang="th">/ กลับหน้าหลัก</span></a>
    <article class="document" aria-label="{escape(title, quote=True)}">
{body}
    </article>
    <div class="document-source"><a href="{source}">Read the original Markdown</a><span aria-hidden="true">·</span><a href="https://github.com/koomean/visionassistant/blob/main/{source}">View document source on GitHub</a></div>
  </main>
  <footer class="document-footer">
    <div class="wrap document-footer-inner">
      <p>© 2026 Wachirawich Kripindakul</p>
      <nav aria-label="Footer"><a href="https://github.com/koomean/visionassistant">Website source</a><a href="LICENSE">AGPL-3.0-or-later</a><a href="project-status.html">Project status</a><a href="licensing.html">Licensing</a><a href="credits.html">Credits</a></nav>
    </div>
  </footer>
</body>
</html>
'''


def main():
    for source, target, title, description in PAGES:
        (ROOT / target).write_text(render_page(source, target, title, description))
        print(f'{source} -> {target}')


if __name__ == '__main__':
    main()
