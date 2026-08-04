# tools

Small viewers for a Lore repository. Neither is required to run the package; both exist
because Lore's own output is structurally complete but visually flat.

## `lore-tree.py`

Renders `lore repository dump` as a tree with directory sizes, and marks files that share
a content address and are therefore stored once.

```bash
lore repository dump --max-depth 99 --no-pager | python3 tools/lore-tree.py
```

## `rich-showcase.py`

Composes the same data into a single "repository at a glance" view and exports it as SVG.

```bash
python3 tools/rich-showcase.py tools/sample-dump.txt out.svg
```

`sample-dump.txt` is a captured dump so both can be developed without a running server.

## Caveats, stated plainly

Both parse `lore repository dump` with a regular expression, and **upstream has never
promised that output format is stable**. They have been exercised against one dump, from
one repository, on Lore 0.8.6. Treat them as demonstrations rather than as tooling you
should depend on. They require `rich` (`pip install rich`) and nothing else.
