---
name: read
description: Read and analyze RFC documents to extract protocol header formats, field definitions, bit layouts, valid ranges, and dispatch keys. Use when starting implementation of a new protocol or verifying an existing one against its RFC specification.
argument-hint: "[RFC number, e.g. 791]"
allowed-tools: Read, Bash, Glob, Grep, WebFetch, WebSearch
---

Analyze RFC $0 and produce a structured summary for protocol dissector implementation.

## Workflow

### Step 1: Check for RFC updates

1. Use `WebFetch` to retrieve `https://www.rfc-editor.org/info/rfc$0`
2. Look for **"Updated by"** and **"Obsoleted by"** fields
3. If an obsoleting RFC exists, analyze that RFC instead
4. If updating RFCs exist, also fetch their txt versions in Step 2

### Step 2: Download all relevant RFC texts to local cache

**IMPORTANT: Always use the plain-text version.** The txt version preserves ASCII art header format diagrams exactly, which is critical for accurate bit-level field extraction. Do NOT use the HTML version.

Cache location: `~/.cache/rfc-reader/rfc<N>.txt`. RFCs are immutable once published, so an existing cached file is always reusable — no re-download needed.

For each RFC to analyze (base RFC plus every updating RFC from Step 1), run:

```bash
mkdir -p ~/.cache/rfc-reader
[ -s ~/.cache/rfc-reader/rfc<N>.txt ] || curl -fsSL "https://www.rfc-editor.org/rfc/rfc<N>.txt" -o ~/.cache/rfc-reader/rfc<N>.txt
```

(Replace `<N>` with the RFC number. The `-s` test skips the download when a non-empty cached copy already exists.)

### Step 3: Extract and analyze from the cached files

Read the cached txt files with the `Read` tool (with `offset`/`limit` to target specific sections) and use `Grep` to locate diagrams, sections, and field definitions. Do NOT re-fetch over the network in this step.

Analyze the base RFC **and all updating RFCs together** to produce a single unified field table:

1. Locate the header format diagram (ASCII art with bit positions) in the base RFC
2. For fields that have been redefined by updating RFCs, use the updated definition (e.g., RFC 791 "Type of Service" was replaced by RFC 2474 "DSCP" + RFC 3168 "ECN")
3. Extract every field: name, bit offset, bit width, byte offset, byte width
4. For each field: valid ranges, default values, reserved bits, behavioral notes
5. Identify the dispatch key (how this protocol indicates the next layer)
6. Identify error conditions: minimum header size, invalid values, truncation points

Every field MUST have an RFC section citation. When a field is redefined by an updating RFC, cite the updating RFC, not the original. Bit-level precision required.
