---
name: read
description: Fetch and analyze 3GPP specifications from ETSI to extract protocol header formats, field definitions, bit layouts, valid ranges, and dispatch keys. Use when implementing protocols defined by 3GPP (e.g., GTP, PFCP, NAS).
argument-hint: "[3GPP spec number, e.g. 29.281]"
allowed-tools: Read, Bash, Glob, Grep, WebFetch, WebSearch
---

Analyze 3GPP TS $0 and produce a structured summary for protocol dissector implementation.

## Prerequisites

This skill requires `pandoc` and `libreoffice` (for `.doc` → `.docx` conversion). Verify with:

```bash
pandoc --version
libreoffice --version
```

If not installed, stop and inform the user:

> Required tools are missing. Please install them:
> ```bash
> sudo apt-get install pandoc libreoffice-writer    # Debian/Ubuntu
> brew install pandoc && brew install --cask libreoffice  # macOS
> ```

## Workflow

### Step 1: Find and download the latest spec from 3GPP FTP

3GPP spec numbering: TS AB.CDE → series AB, spec number ABCDE (e.g., TS 29.281 → series 29, number 29281).

1. Browse the 3GPP FTP directory to find the latest version:
   ```bash
   curl -s "https://www.3gpp.org/ftp/Specs/archive/AB_series/AB.CDE/" | grep -oP 'href="[^"]*\.zip"' | sort -V | tail -5
   ```
   - Example for TS 29.281: `https://www.3gpp.org/ftp/Specs/archive/29_series/29.281/`
2. Download the latest zip file (highest version number):
   ```bash
   curl -L -o /tmp/3gpp_spec.zip "<URL_OF_LATEST_ZIP>"
   ```
3. Extract the spec file:
   ```bash
   unzip -o /tmp/3gpp_spec.zip -d /tmp/3gpp_spec_docx/
   ```

### Step 1.5: Convert `.doc` to `.docx` if needed

Some older 3GPP specs are distributed in `.doc` format (MS Word 97-2003), which pandoc cannot read directly. Check whether the extracted file is `.doc` and convert it to `.docx` using LibreOffice:

```bash
if ls /tmp/3gpp_spec_docx/*.doc 1>/dev/null 2>&1 && ! ls /tmp/3gpp_spec_docx/*.docx 1>/dev/null 2>&1; then
  libreoffice --headless --convert-to docx --outdir /tmp/3gpp_spec_docx/ /tmp/3gpp_spec_docx/*.doc
fi
```

The java warning (`failed to launch javaldx`) can be safely ignored.

### Step 2: Convert docx to Markdown with pandoc

Use the Lua filter in this skill's directory to preserve table structure (colspan/rowspan), which is critical for bit-level header format diagrams.

```bash
SKILL_DIR="$(dirname "$(find /home/user/packet-dissector/.claude/skills/3gpp-reader -name 'table-to-html.lua' -print -quit)")"
pandoc /tmp/3gpp_spec_docx/*.docx \
  -f docx \
  -t markdown \
  --lua-filter="$SKILL_DIR/table-to-html.lua" \
  -o /tmp/3gpp_spec.md
```

Read the converted Markdown using the `Read` tool.

**NOTE**: The Lua filter converts tables to raw HTML blocks, preserving `colspan` and `rowspan` attributes. This is essential for correctly interpreting bit-level header format diagrams where fields span multiple bit positions.

### Step 3: Analyze the specification

1. Locate message/header format sections (typically Chapter 5 for header format, Chapter 6-7 for message formats)
2. Extract header format and field definitions with byte/bit offsets from the HTML tables
   - Use `colspan` values to determine how many bit positions each field spans
   - Map bit positions from table column headers (8, 7, 6, 5, 4, 3, 2, 1)
3. Extract Information Elements (IEs) and their types
4. Identify mandatory vs optional fields
5. Identify the dispatch key for next layer

### Step 4: Clean up

```bash
rm -f /tmp/3gpp_spec.zip
rm -rf /tmp/3gpp_spec_docx/
rm -f /tmp/3gpp_spec.md
```

Every field MUST have a spec section citation. Temporary files MUST be cleaned up.
