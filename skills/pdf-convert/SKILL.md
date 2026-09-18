Convert a scanned or digital PDF into clean, structured markdown.

## When to use

The user has a PDF — a scanned book, an academic paper, anything with maths,
tables or figures — and wants a faithful text version.

The method: read the PDF's own text layer where it is exact, send a page image
only where it is not, split the pages across subagents, then check the result
against the text layer.

## Requirements

Poppler supplies every PDF operation; nothing else is needed but Claude.

```bash
$ command -v pdfinfo pdftotext pdffonts pdfimages pdftoppm
```

If any are missing, install poppler as this machine does — `poppler-utils` on
Debian, Ubuntu and nixpkgs, `poppler` on Homebrew, Arch and Alpine. Everything
else is POSIX shell, with no GNU-only flags, so it runs on macOS and BSD too.
Keep it that way.

## 1. Decide where the output goes

There is no configured directory and no default. Choose from what the
conversion is for:

- Beside the source PDF for a paper being read or cited. Figures are not
  carried into the markdown, so the PDF stays the only copy of them.
- Inside a project, for something feeding other work.
- Wherever the user named.
- Ask, if it is not obvious. One question beats moving files later.

Never invent a library directory, and never move or copy the source PDF.

Ask about a page range on a large document (100+ pages); the user may want one
section. Export `FIRST` and `LAST` to the script below to convert a range.

## 2. Prepare

```bash
$ bash <skill_dir>/prepare.sh <pdf> <output-dir> [pages-per-batch]
```

Eight pages per batch for a born-digital PDF, three for a scan. On a long
document it renders for a while — do not pipe it through `head`, which kills it
with SIGPIPE partway.

It prints what everything below needs, so keep its output:

- `PDF`, `OUT`, `WORK` — paths to paste into prompts
- `pages … scanned … imaged` — how it read the document. **Nearly all pages
  scanned means a scan**; a handful means a typeset document with plates.
- `zoom … pixels at 400 DPI` — subagents need this to re-render a doubtful
  region rather than enlarging a page image, which cannot work
- `ROTATED page …` — look at that page's image before sending it
- `batches …` and a per-batch block giving each batch's reference text, its page
  images, and the pages it has none for

It decides scan-or-typeset per page, selects the pages worth an image, renders
them at 144 DPI, and writes per-batch reference text — leaving a marked gap
where a page is scanned, since an OCR layer is worse than none. Re-run it
freely; it takes seconds and rewrites everything identically.

**Shell variables do not survive between tool calls**, which is why this is one
script and why what follows reads paths from files rather than variables.

## 3. Convert the batches in parallel

One subagent per batch, all spawned in a single message, on **sonnet**. Each
must **write its markdown to a file and reply with only the path** — if batch
markdown comes back through your context you pay for the document twice and the
parallelism buys nothing.

```
Convert pages <start>-<end> of a PDF into markdown.

First read the conversion rules and follow them exactly:
<skill_dir>/conversion-prompt.md

Reference text (the PDF's own text layer; its characters are already exact):
<WORK>/text_<start>-<end>.md

Page images — read these all together in one step:
<the "- page N:" lines for this batch>

Pages <the "no image" list> have no image because they are running prose with
no equations or tables. Use their reference text as it stands.

Source PDF, if you need to re-render part of a page larger to settle an
ambiguous symbol: <PDF>
At 400 DPI a page of this PDF is <zoom> pixels; the crop box is in those.

Write the finished markdown for all <n> pages to <WORK>/md_<start>-<end>.md
Reply with only that path and nothing else.
```

For an all-scan document, drop the reference-text line and say the images are
the only source.

**Spawn a batch only if its output is missing**, so an interrupted run resumes
rather than paying twice:

```bash
$ while read -r r; do
    [ -s "$WORK/md_$r.md" ] || echo "$r still to do"
  done < "$WORK/batches.txt"
```

