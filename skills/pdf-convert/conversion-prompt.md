# Page conversion rules

Convert the pages you were given to markdown. Follow these exactly.

## Your sources

**With a reference text**, its characters are already correct. Copy its wording
verbatim rather than re-transcribing prose from the image. Take from the images
only what the text layer loses:

- Flattened super- and subscripts: `O(N 3)` is $O(N^3)$, `meV A-1` is
  meV $\text{Å}^{-1}$.
- Math markup, absent entirely. Rebuild equations as LaTeX from the image.
- Reading order. Margin notes, headings and captions can arrive detached from
  where they belong; put them back.
- Table grids. Cells arrive as loose lines; rebuild the grid from the image,
  keeping every value exactly as extracted.

**With no reference text**, the images are the only source. Transcribe what
they say, taking care over anything small or faint: subscripts, footnotes,
digits in tables. Read through skew, speckle and the page curve near a spine;
none of that belongs in the output.

### An ambiguous symbol

Re-render that region from the PDF at 400 DPI. Your task prompt gives the
page's size in pixels at that resolution; the crop box is in those pixels, from
the top left.

```bash
$ pdftoppm -png -r 400 -f <page> -l <page> \
    -x <left> -y <top> -W <width> -H <height> <pdf> <out-prefix>
```

A band across the middle of a page that is 2789 by 3983: `-x 0 -y 1800 -W 2789
-H 400`.

**Do not crop the page image you were given.** It is 144 DPI, so enlarging it
magnifies pixels already too coarse to read: nothing gets clearer and you will
want to look again, at a minute a time. Check yourself — a crop as wide as the
image you were handed is a crop of that image, not a re-render.

**Re-render a given spot at most twice.** If a second look does not settle it, a
third will not either — the detail is not in the file. Widen the crop to catch
the surrounding context, or write `[?]` and carry on.

Re-render as many *different* places as the page needs; that is what the tool
is for. The waste is returning to the same glyph over and over.

## Always

- **Omit print artifacts:** page numbers, running headers and footers, repeated
  chapter titles, and the `<!-- page N -->` markers in the reference text.
- **Wrap every mathematical variable in `$...$`**, including single letters in
  prose. "the process $z$ is killed", "for all $T > t$", "at time $s$" — not
  "the process z is killed". Likewise `$t \leq s$` not "t ≤ s".
- Display maths goes in `$$...$$` on its own line, never inline with text.
- Reproduce every sentence. Never summarise, never drop content, never reorder
  (footnotes stay where they appear).
- Equation number spacing: `(82) \qquad f(x) = ...`

## LaTeX conventions

- **Double-bar norm ‖f‖ is `\|f\|`**, never `|f|`. A norm has two bars;
  reducing it to one changes it to absolute value. Keep subscripts: `\|f\|_F`.
- Single-bar `|x|` stays as it is.
- `\varepsilon` not `\epsilon`; `\mathscr{R}` for ℛ; `\bar{\gamma}` for γ̄.
- `\to`, `\leq`, `\in`, `\infty` rather than `->`, `<=`, `in`, `infinity`.
- Write a symbol as itself inside `\text{}`. Never `\unicode{...}` — it renders
  in a browser but is not a LaTeX macro, so it breaks conversion to PDF.

## Figures

The images are not kept, so a figure survives only as what you write. Never
emit a markdown image link.

Put a description where the figure was, as a blockquote opening
`*Figure N described:*`, and keep the author's caption as ordinary text outside
the blockquote so nothing of yours can be mistaken for theirs.

- Plots: axis labels with units, each axis range, every series and what
  distinguishes it, the shape of each curve, and the values a reader would
  quote — crossings, plateaus, maxima, final values.
- Schematics: every labelled part and how they connect, in reading order.
- Images of text, such as screenshots or boxed equations: transcribe it.
- Photographs and decoration: one sentence.
- Describe only what is visible. Never state a result the figure does not show.

## Tables

Rebuild as markdown tables with `|` and a `---` header row. Preserve every
column header, including multi-level ones. For merged cells, repeat the
spanning value or add a note below. Split a too-wide table into several sharing
a header.

**Cell values matter more than formatting.** A two-column page layout is not a
table — treat each column as sequential prose.

## Page breaks

A page break is not a break in the text. Where a sentence, paragraph, table or
list runs from one page to the next, join it up, even when a figure, caption or
page number sits between the halves. Put the figure description after the
mended sentence, not through the middle of it.

**Your pages are part of a longer document.** The first may open mid-sentence
and the last may stop mid-sentence, because batch boundaries fall where they
fall. Transcribe your portion as it stands: invent no opening or ending to make
it read whole, and discard no fragment for looking incomplete. The halves are
joined once every batch is in, which only works if both survive.

## Output

Write the markdown to the file you were given and put nothing else in it — no
code fences around the whole document, no wrapper tags like `<output>` or
`<content>`. It is concatenated with the other batches exactly as you leave it.

**Write the whole file in one operation.** Compose all your pages, then write
once. Building it up page by page, or going back to edit what you already
wrote, re-sends the entire conversation each time and is most of what a batch
costs.

Do not write a summary of what you changed.
