#!/usr/bin/env python3
"""Generate the animated SVGs the README embeds.

    python3 docs/gen-svg.py docs

Standard library only, deterministic, no fonts fetched: every face is a system
stack, so the drawings look the same on GitHub as in a browser with no network.
Animation is SMIL and CSS inside the SVG, which GitHub renders through <img>,
and every drawing reads as a still when motion is off.

Three drawings:
  header.svg    a take in progress: 1 fps capture on the left, the transcript
                arriving on the right, the title above
  rec-flow.svg  the pipeline, with the optional AI box that RECORD_AI=0 skips
  any-cli.svg   one config line switching between the three CLIs
"""
import os
import sys

OUT = sys.argv[1] if len(sys.argv) > 1 else "docs"

BG = "#0F0D0C"      # ground
INK = "#F3ECE2"     # text
MUTED = "#8A837A"   # secondary text
LINE = "#2A2522"    # rules, connectors, card strokes
DIM = "#3A3430"     # captions
RED = "#E5322D"     # the recording dot, the optional box, the travelling packet
OK = "#5E8F5A"      # LOCAL tags
BOX = "#161311"     # card fill
MONO = 'ui-monospace, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace'
SERIF = '"Iowan Old Style", "Palatino Linotype", Palatino, Georgia, "Times New Roman", serif'

CSS = """
  .mono{font-family:%s;}
  .serif{font-family:%s;}
  @keyframes pulse{0%%,100%%{opacity:1}50%%{opacity:.15}}
  .live{animation:pulse 1.4s ease-in-out infinite}
  @keyframes ring{0%%{r:6;opacity:.9}100%%{r:18;opacity:0}}
  .ring{animation:ring 1.4s ease-out infinite}
  @keyframes blink{0%%,49%%{opacity:1}50%%,100%%{opacity:0}}
  .cursor{animation:blink 1.1s steps(1) infinite}
  @keyframes fadein{from{fill-opacity:0}to{fill-opacity:1}}
  .l{fill-opacity:0;animation:fadein .7s ease-out forwards}
  @keyframes scan{from{transform:translateY(-4px)}to{transform:translateY(%dpx)}}
  .scan{animation:scan 9s linear infinite}
  @keyframes press{0%%,88%%,100%%{transform:translateY(0)}92%%{transform:translateY(3px)}}
  .key{animation:press 3.6s ease-in-out infinite}
  @keyframes glow{0%%,100%%{stroke-opacity:.35}50%%{stroke-opacity:1}}
  .glow{animation:glow 2.4s ease-in-out infinite}
  @media (prefers-reduced-motion: reduce){*{animation:none!important}}
"""


def css(height):
    return CSS % (MONO, SERIF, height + 4)


def svg_open(w, h, title, label):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" '
            f'role="img" aria-label="{label}">\n<title>{title}</title>\n<style>{css(h)}</style>\n'
            f'<rect width="{w}" height="{h}" fill="{BG}"/>')


def corners(w, h):
    return (f'<g stroke="{LINE}" stroke-width="2" fill="none">'
            f'<path d="M28 60 V28 H60"/><path d="M{w-28} 60 V28 H{w-60}"/>'
            f'<path d="M28 {h-60} V{h-28} H60"/><path d="M{w-28} {h-60} V{h-28} H{w-60}"/></g>')


def caption(x, y, text, anchor="start", color=MUTED, size=15):
    return (f'<text class="mono" x="{x}" y="{y}" text-anchor="{anchor}" fill="{color}" '
            f'font-size="{size}" letter-spacing="2.5">{text}</text>')


def discrete(attr, values, keytimes, dur, begin="0s"):
    """A stepped <animate>: the attribute jumps between values, never tweens."""
    return (f'<animate attributeName="{attr}" values="{values}" keyTimes="{keytimes}" '
            f'calcMode="discrete" dur="{dur}s" begin="{begin}" repeatCount="indefinite"/>')


def cycle(items, dur, render):
    """Show one of several elements at a time, each for an equal slice of dur.

    render(item) returns the element's inner markup; the wrapper handles the
    opacity schedule. Same trick as a ticking digit, generalised."""
    n = len(items)
    out = []
    for i, it in enumerate(items):
        if i == 0:
            an = discrete("opacity", "1;0", f"0;{1/n:.4f}", dur)
        elif i == n - 1:
            an = discrete("opacity", "0;1", f"0;{i/n:.4f}", dur)
        else:
            an = discrete("opacity", "0;1;0", f"0;{i/n:.4f};{(i+1)/n:.4f}", dur)
        out.append(f'<g opacity="{1 if i == 0 else 0}">{render(it)}{an}</g>')
    return "".join(out)


