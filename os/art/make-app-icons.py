#!/usr/bin/env python3
"""Ollie OS's app icons, one family: a flat tile in the app's own colour with a
simple line drawing on it (no emoji, no shine). Writes each as SVG
(hicolor/scalable/apps/NAME.svg) and as PNG at 256, 128, 64 and 48 px (the
apps' windows use the PNGs), with rsvg-convert:

  python3 os/art/make-app-icons.py

The drawings are on a 256 x 256 grid; the tile is 224 wide, corners 52.
"""
import math
import os
import subprocess

INK = "#FFF6E9"  # the drawing's colour: warm white
F = f' fill="{INK}" stroke="none"'  # a filled shape instead of a line

# The palette: a few strong, slightly muted colours, each used for a kind of app.
RED, ORANGE, MUSTARD, GREEN, TEAL = "#C8473D", "#E07A2F", "#D9A021", "#4F8A45", "#257A78"
BLUE, NAVY, PURPLE, PLUM, BROWN, SLATE, PINK = "#336B9E", "#283A63", "#6A4E9C", "#8E4573", "#7E5634", "#4C5363", "#D0587E"


def star(cx, cy, r1, r2, n=5):
    pts = []
    for i in range(n * 2):
        r = r1 if i % 2 == 0 else r2
        a = math.pi * i / n - math.pi / 2
        pts.append(f"{cx + r * math.cos(a):.1f} {cy + r * math.sin(a):.1f}")
    return "M" + " L".join(pts) + " Z"


def gear(cx, cy, r_out, r_in, teeth=8):
    pts, step = [], 2 * math.pi / teeth
    for i in range(teeth):
        a = i * step
        for da, r in ((-0.30, r_in), (-0.18, r_out), (0.18, r_out), (0.30, r_in)):
            pts.append(f"{cx + r * math.cos(a + da * step * 1.6):.1f} {cy + r * math.sin(a + da * step * 1.6):.1f}")
    return "M" + " L".join(pts) + " Z"


