# lorevis — Lore repository data, rendered with ratatui

Five panels, rendered headlessly and exported as SVG. **Every figure is real**: parsed from a
`lore repository dump` (`dump.txt`) or measured on a live install and recorded in
`docs/DEBUGGING.md`. Nothing is illustrative.

```bash
cargo build --release
for i in 1 2 3 4 5; do ./target/release/lorevis $i > $i.svg; done
```

| # | Panel | ratatui widgets | What it shows |
| --- | --- | --- | --- |
| 01 | deduplication | `Gauge`, `List`, `Canvas` + `Braille` | one object, three references; 7.6 MiB of 31.4 MiB never stored twice |
| 02 | commit cost | `BarChart` (`NINE_LEVELS`), `Paragraph` | 31.4 MiB, then 144 KiB twice, on one linear scale |
| 03 | repository tree | `List`, inline bars | size encoded twice: bar length and viridis lightness |
| 04 | media formats | `BarChart`, Okabe-Ito | the 15-file media corpus by format |
| 05 | integrity, shards | `Gauge`, `BarChart` | verify result, and objects per store shard |

## How it renders without a terminal

ratatui is a full-screen interactive framework and will not emit a static block. `TestBackend`
draws into an in-memory `Buffer`; `to_svg` then walks the cells and emits a monospace SVG grid,
one rect per non-default background and one text run per contiguous style. That gives exact colour
and crisp output at any scale.

## Colour

Published scientific palettes only. **viridis** for anything ordered (perceptually uniform,
monotonic in lightness, so it survives greyscale and common colour-vision deficiencies) and
**Okabe-Ito** for categories (CVD-safe, eight classes). Colour is always the redundant channel:
position and length carry the data.

## Caveats, stated plainly

This parses `lore repository dump`, whose format **upstream has never promised to keep stable**, and
there is no machine-readable output anywhere in Lore to use instead. Exercised against one dump on
Lore 0.8.6. A demonstration, not dependable tooling.

Panel 04 deliberately excludes `raw/`, `dedup/` and `incremental/`: those are synthetic payloads
generated to exercise chunking, and including them shows `.bin` dominating, which misrepresents the
corpus.
