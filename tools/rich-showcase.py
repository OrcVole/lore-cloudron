#!/usr/bin/env python3
"""Compose a single 'repository at a glance' view for the Cloudron forum post.

    python3 rich-showcase.py sample-dump.txt out.svg

Every number here is measured, not illustrative:
  - tree, sizes and shared content addresses are parsed from `lore repository dump`
  - the incremental figures are server-side store growth measured on the live install
    (docs/DEBUGGING.md, gate 2): a one-byte edit in an 8 MB file cost 144 KiB

The caption is rendered INSIDE the image on purpose. This is our viewer, not Lore's UI;
Lore ships no TUI and no web interface. Images get reposted without their surrounding
text, so the disclaimer has to travel with the pixels.
"""
import re, sys
from collections import defaultdict
from rich.console import Console, Group
from rich.tree import Tree
from rich.table import Table
from rich.panel import Panel
from rich.columns import Columns
from rich.text import Text
from rich import box

LINE = re.compile(r'^(?P<path>\S+)\s+id\s+\d+.*?size\s+(?P<size>\d+).*?flags\s+\d+(?:.*?addr\s+(?P<addr>[0-9a-f]+)-)?')

def human(n):
    for u in ("B", "KiB", "MiB", "GiB"):
        if n < 1024 or u == "GiB":
            return f"{n:.0f} {u}" if u == "B" else f"{n:.1f} {u}"
        n /= 1024

def bar(frac, width=28, style="cyan"):
    filled = max(1, int(round(frac * width)))
    return Text("█" * filled, style=style) + Text("░" * (width - filled), style="grey30")

src, out = sys.argv[1], sys.argv[2]
entries = []
for raw in open(src):
    m = LINE.match(raw.strip())
    if m:
        d = m.groupdict()
        entries.append({"path": d["path"].rstrip("/"), "is_dir": d["path"].endswith("/"),
                        "size": int(d["size"]), "addr": d["addr"]})

by_addr = defaultdict(list)
for e in entries:
    if e["addr"] and not e["is_dir"]:
        by_addr[e["addr"]].append(e["path"])
dups = {a: p for a, p in by_addr.items() if len(p) > 1}
duped = {p for v in dups.values() for p in v}

# ---- tree ----
tree = Tree("[bold white]game-assets[/]", guide_style="grey35")
nodes = {"": tree}
for e in sorted(entries, key=lambda x: x["path"]):
    parts = e["path"].split("/"); parent = "/".join(parts[:-1]); label = parts[-1]
    p = nodes.get(parent, tree)
    if e["is_dir"]:
        nodes[e["path"]] = p.add(f"[bold cyan]{label}/[/]  [grey50]{human(e['size'])}[/]")
    else:
        tag = "  [magenta]⇄ shared[/]" if e["path"] in duped else ""
        p.add(f"[white]{label}[/]  [grey50]{human(e['size'])}[/]{tag}")

logical = sum(e["size"] for e in entries if not e["is_dir"])
saved = sum(next(e["size"] for e in entries if e["addr"] == a) * (len(v) - 1) for a, v in dups.items())

# ---- dedup ----
dt = Table(box=box.SIMPLE_HEAD, header_style="bold magenta", pad_edge=False)
dt.add_column("shared address"); dt.add_column("stored once", justify="right"); dt.add_column("referenced by")
for a, paths in dups.items():
    sz = next(e["size"] for e in entries if e["addr"] == a)
    dt.add_row(f"[grey62]{a[:14]}…[/]", human(sz), "\n".join(f"[white]{p}[/]" for p in paths))

dedup_body = Group(dt, Text(""),
    Text.assemble(("  deduplicated  ", "bold"), bar(saved / logical, 18, "magenta"),
                  (f"  {saved/logical*100:.0f}%  ", "bold magenta"),
                  (f"{human(saved)} saved", "grey62")))

# ---- incremental, the headline ----
revs = [("r1  import, 23 assets", 31.44 * 1024, "cyan"),
        ("r2  1 byte in an 8 MB file", 144, "green"),
        ("r3  1 byte again", 144, "green")]
top = max(v for _, v, _ in revs)
it = Table.grid(padding=(0, 1), expand=False)
it.add_column(no_wrap=True); it.add_column(no_wrap=True); it.add_column(justify="right", no_wrap=True)
for label, kib, col in revs:
    it.add_row(Text(label, style="white"), bar(kib / top, 18, col), Text(human(kib * 1024), style=f"bold {col}"))
inc_body = Group(it, Text(""),
    Text("  content-defined chunking: 144 KiB, not 8 MB", style="grey62"))

console = Console(record=True, width=132)
console.print(Panel(Text.assemble(
    ("Lore Server", "bold white"), ("   \u00b7   version control for very large binary assets", "grey70"),
    ("   ·   packaged for Cloudron", "cyan")), box=box.HEAVY, border_style="grey35", padding=(0, 2)))
console.print(Columns([
    Panel(tree, title="[bold]repository[/]", border_style="grey35", box=box.ROUNDED, width=56),
    Group(Panel(inc_body, title="[bold]what a commit actually costs[/]", border_style="grey35", box=box.ROUNDED, width=70),
          Panel(dedup_body, title="[bold]content-addressed storage[/]", border_style="grey35", box=box.ROUNDED, width=70)),
], padding=(0, 1)))
console.print(Text("  Rendered by lore-tree, a viewer in the Cloudron package repo. Lore itself ships no TUI "
                   "and no web interface; all figures measured on a live install.", style="italic grey50"))
console.save_svg(out, title="lore repository dump  —  visualised")
print(f"wrote {out}")