def marching(path, color=LINE, width=2.0, dur=0.9, extra=""):
    return (f'<path d="{path}" fill="none" stroke="{color}" stroke-width="{width}" stroke-dasharray="5 6"{extra}>'
            f'<animate attributeName="stroke-dashoffset" from="0" to="-22" dur="{dur}s" repeatCount="indefinite"/></path>')


def traveller(path, begin, dur=2.6, r=4.5, color=RED):
    motion = (f'<animateMotion dur="{dur}s" begin="{begin}s" repeatCount="indefinite" calcMode="spline" '
              f'keyTimes="0;1" keySplines=".4 0 .2 1" path="{path}"/>')
    return (f'<circle r="{r}" fill="{color}">{motion}</circle>'
            f'<circle r="{r*2.2}" fill="{color}" opacity=".16">{motion}</circle>')


def card(x, y, w, h, label, sub, stroke=LINE, dash="", cls="", right=""):
    out = [f'<rect class="{cls}" x="{x}" y="{y}" width="{w}" height="{h}" rx="10" fill="{BOX}" '
           f'stroke="{stroke}" stroke-width="1.5"{dash}/>',
           f'<text class="mono" x="{x+18}" y="{y+h/2-3:.0f}" fill="{INK}" font-size="19" font-weight="700">{label}</text>',
           f'<text class="mono" x="{x+18}" y="{y+h/2+19:.0f}" fill="{MUTED}" font-size="12">{sub}</text>']
    if right:
        out.append(f'<text class="mono" x="{x+w-16}" y="{y+h/2-3:.0f}" text-anchor="end" fill="{DIM}" '
                   f'font-size="11" letter-spacing="2">{right}</text>')
    return "".join(out)