def lifebuoy_bands():
    out = []
    for deg in (45, 135, 225, 315):
        a = math.radians(deg)
        x1, y1 = 128 + 30 * math.cos(a), 128 + 30 * math.sin(a)
        x2, y2 = 128 + 60 * math.cos(a), 128 + 60 * math.sin(a)
        out.append(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke-width="24" stroke-linecap="butt"/>')
    return "".join(out)


# icon name: (tile colour, drawing)
ICONS = {
    "ollie-games": (PURPLE, f'<rect x="66" y="150" width="124" height="42" rx="14"/><line x1="128" y1="150" x2="128" y2="106"/>'
                            f'<circle cx="128" cy="86" r="24"{F}/><circle cx="96" cy="171" r="8"{F}/>'),
    "ollie-pet": (TEAL, f'<rect x="66" y="70" width="124" height="116" rx="28"/><circle cx="106" cy="120" r="11"{F}/>'
                        f'<circle cx="150" cy="120" r="11"{F}/><path d="M104 150 Q128 170 152 150"/>'),
    "ollie-finder": (BLUE, '<circle cx="114" cy="112" r="40"/><line x1="143" y1="141" x2="184" y2="182" stroke-width="20"/>'),
    "ollie-typing": (NAVY, '<rect x="52" y="86" width="152" height="92" rx="16"/>'
                           + "".join(f'<rect x="{x}" y="{y}" width="14" height="14" rx="3"{F}/>' for y in (106, 128) for x in (73, 99, 125, 151, 177) if not (y == 128 and x == 177))
                           + '<line x1="98" y1="158" x2="158" y2="158"/>'),
    "ollie-coop": (ORANGE, '<path d="M86 100 H170 C194 100 205 122 207 150 C209 176 198 186 186 186 C174 186 168 170 156 162 H100 C88 170 82 186 70 186 C58 186 47 176 49 150 C51 122 62 100 86 100 Z"/>'
                           f'<path d="M88 130 V158 M74 144 H102" stroke-width="10"/><circle cx="162" cy="134" r="8"{F}/><circle cx="180" cy="152" r="8"{F}/>'),
    "ollie-paint": (PURPLE, '<line x1="190" y1="66" x2="132" y2="124" stroke-width="18"/><path d="M118 120 L136 138"/>'
                            f'<path d="M114 128 L128 142 C126 168 104 186 70 190 C76 160 90 134 114 128 Z"{F}/><circle cx="178" cy="176" r="12"{F}/>'),
    "ollie-mouse": (TEAL, '<path d="M84 52 V188 L118 156 L142 206 L166 194 L142 146 H190 Z" stroke-linejoin="round"/>'),
    "ollie-undo-update": (SLATE, '<path d="M86 96 A60 60 0 1 1 74 160"/><path d="M60 70 L86 100 L118 84" stroke-linejoin="round"/>'
                                 '<path d="M128 100 V132 L150 146"/>'),
    "ollie-school": (ORANGE, '<rect x="58" y="70" width="140" height="124" rx="16"/><line x1="58" y1="106" x2="198" y2="106"/>'
                             '<line x1="94" y1="56" x2="94" y2="82"/><line x1="162" y1="56" x2="162" y2="82"/>'
                             f'<circle cx="128" cy="150" r="17"{F}/>'
                             + "".join(f'<line x1="{128 + 26 * math.cos(a):.1f}" y1="{150 + 26 * math.sin(a):.1f}" x2="{128 + 34 * math.cos(a):.1f}" y2="{150 + 34 * math.sin(a):.1f}" stroke-width="8"/>'
                                       for a in [i * math.pi / 4 for i in range(8)])),
    "ollie-sticker": (PINK, f'<path d="{star(128, 132, 66, 28)}"/>'),
    "ollie-comic": (MUSTARD, '<path d="M72 80 H184 A20 20 0 0 1 204 100 V148 A20 20 0 0 1 184 168 H120 L88 196 V168 H72 A20 20 0 0 1 52 148 V100 A20 20 0 0 1 72 80 Z"/>'
                             f'<circle cx="100" cy="124" r="9"{F}/><circle cx="128" cy="124" r="9"{F}/><circle cx="156" cy="124" r="9"{F}/>'),
    "ollie-animator": (RED, '<rect x="74" y="60" width="108" height="136" rx="12"/><rect x="104" y="90" width="48" height="76" rx="4" stroke-width="10"/>'
                            + "".join(f'<rect x="{x}" y="{y}" width="10" height="14" rx="2"{F}/>' for x in (84, 162) for y in (78, 121, 164))),
    "ollie-soundboard": (PLUM, f'<path d="M66 106 H94 L132 76 V180 L94 150 H66 Z"{F}/><path d="M154 104 Q170 128 154 152"/><path d="M174 86 Q202 128 174 170"/>'),
    "ollie-codequest": (GREEN, f'<rect x="70" y="94" width="116" height="92" rx="22"/><line x1="128" y1="94" x2="128" y2="72"/><circle cx="128" cy="64" r="10"{F}/>'
                               f'<circle cx="106" cy="134" r="11"{F}/><circle cx="150" cy="134" r="11"{F}/><line x1="108" y1="162" x2="148" y2="162"/>'),
    "ollie-space": (NAVY, f'<circle cx="128" cy="128" r="40"/><ellipse cx="128" cy="128" rx="80" ry="22" transform="rotate(-20 128 128)" stroke-width="10"/>'
                          f'<circle cx="68" cy="74" r="5"{F}/><circle cx="190" cy="186" r="5"{F}/><circle cx="184" cy="66" r="4"{F}/>'),
    "ollie-spelling": (MUSTARD, '<path d="M76 180 L88 144 L160 72 L184 96 L112 168 Z"/><path d="M88 144 L112 168 M148 84 L172 108"/><line x1="150" y1="188" x2="196" y2="188"/>'),
    "ollie-world": (BLUE, '<circle cx="128" cy="128" r="62"/><ellipse cx="128" cy="128" rx="26" ry="62"/><line x1="66" y1="128" x2="190" y2="128"/>'
                          '<path d="M76 98 H180 M76 158 H180" stroke-width="10"/>'),
    "ollie-recovery": (RED, '<circle cx="128" cy="128" r="62"/><circle cx="128" cy="128" r="28"/>' + lifebuoy_bands()),
    "ollie-settings": (SLATE, f'<path d="{gear(128, 128, 70, 52)}"/><circle cx="128" cy="128" r="20"/>'),
    "ollie-os-update": (GREEN, '<circle cx="128" cy="128" r="62"/><path d="M128 164 V94 M98 122 L128 92 L158 122"/>'),
    "ollie-update-checker": (MUSTARD, '<path d="M128 68 C100 68 88 92 88 118 V146 L72 168 H184 L168 146 V118 C168 92 156 68 128 68 Z"/><path d="M112 184 Q128 198 144 184"/>'),
    "ollie-scanner-notes": (SLATE, '<rect x="78" y="60" width="100" height="136" rx="12"/><path d="M100 98 H156 M100 124 H156 M100 150 H136"/>'),
    "ollie-wallpaper-maker": (PURPLE, f'<rect x="56" y="74" width="144" height="108" rx="12"/><path d="M70 168 L110 124 L138 152 L156 136 L186 168"/><circle cx="160" cy="104" r="12"{F}/>'),
    "ollie-fixer": (ORANGE, '<g transform="rotate(-45 128 128)"><rect x="54" y="102" width="148" height="52" rx="26"/><rect x="106" y="102" width="44" height="52" stroke-width="10"/></g>'),
    "ollie-storage": (BLUE, f'<rect x="60" y="82" width="136" height="92" rx="14"/><line x1="60" y1="124" x2="196" y2="124"/><line x1="82" y1="150" x2="128" y2="150"/><circle cx="168" cy="150" r="9"{F}/>'),
    "ollie-stuff-saver": (BROWN, '<path d="M70 102 L128 78 L186 102 V164 L128 190 L70 164 Z"/><path d="M70 102 L128 126 L186 102 M128 126 V190"/>'),
    "ollie-download-tracker": (TEAL, '<path d="M128 64 V146 M96 116 L128 148 L160 116"/><path d="M68 150 V182 H188 V150"/>'),
    "ollie-write": (PURPLE, f'<rect x="94" y="104" width="68" height="94" rx="14"/><rect x="106" y="60" width="44" height="44" rx="4"/>'
                            f'<rect x="114" y="74" width="9" height="12"{F}/><rect x="133" y="74" width="9" height="12"{F}/>'),
    "ollie-restart-windows": (BLUE, '<rect x="60" y="68" width="136" height="116" rx="12"/><line x1="60" y1="98" x2="196" y2="98"/>'
                                    '<path d="M128 98 V184 M60 141 H196" stroke-width="10"/>'),
    "ollie-appcenter": (PINK, '<path d="M74 102 H182 L172 190 H84 Z"/><path d="M104 102 V90 A24 24 0 0 1 152 90 V102"/>'),
    "ollie-mathquest": (TEAL, '<path d="M100 76 V120 M78 98 H122"/><path d="M134 98 H178"/><path d="M82 140 L118 176 M118 140 L82 176"/><path d="M134 148 H178 M134 168 H178"/>'),
    "ollie-trophies": (MUSTARD, '<path d="M90 68 H166 V106 A38 38 0 0 1 90 106 Z"/><path d="M90 82 H70 A18 18 0 0 0 90 118 M166 82 H186 A18 18 0 0 1 166 118"/>'
                                '<line x1="128" y1="144" x2="128" y2="172"/><line x1="98" y1="184" x2="158" y2="184"/>'),
    "ollie-gamehub": (NAVY, f'<rect x="54" y="72" width="148" height="98" rx="14"/><path d="M104 196 H152 M128 170 V196"/><path d="M114 100 L150 121 L114 142 Z"{F}/>'),
    "ollie-quickmenu": (ORANGE, f'<path d="M142 56 L86 138 H124 L110 200 L170 114 H132 Z"{F}/>'),
    "ollie-playtime": (TEAL, '<circle cx="128" cy="142" r="56"/><path d="M128 142 V110 M112 66 H144 M128 66 V86 M170 92 L180 82"/>'),
    "ollie-music": (PURPLE, f'<path d="M108 170 V84 L174 70 V156"/><ellipse cx="92" cy="170" rx="20" ry="15"{F}/><ellipse cx="158" cy="156" rx="20" ry="15"{F}/>'),
    "ollie-photobooth": (RED, '<rect x="52" y="92" width="152" height="98" rx="16"/><path d="M98 92 L110 70 H146 L158 92"/><circle cx="128" cy="140" r="28"/>'),
    "ollie-tour": (GREEN, '<path d="M128 198 C128 198 74 150 74 112 A54 54 0 0 1 182 112 C182 150 128 198 128 198 Z"/><circle cx="128" cy="112" r="18"/>'),
}


def svg(colour, drawing):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">'
            f'<rect x="16" y="16" width="224" height="224" rx="52" fill="{colour}"/>'
            f'<g fill="none" stroke="{INK}" stroke-width="14" stroke-linecap="round" stroke-linejoin="round">{drawing}</g></svg>\n')


here = os.path.dirname(os.path.abspath(__file__))
dest = os.path.join(here, "..", "profile", "airootfs", "usr", "share", "icons", "hicolor")
for name, (colour, drawing) in ICONS.items():
    path = os.path.join(dest, "scalable", "apps", name + ".svg")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(svg(colour, drawing))
    for size in (256, 128, 64, 48):
        out = os.path.join(dest, f"{size}x{size}", "apps", name + ".png")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), "-o", out, path], check=True)
print(len(ICONS), "icons")