Preparation costs seconds and rebuilds `batches.txt` identically, so resuming
in a later session is free — only the `md_` files are paid work. Re-run one bad
batch by deleting its file and spawning it alone. Never hand-edit the markdown.

## 4. Assemble

```bash
$ : > "$OUT/$NAME.md"
$ while read -r r; do
    cat "$WORK/md_$r.md" >> "$OUT/$NAME.md"
  done < "$WORK/batches.txt"
```

## 5. Mend the seams

Subagents never see each other's pages, so the joins carry this design's own
defects — and step 6 cannot see them, because nothing is missing.

```bash
$ grep -n -e '</\?output>' -e '</\?content>' -e '^```$' "$OUT/$NAME.md"
```

Delete any leaked framing. Then read each join, the last page of one batch
against the first page of the next, and fix only:

- **A sentence split across the break**, often with a figure between the halves.
  Join it and move the figure description after the mended sentence.
- **A table or list broken into two unrelated fragments.**
- **Heading level drift** between batches.
- **Notation that changed hands** — `\mathbf{w}` in one batch, `\vec{w}` in the
  next.

Do not have a subagent rewrite the whole document to repair a few joins. Re-run
step 6 afterwards; coverage should not move.

## 6. Verify

Two checks against the PDF's own text layer. This is what catches a dropped
table cell that reads perfectly well in isolation.

```bash
$ export LC_ALL=C
$ pdftotext "$PDF" - | grep -oE '[0-9]+\.[0-9]+|[0-9]{2,}' | sort -u > "$WORK/pdfnums"
$ grep -oE '[0-9]+\.[0-9]+|[0-9]{2,}' "$OUT/$NAME.md" | sort -u > "$WORK/mdnums"
$ comm -23 "$WORK/pdfnums" "$WORK/mdnums"
```

```bash
$ norm() { tr '\n' '\001' | sed 's/-[ \t]*\001[ \t]*//g' | tr '\001' '\n' |
           tr 'A-Z$' 'a-z ' | grep -oE '[a-z0-9]+'; }
$ pdftotext "$PDF" - | norm > "$WORK/want"
$ norm < "$OUT/$NAME.md" | sort -u > "$WORK/have"
$ awk -v RUN=6 '
    NR==FNR { have[$0]=1; next }
    { want[++n]=$0; ok=($0 in have); hits+=ok
      if (!ok) { if (!start) start=n }
      else if (start) {
        if (n-start >= RUN) { s=""; for(i=start;i<n;i++) s=s want[i]" "
                              print "RUN: " substr(s,1,90) }
        start=0 } }
    END { if (start && n+1-start >= RUN) { s=""; for(i=start;i<=n;i++) s=s want[i]" "
                                           print "RUN: " substr(s,1,90) }
          printf "coverage: %.1f%%\n", 100*hits/n }
  ' "$WORK/have" "$WORK/want"
```

Expect about 99%; below 97% needs explaining. **Read the runs, not the
percentage.** A long run is dropped content. Scattered single words are usually
correct: stripped headers, figure labels turned into prose, or maths — the text
layer flattens `$z_j$` to `zj`, which never matches, so a math-dense appendix
scores in the low 90s for that reason alone. Missing numbers like `1010` are
`10^{10}` flattened the same way.

**Neither check applies to a scan.** Its OCR layer is guesswork, so a
disagreement identifies nothing and a real error matching the OCR gets blessed.
Spot-read against the page images instead — Greek letters, script capitals, sub-
and superscripts, digits in tables. **If another conversion of the same document
exists, diff against it**: two readings disagree where the source is hard to
read, which is the strongest check available on a scan. Settle each
disagreement against the page at 400 DPI, not by preferring a version.

## 7. Report

Say where the file is. Read the first few pages and flag maths not wrapped in
`$...$`, leftover page numbers or running headers, and any figure caption left
without a `> *Figure N described:*` blockquote — a caption alone is a defect.

The images are deliberately absent; do not try to restore them. The description
carries the diagram, so check it against the PDF if the user doubts it.