# =====================================================================
# header.svg: a take in progress
# =====================================================================
def header():
    W, H = 1280, 480
    parts = [svg_open(W, H, "lightweight-rec",
                      "lightweight-rec. One shortcut records the screen at one frame per second with the "
                      "microphone, transcribes on the Mac, and files a Markdown note in your vault.")]
    parts.append(f'<defs>'
                 f'<clipPath id="type"><rect x="86" y="228" width="0" height="34">'
                 f'<animate attributeName="width" from="0" to="1000" begin="1.1s" dur="3.4s" calcMode="linear" fill="freeze"/>'
                 f'</rect></clipPath>'
                 f'<clipPath id="ticker"><rect x="536" y="292" width="{W-536-64}" height="150"/></clipPath>'
                 f'<clipPath id="screen"><rect x="80" y="306" width="400" height="102" rx="4"/></clipPath>'
                 f'<linearGradient id="fadeTop" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{BG}"/><stop offset="1" stop-color="{BG}" stop-opacity="0"/></linearGradient>'
                 f'<linearGradient id="fadeBot" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{BG}" stop-opacity="0"/><stop offset="1" stop-color="{BG}"/></linearGradient>'
                 f'<linearGradient id="scanG" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{INK}" stop-opacity="0"/><stop offset="1" stop-color="{INK}" stop-opacity=".08"/></linearGradient>'
                 f'</defs>')
    parts.append(f'<rect class="scan" x="0" y="0" width="{W}" height="4" fill="url(#scanG)"/>')
    parts.append(corners(W, H))

    # REC, the ring, the clock. The last digit ticks: this is a live take.
    parts.append(f'<g class="mono" font-size="17" letter-spacing="2">'
                 f'<circle class="ring" cx="76" cy="55" r="6" fill="none" stroke="{RED}" stroke-width="1.5"/>'
                 f'<circle class="live" cx="76" cy="55" r="6" fill="{RED}"/>'
                 f'<text x="94" y="61" fill="{RED}" font-weight="700">REC</text>'
                 f'<g fill="{MUTED}"><text x="150" y="61">00:41:2</text>')
    digits = [str(d) for d in range(10)]
    parts.append(cycle(digits, 10, lambda d: f'<text x="237" y="61">{d}</text>'))
    parts.append('</g></g>')

    # The pipeline steps, lit in turn, top right.
    steps = ["OPTION+R", "CAPTURE", "WHISPER", "NOTE"]
    spans = []
    for i, s in enumerate(steps):
        if i == 0:
            an = discrete("fill", f"{INK};{MUTED}", "0;0.25", 4.8)
        else:
            an = discrete("fill", f"{MUTED};{INK};{MUTED}", f"0;{i/4};{(i+1)/4}", 4.8)
        sep = "" if i == len(steps) - 1 else " · "
        spans.append(f'<tspan fill="{INK if i == 0 else MUTED}">{s}{an}</tspan>{sep}')
    parts.append(f'<text class="mono" x="{W-64}" y="61" text-anchor="end" font-size="16" letter-spacing="1.5">{"".join(spans)}</text>')

    # The name, letter by letter.
    name = "lightweight-rec"
    letters = "".join(f'<tspan class="l" style="animation-delay:{0.15+i*0.045:.3f}s">{c}</tspan>' for i, c in enumerate(name))
    parts.append(f'<text class="serif" x="62" y="196" fill="{INK}" font-size="104" letter-spacing="-2">{letters}</text>')

    # The typed line.
    parts.append(f'<g class="mono" font-size="22"><text x="66" y="254" fill="{RED}">$</text>'
                 f'<text x="90" y="254" fill="{MUTED}" clip-path="url(#type)">one shortcut. one note. nothing leaves the Mac unless you say so.'
                 f'<tspan class="cursor" fill="{INK}">▍</tspan></text></g>')

    # Left: the captured display, at one frame per second. Nothing here tweens:
    # the pointer jumps, the frame counter steps, the filmstrip advances, once
    # a second, because that is what a 1 fps capture looks like.
    parts.append(caption(64, 286, "CAPTURE SCREEN 0 · 1 FPS", color=DIM, size=13))
    parts.append(f'<rect x="64" y="292" width="432" height="150" rx="10" fill="{BOX}" stroke="{LINE}" stroke-width="1.5"/>')
    parts.append(f'<rect x="80" y="306" width="400" height="102" rx="4" fill="#0B0A09"/>')
    # a fake window: a title bar and a few lines of "text"
    win = [f'<rect x="96" y="316" width="368" height="16" rx="3" fill="#1C1917"/>',
           f'<circle cx="106" cy="324" r="3" fill="{RED}" opacity=".8"/><circle cx="116" cy="324" r="3" fill="#8A837A" opacity=".5"/><circle cx="126" cy="324" r="3" fill="#8A837A" opacity=".5"/>']
    widths = [220, 300, 180, 260, 140]
    for i, wdt in enumerate(widths):
        win.append(f'<rect x="96" y="{342+i*12}" width="{wdt}" height="6" rx="3" fill="#2A2522"/>')
    parts.append(f'<g clip-path="url(#screen)">{"".join(win)}')
    # the pointer, jumping once a second between eight spots
    spots = ["150 352", "300 364", "240 386", "410 346", "120 392", "330 376", "200 358", "380 388"]
    frames = 8
    for i, xy in enumerate(spots):
        x, y = xy.split()
        kt = "0;%.4f" % (1/frames) if i == 0 else ("0;%.4f" % (i/frames) if i == frames-1 else "0;%.4f;%.4f" % (i/frames, (i+1)/frames))
        vals = "1;0" if i == 0 else ("0;1" if i == frames-1 else "0;1;0")
        parts.append(f'<path d="M{x} {y} l0 14 l4 -3 l3 6 l2 -1 l-3 -6 l5 0 z" fill="{INK}" opacity="{1 if i == 0 else 0}">'
                     f'{discrete("opacity", vals, kt, frames)}</path>')
    parts.append('</g>')
    # the pulsing dot in the corner of the display
    parts.append(f'<circle class="live" cx="466" cy="320" r="5" fill="{RED}"/>')
    # frame counter and filmstrip in the bezel under the screen
    parts.append(f'<g class="mono" font-size="12" letter-spacing="1.5" fill="{MUTED}">')
    parts.append(cycle([f"FRAME {i+1}/8 · k{i+1:03d}.jpg" for i in range(frames)], frames,
                       lambda t: f'<text x="80" y="430">{t}</text>'))
    parts.append('</g>')
    for i in range(frames):
        x = 306 + i * 22
        kt = "0;%.4f" % (1/frames) if i == 0 else ("0;%.4f" % (i/frames) if i == frames-1 else "0;%.4f;%.4f" % (i/frames, (i+1)/frames))
        vals = f"{INK};{LINE}" if i == 0 else (f"{LINE};{INK}" if i == frames-1 else f"{LINE};{INK};{LINE}")
        parts.append(f'<rect x="{x}" y="421" width="16" height="8" rx="2" fill="{INK if i == 0 else LINE}">'
                     f'{discrete("fill", vals, kt, frames)}</rect>')

    # Right: the transcript, arriving line by line, on device.
    parts.append(caption(536, 286, "TRANSCRIPT · WHISPER · ON DEVICE", color=DIM, size=13))
    rows = [("00:00", "So the duplicates all come from the same worker."),
            ("00:06", "Every one of them on the fifth attempt."),
            ("00:14", "Right, and we never mark the row as consumed."),
            ("00:21", "So the retry writes it again."),
            ("00:27", "Then the fix is the backoff, not the dedupe."),
            ("00:34", "Exponential, and a dead letter after the third."),
            ("00:41", "What about the alert threshold?"),
            ("00:45", "Leave it. Separate ticket."),
            ("00:52", "Fine. Can you drop the frames in the note?"),
            ("00:58", "Already there, it files itself on stop.")]
    rh = 24
    top = 314
    n = len(rows)
    loop = n * rh
    lines = []
    for k in range(2):
        for i, (t, s) in enumerate(rows):
            y = top + (k * n + i) * rh
            lines.append(f'<text x="536" y="{y}" fill="{RED}">▸</text>'
                         f'<text x="556" y="{y}" fill="{MUTED}">{t}</text>'
                         f'<text x="616" y="{y}" fill="{INK}">{s}</text>')
    parts.append(f'<g clip-path="url(#ticker)" class="mono" font-size="15">'
                 f'<g><animateTransform attributeName="transform" type="translate" from="0 0" to="0 -{loop}" '
                 f'dur="{n*1.9:.1f}s" repeatCount="indefinite"/>{"".join(lines)}</g></g>')
    parts.append(f'<rect x="536" y="292" width="{W-536-64}" height="24" fill="url(#fadeTop)"/>')
    parts.append(f'<rect x="536" y="{292+150-24}" width="{W-536-64}" height="24" fill="url(#fadeBot)"/>')

    parts.append(caption(64, H-22, "1 FPS · ~110 MB / HOUR · HARDWARE HEVC", color=DIM, size=13))
    parts.append(caption(W-64, H-22, "MACOS · OPEN SOURCE · MIT", anchor="end", color=DIM, size=13))
    parts.append('</svg>')
    return "\n".join(parts)


