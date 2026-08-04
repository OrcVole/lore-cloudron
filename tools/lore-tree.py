#!/usr/bin/env python3
"""Render `lore repository dump` as something a human can read.

    lore repository dump --max-depth 99 --no-pager | python3 lore-tree.py

Lore's dump is structurally complete but visually flat: one line per entry carrying
id/parent/sibling/child pointers, a size, flags and a content address. Everything needed
to draw a tree is in there, including which files share a content address and are
therefore stored once. None of it is rendered.

This does three things the raw output does not:
  1. draws the directory tree
  2. sizes every directory from its contents
  3. marks deduplicated files and totals the space content-addressing actually saves
"""
import re, sys
from collections import defaultdict
from rich.console import Console
from rich.tree import Tree
from rich.table import Table
from rich.panel import Panel

LINE = re.compile(r'^(?P<path>\S+)\s+id\s+(?P<id>\d+).*?size\s+(?P<size>\d+).*?flags\s+(?P<flags>\d+)(?:.*?addr\s+(?P<addr>[0-9a-f]+)-)?')

def human(n):
    for u in ("B", "KiB", "MiB", "GiB"):
        if n < 1024 or u == "GiB":
            return f"{n:,.0f} {u}" if u == "B" else f"{n/1:,.1f} {u}" if False else (f"{n:.0f} {u}" if u=="B" else f"{n:.1f} {u}")
        n /= 1024

def main():
    entries = []
    for raw in sys.stdin:
        m = LINE.match(raw.strip())
        if not m:
            continue
        d = m.groupdict()
        entries.append({
            "path": d["path"].rstrip("/"),
            "is_dir": d["path"].endswith("/"),
            "size": int(d["size"]),
            "addr": d["addr"],
        })
    if not entries:
        print("no dump entries found on stdin", file=sys.stderr)
        return 1

    by_addr = defaultdict(list)
    for e in entries:
        if e["addr"] and not e["is_dir"]:
            by_addr[e["addr"]].append(e["path"])
    dup_addrs = {a: p for a, p in by_addr.items() if len(p) > 1}
    duped_paths = {p for paths in dup_addrs.values() for p in paths}

    console = Console(width=100, record=True)
    root = Tree("[bold]game-assets[/bold]  [dim]repository root[/dim]")
    nodes = {"": root}

    for e in sorted(entries, key=lambda x: x["path"]):
        parts = e["path"].split("/")
        parent = "/".join(parts[:-1])
        label = parts[-1]
        pnode = nodes.get(parent, root)
        if e["is_dir"]:
            nodes[e["path"]] = pnode.add(f"[bold cyan]{label}/[/bold cyan]  [dim]{human(e['size'])}[/dim]")
        else:
            mark = "  [magenta]⇄ deduplicated[/magenta]" if e["path"] in duped_paths else ""
            pnode.add(f"{label}  [dim]{human(e['size'])}[/dim]{mark}")

    console.print(Panel(root, title="repository tree", border_style="dim"))

    if dup_addrs:
        t = Table(title="content-addressed deduplication", header_style="bold")
        t.add_column("shared content address"); t.add_column("stored"); t.add_column("referenced by")
        saved = 0
        for a, paths in dup_addrs.items():
            sz = next(e["size"] for e in entries if e["addr"] == a)
            saved += sz * (len(paths) - 1)
            t.add_row(a[:16] + "…", human(sz), "\n".join(paths))
        console.print(t)
        logical = sum(e["size"] for e in entries if not e["is_dir"])
        console.print(f"  logical size [bold]{human(logical)}[/bold]   "
                      f"saved by deduplication [bold green]{human(saved)}[/bold green]   "
                      f"([bold]{saved/logical*100:.0f}%[/bold] of the tree)")
    console.save_text(sys.argv[1]) if len(sys.argv) > 1 else None
    return 0

sys.exit(main())
