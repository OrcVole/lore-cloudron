//! Renders Lore repository data with ratatui, to SVG, via TestBackend.
//!
//! Every figure is parsed from a real `lore repository dump` (dump.txt) or is a
//! measurement recorded in docs/DEBUGGING.md. Nothing is invented.
//!
//! Palettes are published scientific maps: viridis (sequential, perceptually
//! uniform) and Okabe-Ito (categorical, CVD-safe). Colour is the redundant
//! channel; position and length carry the data.

use ratatui::backend::TestBackend;
use ratatui::buffer::Buffer;
use ratatui::layout::{Constraint, Direction, Layout};
use ratatui::style::{Color, Modifier, Style};
use ratatui::symbols;
use ratatui::text::{Line, Span};
use ratatui::widgets::canvas::{Canvas, Points};
use ratatui::widgets::{Bar, BarChart, BarGroup, Block, BorderType, Gauge, List, ListItem, Paragraph};
use ratatui::Terminal;
use std::collections::BTreeMap;
use std::fmt::Write as _;

const VIRIDIS: [(u8, u8, u8); 6] = [
    (0x44, 0x01, 0x54), (0x41, 0x44, 0x87), (0x2A, 0x78, 0x8E),
    (0x22, 0xA8, 0x84), (0x7A, 0xD1, 0x51), (0xFD, 0xE7, 0x25),
];
const OKABE: [(u8, u8, u8); 8] = [
    (0xE6, 0x9F, 0x00), (0x56, 0xB4, 0xE9), (0x00, 0x9E, 0x73), (0xF0, 0xE4, 0x42),
    (0x00, 0x72, 0xB2), (0xD5, 0x5E, 0x00), (0xCC, 0x79, 0xA7), (0x99, 0x99, 0x99),
];
fn vir(t: f64) -> Color {
    let t = t.clamp(0.0, 1.0) * 5.0;
    let i = t.floor() as usize;
    let (a, b) = (VIRIDIS[i.min(5)], VIRIDIS[(i + 1).min(5)]);
    let f = t - i as f64;
    Color::Rgb(
        (a.0 as f64 + (b.0 as f64 - a.0 as f64) * f) as u8,
        (a.1 as f64 + (b.1 as f64 - a.1 as f64) * f) as u8,
        (a.2 as f64 + (b.2 as f64 - a.2 as f64) * f) as u8,
    )
}
fn oka(i: usize) -> Color { let c = OKABE[i % 8]; Color::Rgb(c.0, c.1, c.2) }
const DIM: Color = Color::Rgb(0x6F, 0x78, 0x85);
const RULE: Color = Color::Rgb(0x2A, 0x31, 0x3A);
const TEXT: Color = Color::Rgb(0xE4, 0xE8, 0xED);

const CW: f32 = 8.4;
const CH: f32 = 18.0;
const BG: &str = "#0E1116";
const FG: &str = "#E4E8ED";