# =====================================================================
# rec-flow.svg: the pipeline
# =====================================================================
def rec_flow():
    W, H = 1280, 260
    nodes = [("⌥ R", "one shortcut", None),
             ("capture", "1 fps screen + mic", "LOCAL"),
             ("whisper", "transcript, on device", "LOCAL"),
             ("$RECORD_AI", "title · tags · summary", "OPTIONAL"),
             ("note.md", "filed in your vault", "LOCAL")]
    nw, gap = 196, 43
    total = 5 * nw + 4 * gap
    sx = (W - total) // 2
    cy = 122
    parts = [svg_open(W, H, "lightweight-rec pipeline",
                      "Option R, then capture at one frame per second with the microphone, whisper on the Mac, "
                      "an optional pass through the AI CLI you name in RECORD_AI for title, tags and summary, "
                      "and a Markdown note in your vault.")]
    parts.append(caption(sx, 44, "LIGHTWEIGHT-REC · ~110 MB / HOUR"))
    parts.append(caption(W - sx, 44, "RECORD_AI=0 SKIPS THE DASHED BOX", anchor="end"))
    conns, boxes = [], []
    xs = []
    for i, (t, sub, tag) in enumerate(nodes):
        x = sx + i * (nw + gap)
        xs.append(x)
        if i == 0:
            boxes.append(f'<g class="key"><rect x="{x+38}" y="{cy-40}" width="120" height="80" rx="14" fill="#1C1917" stroke="{LINE}" stroke-width="2"/>'
                         f'<rect x="{x+44}" y="{cy-36}" width="108" height="64" rx="11" fill="#24201D"/>'
                         f'<text class="mono" x="{x+98}" y="{cy+10}" text-anchor="middle" fill="{INK}" font-size="30" font-weight="700">⌥ R</text></g>')
            boxes.append(f'<rect x="{x+38}" y="{cy+40}" width="120" height="4" rx="2" fill="#0A0908"/>')
        else:
            optional = tag == "OPTIONAL"
            stroke = RED if optional else LINE
            dash = ' stroke-dasharray="6 5"' if optional else ''
            boxes.append(f'<rect x="{x}" y="{cy-40}" width="{nw}" height="80" rx="12" fill="{BOX}" stroke="{stroke}" stroke-width="1.5"{dash}/>')
            boxes.append(f'<text class="mono" x="{x+nw/2}" y="{cy-4}" text-anchor="middle" fill="{INK}" font-size="{21 if optional else 24}" font-weight="700">{t}</text>')
            boxes.append(f'<text class="mono" x="{x+nw/2}" y="{cy+23}" text-anchor="middle" fill="{MUTED}" font-size="14">{sub}</text>')
        if tag:
            col = RED if tag == "OPTIONAL" else OK
            boxes.append(f'<text class="mono" x="{x+nw/2}" y="{cy+70}" text-anchor="middle" fill="{col}" font-size="14" letter-spacing="2.5">{tag}</text>')
        if i < 4:
            lx = x + 158 if i == 0 else x + nw
            conns.append(marching(f"M{lx} {cy} H{x+nw+gap}"))
    # The bypass: from whisper straight to the note, over the optional box.
    x3_end = xs[2] + nw
    x5 = xs[4]
    bypass = f"M{x3_end} {cy} C{x3_end+60} {cy} {x3_end+70} {cy-60} {x3_end+gap+nw/2:.0f} {cy-60} S{x5-60} {cy} {x5} {cy}"
    conns.append(marching(bypass, color=LINE, width=1.5, dur=1.2, extra=' stroke-opacity=".7"'))
    main = f"M {sx+158} {cy} H {xs[4]}"
    parts.extend(conns)
    parts.extend(boxes)
    parts.append(traveller(main, begin=0, dur=4.5))
    parts.append(traveller(bypass, begin=2.6, dur=4.5, r=3.5, color=MUTED))
    parts.append(caption(sx, H - 22, "ONE MP4 PER HOUR · NOTHING RUNS UNTIL YOU PRESS IT", color=DIM, size=13))
    parts.append(caption(W - sx, H - 22, "THE GREY DOT IS RECORD_AI=0", anchor="end", color=DIM, size=13))
    parts.append('</svg>')
    return "\n".join(parts)


# =====================================================================
# any-cli.svg: one config line, three CLIs
# =====================================================================
def any_cli():
    W, H = 1280, 380
    clis = [("claude", "claude code", "sonnet · haiku", "ANTHROPIC"),
            ("cursor", "cursor cli", "cursor grok 4.6", "CURSOR"),
            ("copilot", "copilot cli", "gemini 3.8 flash", "GITHUB")]
    cx0, cw, ch = 64, 268, 64
    cys = [120, 200, 280]
    bx, by, bw, bh = 500, 150, 300, 100
    nx, nw, nh = 992, 224, 64
    T = 9.0  # one full turn of the selector
    n = len(clis)

    parts = [svg_open(W, H, "Plug any CLI",
                      "One config line, RECORD_AI, picks which CLI writes the title, tags, summary and screen "
                      "description: Claude Code, Cursor CLI or Copilot CLI. The note is the same either way.")]
    parts.append(corners(W, H))
    parts.append(caption(64, 52, "ONE CONFIG LINE"))
    parts.append(caption(W - 64, 52, "SWAP THE CLI, KEEP THE NOTE", anchor="end"))

    def window(i):
        # keyTimes over one turn for CLI i: active in [i/n, (i+1)/n)
        if i == 0:
            return "0;%.4f" % (1/n), lambda a, b: f"{a};{b}"
        if i == n - 1:
            return "0;%.4f" % (i/n), lambda a, b: f"{b};{a}"
        return "0;%.4f;%.4f" % (i/n, (i+1)/n), lambda a, b: f"{b};{a};{b}"

    # The selector: RECORD_AI= and the value that changes. The values are
    # separate texts stacked on one anchor, so the visible one always sits
    # right after the equals sign, caret included.
    sel = bx + bw / 2 + 8
    parts.append(f'<text class="mono" x="{sel}" y="98" text-anchor="end" fill="{MUTED}" font-size="26">RECORD_AI=</text>')
    parts.append(f'<g class="mono" font-size="26" font-weight="700" fill="{INK}">')
    parts.append(cycle([c[0] for c in clis], T,
                       lambda key: f'<text x="{sel}" y="98">{key}<tspan class="cursor">▍</tspan></text>'))
    parts.append('</g>')

    paths, dots, cards = [], [], []
    for i, ((_key, label, sub, vendor), y) in enumerate(zip(clis, cys)):
        kt, order = window(i)
        p = f"M{cx0+cw} {y} C{cx0+cw+110} {y} {bx-110} {by+bh/2} {bx} {by+bh/2}"
        paths.append(f'<path d="{p}" fill="none" stroke="{LINE}" stroke-width="2" stroke-dasharray="5 6">'
                     f'<animate attributeName="stroke-dashoffset" from="0" to="-22" dur="0.9s" repeatCount="indefinite"/>'
                     f'{discrete("stroke", order(RED, LINE), kt, T)}</path>')
        cards.append(f'<rect x="{cx0}" y="{y-ch/2}" width="{cw}" height="{ch}" rx="10" fill="{BOX}" stroke="{LINE}" stroke-width="1.5">'
                     f'{discrete("stroke", order(RED, LINE), kt, T)}</rect>')
        cards.append(f'<text class="mono" x="{cx0+18}" y="{y-3}" fill="{INK}" font-size="19" font-weight="700">{label}</text>')
        cards.append(f'<text class="mono" x="{cx0+18}" y="{y+19}" fill="{MUTED}" font-size="12">{sub}</text>')
        cards.append(f'<text class="mono" x="{cx0+cw-16}" y="{y-3}" text-anchor="end" fill="{DIM}" font-size="11" letter-spacing="2">{vendor}</text>')
        # the packet: moves during this CLI's third of the turn, hidden otherwise
        begin = i * T / n
        motion = (f'<animateMotion dur="{T}s" begin="{begin}s" repeatCount="indefinite" calcMode="linear" '
                  f'keyPoints="0;1;1" keyTimes="0;{1/n:.4f};1" path="{p}"/>')
        vis = discrete("opacity", "1;0", f"0;{1/n:.4f}", T, begin=f"{begin}s")
        dots.append(f'<g opacity="0">{vis}<circle r="4.5" fill="{RED}">{motion}</circle>'
                    f'<circle r="9.9" fill="{RED}" opacity=".16">{motion}</circle></g>')

    # the shared box: what every CLI has to produce
    cards.append(f'<rect class="glow" x="{bx}" y="{by}" width="{bw}" height="{bh}" rx="14" fill="{BOX}" stroke="{RED}" stroke-width="1.5" stroke-dasharray="6 5"/>')
    cards.append(f'<text class="mono" x="{bx+bw/2}" y="{by+44}" text-anchor="middle" fill="{INK}" font-size="20" font-weight="700">title · tags · summary</text>')
    cards.append(f'<text class="mono" x="{bx+bw/2}" y="{by+70}" text-anchor="middle" fill="{MUTED}" font-size="14">and what was on screen</text>')
    cards.append(f'<text class="mono" x="{bx+bw/2}" y="{by+bh+26}" text-anchor="middle" fill="{RED}" font-size="13" letter-spacing="2.5">OPTIONAL · PAID · OFF-MACHINE</text>')
    # box -> note
    p_out = f"M{bx+bw} {by+bh/2} C{bx+bw+90} {by+bh/2} {nx-90} {cys[1]} {nx} {cys[1]}"
    paths.append(marching(p_out))
    dots.append(traveller(p_out, begin=1.2, dur=2.2, color=INK, r=4))
    cards.append(card(nx, cys[1]-nh/2, nw, nh, "note.md", "same note, any CLI"))
    cards.append(f'<text class="mono" x="{nx+nw/2}" y="{cys[1]+nh/2+26}" text-anchor="middle" fill="{OK}" font-size="13" letter-spacing="2.5">IN YOUR VAULT</text>')

    parts.extend(paths)
    parts.extend(cards)
    parts.extend(dots)
    parts.append(caption(64, H - 22, "RECORD_AI=0 MAKES NO CALL AT ALL", color=DIM, size=13))
    parts.append(caption(W - 64, H - 22, "CAPTURE AND TRANSCRIPT NEVER LEAVE THE MAC", anchor="end", color=DIM, size=13))
    parts.append('</svg>')
    return "\n".join(parts)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, fn in (("header.svg", header), ("rec-flow.svg", rec_flow), ("any-cli.svg", any_cli)):
        with open(os.path.join(OUT, name), "w", encoding="utf-8") as f:
            f.write(fn())
        print(name, os.path.getsize(os.path.join(OUT, name)), "bytes")