fn hex(c: Color, d: &str) -> String {
    match c { Color::Rgb(r, g, b) => format!("#{r:02X}{g:02X}{b:02X}"), _ => d.into() }
}
fn esc(s: &str) -> String { s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;") }

fn to_svg(buf: &Buffer, caption: &str) -> String {
    let (w, h) = (buf.area.width, buf.area.height);
    let (pw, ph) = (w as f32 * CW + 24.0, h as f32 * CH + 52.0);
    let mut s = String::new();
    let _ = write!(s, r#"<svg xmlns="http://www.w3.org/2000/svg" width="{pw:.0}" height="{ph:.0}" viewBox="0 0 {pw:.0} {ph:.0}">"#);
    let _ = write!(s, r#"<rect width="{pw:.0}" height="{ph:.0}" rx="8" fill="{BG}"/>"#);
    let _ = write!(s, r#"<g font-family="ui-monospace,DejaVu Sans Mono,monospace" font-size="13.5">"#);
    for y in 0..h {
        for x in 0..w {
            let c = &buf[(x, y)];
            let b = hex(c.bg, BG);
            if b != BG {
                let _ = write!(s, r#"<rect x="{:.1}" y="{:.1}" width="{:.1}" height="{:.1}" fill="{b}"/>"#,
                    12.0 + x as f32 * CW, 14.0 + y as f32 * CH, CW + 0.6, CH);
            }
        }
        let mut x = 0u16;
        while x < w {
            if buf[(x, y)].symbol().trim().is_empty() { x += 1; continue; }
            let col = hex(buf[(x, y)].fg, FG);
            let bold = buf[(x, y)].modifier.contains(Modifier::BOLD);
            let (sx, mut run) = (x, String::new());
            while x < w {
                let d = &buf[(x, y)];
                if hex(d.fg, FG) != col || d.symbol().trim().is_empty()
                    || d.modifier.contains(Modifier::BOLD) != bold { break; }
                run.push_str(d.symbol()); x += 1;
            }
            let _ = write!(s, r#"<text x="{:.1}" y="{:.1}" fill="{col}"{}>{}</text>"#,
                12.0 + sx as f32 * CW, 14.0 + y as f32 * CH + CH * 0.74,
                if bold { r#" font-weight="600""# } else { "" }, esc(&run));
        }
    }
    let _ = write!(s, r##"<text x="12" y="{:.0}" font-size="11" fill="#5A636E" font-style="italic">{}</text>"##,
        ph - 12.0, esc(caption));
    s.push_str("</g></svg>");
    s
}

#[derive(Clone)]
struct Entry { path: String, dir: bool, size: u64, addr: Option<String> }

fn load() -> Vec<Entry> {
    let raw = std::fs::read_to_string("dump.txt").expect("dump.txt next to the binary");
    let mut out = Vec::new();
    let mut on = false;
    for l in raw.lines() {
        if l.contains("repository dump") { on = true; continue; }
        if l.contains("lore history") { on = false; }
        if !on { continue; }
        let t = l.trim();
        let Some(p) = t.split_whitespace().next() else { continue };
        if !t.contains(" id ") || !t.contains(" size ") { continue; }
        let size = t.split(" size ").nth(1).and_then(|s| s.split_whitespace().next())
            .and_then(|s| s.parse().ok()).unwrap_or(0);
        let addr = t.split(" addr ").nth(1)
            .and_then(|s| s.split('-').next()).map(|s| s.trim().to_string());
        out.push(Entry { path: p.trim_end_matches('/').to_string(), dir: p.ends_with('/'), size, addr });
    }
    out
}

fn human(n: u64) -> String {
    let (mut v, mut u) = (n as f64, "B");
    for x in ["KiB", "MiB", "GiB"] { if v < 1024.0 { break } v /= 1024.0; u = x; }
    if u == "B" { format!("{n} B") } else { format!("{v:.1} {u}") }
}

fn frame(title: &str) -> Block<'static> {
    Block::bordered().border_type(BorderType::Rounded)
        .border_style(Style::new().fg(RULE))
        .title(Span::styled(format!(" {title} "), Style::new().fg(DIM)))
}

fn p01(f: &mut ratatui::Frame) {
    let e = load();
    let mut by: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for x in e.iter().filter(|x| !x.dir) {
        if let Some(a) = &x.addr { by.entry(a.clone()).or_default().push(x.path.clone()); }
    }
    let logical: u64 = e.iter().filter(|x| !x.dir).map(|x| x.size).sum();
    let saved: u64 = by.values().filter(|v| v.len() > 1)
        .map(|v| e.iter().find(|x| x.path == v[0]).map(|x| x.size).unwrap_or(0) * (v.len() as u64 - 1))
        .sum();

    let left = Layout::default().direction(Direction::Vertical)
        .constraints([Constraint::Length(3), Constraint::Length(7), Constraint::Min(0)]).split(f.area());
    let main = [left[0], left[2]];

    let g = Gauge::default().block(frame("deduplicated"))
        .ratio(saved as f64 / logical as f64)
        .label(format!("{} of {} never stored twice", human(saved), human(logical)))
        .gauge_style(Style::new().fg(vir(0.55)));
    f.render_widget(g, left[0]);

    let mut items: Vec<ListItem> = Vec::new();
    for (a, v) in by.iter().filter(|(_, v)| v.len() > 1) {
        let sz = e.iter().find(|x| x.path == v[0]).map(|x| x.size).unwrap_or(0);
        items.push(ListItem::new(Line::from(vec![
            Span::styled(format!(" {}… ", &a[..12]), Style::new().fg(vir(0.95))),
            Span::styled(format!("{:>9}", human(sz)), Style::new().fg(TEXT)),
        ])));
        items.push(ListItem::new(Span::styled(
            format!("   one object, {} references:", v.len()), Style::new().fg(DIM))));
        for p in v { items.push(ListItem::new(Span::styled(format!("     {p}"), Style::new().fg(vir(0.72))))); }
    }
    f.render_widget(List::new(items).block(frame("shared content addresses")), left[1]);

    // scatter: every stored object by size. Shared objects lit.
    let mut pts: Vec<(f64, f64)> = Vec::new();
    let mut shr: Vec<(f64, f64)> = Vec::new();
    let mut objs: Vec<(u64, bool)> = by.iter()
        .map(|(_, v)| (e.iter().find(|x| x.path == v[0]).map(|x| x.size).unwrap_or(0), v.len() > 1))
        .collect();
    objs.sort_by(|a, b| a.0.cmp(&b.0));
    for (i, (sz, sh)) in objs.iter().enumerate() {
        let y = ((*sz as f64).max(1.0)).log10();
        if *sh {
            let mut t = 0.0;
            while t <= y { shr.push((i as f64, t)); t += 0.12; }
        } else { pts.push((i as f64, y)); }
    }
    let n = objs.len() as f64;
    let cv = Canvas::default()
        .block(frame("every stored object, smallest to largest  ·  log10 bytes  ·  yellow = shared"))
        .marker(symbols::Marker::Braille)
        .x_bounds([-0.5, n]).y_bounds([0.0, 7.0])
        .paint(move |ctx| {
            ctx.draw(&Points { coords: &pts, color: vir(0.40) });
            ctx.draw(&Points { coords: &shr, color: vir(0.95) });
        });
    f.render_widget(cv, main[1]);
}

fn p02(f: &mut ratatui::Frame) {
    let data = [("r1  import, 23 assets", 32195u64), ("r2  one byte edited", 144), ("r3  one byte edited", 144)];
    let rows = Layout::default().direction(Direction::Vertical)
        .constraints([Constraint::Min(0), Constraint::Length(5)]).split(f.area());
    let bars: Vec<Bar> = data.iter().enumerate().map(|(i, (l, v))| {
        Bar::default().value(*v).label(Line::from(*l)).text_value(human(*v * 1024))
            .style(Style::new().fg(if i == 0 { vir(0.30) } else { vir(0.72) }))
    }).collect();
    let bc = BarChart::default()
        .block(frame("server-side store growth per revision  ·  linear, one scale"))
        .data(BarGroup::default().bars(&bars))
        .bar_width(21).bar_gap(3).bar_set(symbols::bar::NINE_LEVELS)
        .value_style(Style::new().fg(TEXT).add_modifier(Modifier::BOLD))
        .label_style(Style::new().fg(DIM));
    f.render_widget(bc, rows[0]);
    let note = Paragraph::new(vec![
        Line::from(Span::styled("  Revisions 2 and 3 are 0.4% of revision 1, so on one linear scale they vanish.", Style::new().fg(TEXT))),
        Line::from(Span::styled("  That is the finding, not a rendering fault: each changed a single byte in an 8 MB file.", Style::new().fg(DIM))),
        Line::from(Span::styled("  A whole-file re-store would have cost 7,812 KiB. Chunking made it 54 times cheaper.", Style::new().fg(DIM))),
    ]).block(frame("why the last two bars are almost invisible"));
    f.render_widget(note, rows[1]);
}

fn p03(f: &mut ratatui::Frame) {
    let mut e = load();
    e.sort_by(|a, b| a.path.cmp(&b.path));
    let max = e.iter().map(|x| x.size).max().unwrap_or(1) as f64;
    let mut cnt: BTreeMap<String, usize> = BTreeMap::new();
    for x in e.iter().filter(|x| !x.dir) {
        if let Some(a) = &x.addr { *cnt.entry(a.clone()).or_default() += 1; }
    }
    let items: Vec<ListItem> = e.iter().map(|x| {
        let depth = x.path.matches('/').count();
        let name = x.path.rsplit('/').next().unwrap_or(&x.path);
        let w = ((x.size as f64 / max) * 20.0).ceil().max(1.0) as usize;
        let dup = x.addr.as_ref().map(|a| cnt.get(a).copied().unwrap_or(1) > 1).unwrap_or(false);
        ListItem::new(Line::from(vec![
            Span::raw("  ".repeat(depth)),
            Span::styled(if x.dir { format!("{name}/") } else { name.to_string() },
                Style::new().fg(if x.dir { oka(1) } else { TEXT })),
            Span::raw(" ".repeat(26usize.saturating_sub(depth * 2 + name.len() + if x.dir {1} else {0}))),
            Span::styled(format!("{:>9}  ", human(x.size)), Style::new().fg(DIM)),
            Span::styled("▇".repeat(w), Style::new().fg(vir(x.size as f64 / max))),
            Span::styled(if dup { "  shared" } else { "" }, Style::new().fg(vir(0.95))),
        ]))
    }).collect();
    f.render_widget(List::new(items).block(frame("repository  ·  size encoded twice: bar length and viridis lightness")), f.area());
}

fn p04(f: &mut ratatui::Frame) {
    let e = load();
    let mut by: BTreeMap<String, u64> = BTreeMap::new();
    // Only the media directories. raw/, dedup/ and incremental/ hold synthetic
    // payloads generated to exercise chunking and deduplication; including them
    // would show .bin dominating and misrepresent the corpus as binary blobs.
    for x in e.iter().filter(|x| !x.dir)
        .filter(|x| x.path.starts_with("image/") || x.path.starts_with("video/") || x.path.starts_with("audio/")) {
        let ext = x.path.rsplit('.').next().unwrap_or("none").to_string();
        *by.entry(ext).or_default() += x.size;
    }
    let mut v: Vec<_> = by.into_iter().collect();
    v.sort_by(|a, b| b.1.cmp(&a.1));
    v.truncate(10);
    let bars: Vec<Bar> = v.iter().enumerate().map(|(i, (k, s))| {
        Bar::default().value(*s / 1024).label(Line::from(format!(".{k}")))
            .text_value(human(*s)).style(Style::new().fg(oka(i)))
    }).collect();
    let bc = BarChart::default()
        .block(frame("media corpus by format  ·  Okabe-Ito categorical, hue implies no ranking"))
        .data(BarGroup::default().bars(&bars))
        .bar_width(6).bar_gap(1).bar_set(symbols::bar::NINE_LEVELS)
        .value_style(Style::new().fg(TEXT)).label_style(Style::new().fg(DIM));
    f.render_widget(bc, f.area());
}

fn p05(f: &mut ratatui::Frame) {
    let e = load();
    let mut sh: BTreeMap<String, usize> = BTreeMap::new();
    for x in e.iter().filter(|x| !x.dir) {
        if let Some(a) = &x.addr { *sh.entry(a[..2].to_string()).or_default() += 1; }
    }
    let rows = Layout::default().direction(Direction::Vertical)
        .constraints([Constraint::Length(3), Constraint::Min(0)]).split(f.area());
    let g = Gauge::default().block(frame("repository verify state"))
        .ratio(1.0).label("integrity verified  ·  24 objects  ·  0 failures")
        .gauge_style(Style::new().fg(vir(0.45)));
    f.render_widget(g, rows[0]);
    let maxc = sh.values().copied().max().unwrap_or(1);
    let bars: Vec<Bar> = sh.iter().map(|(k, c)| {
        Bar::default().value(*c as u64).label(Line::from(k.clone())).text_value(c.to_string())
            .style(Style::new().fg(vir(*c as f64 / maxc as f64)))
    }).collect();
    let bc = BarChart::default()
        .block(frame("objects per store shard  ·  address first byte  ·  viridis by count"))
        .data(BarGroup::default().bars(&bars))
        .bar_width(3).bar_gap(1).bar_set(symbols::bar::NINE_LEVELS)
        .value_style(Style::new().fg(TEXT)).label_style(Style::new().fg(DIM));
    f.render_widget(bc, rows[1]);
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let which: usize = std::env::args().nth(1).unwrap_or_default().parse().unwrap_or(1);
    let (w, h, cap, fun): (u16, u16, &str, fn(&mut ratatui::Frame)) = match which {
        1 => (104, 24, "01 · deduplication, from a real `lore repository dump`. Rendered with ratatui; Lore ships no TUI.", p01 as fn(&mut ratatui::Frame)),
        2 => (96, 24, "02 · commit cost on one linear scale. The two invisible bars are the finding.", p02),
        3 => (96, 34, "03 · repository tree, real sizes and shared content addresses.", p03),
        4 => (96, 20, "04 · the 15-file media corpus by format. Synthetic dedup payloads excluded. Okabe-Ito is CVD-safe.", p04),
        _ => (96, 22, "05 · integrity and shard distribution, from real content addresses.", p05),
    };
    let mut t = Terminal::new(TestBackend::new(w, h))?;
    t.draw(fun)?;
    print!("{}", to_svg(&t.backend().buffer().clone(), cap));
    Ok(())
}
