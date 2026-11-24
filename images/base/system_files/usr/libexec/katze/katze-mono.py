#!/usr/bin/env python3
"""Katze Mono: one-colour application icons on a circle or squircle.

Writes an icon theme with one icon per visible application: a glyph in a
single colour on a dark shape. Everything else is inherited from Breeze.

  katze-mono.py --report          list the glyph source of every application
  katze-mono.py --sheet all.svg   write one picture with every icon
  katze-mono.py --follow-accent   write the theme to ~/.local/share/icons/katze-mono

Glyph sources, in order:
  alias    aliases.toml, which points an application at a glyph by name
  own      <glyphs dir>/<icon>.svg, a brand mark saved under the icon's name
  breeze   Breeze apps/22/<icon>-symbolic.svg
  app      the application's own symbolic icon (hicolor or Adwaita)
  generic  a line glyph for the application's category, from the glyphs
           directory or else from Breeze
  initial  the first letter of the name
"""

from __future__ import annotations

import argparse
import configparser
import math
import os
import re
import sys
import tomllib
import xml.etree.ElementTree as ET
from collections import Counter
from dataclasses import dataclass
from html import escape
from pathlib import Path

SOURCES = ("alias", "own", "breeze", "app", "generic", "initial")

# First match wins, so the more specific categories come first.
CATEGORY_ICONS = (
    ("Development", "applications-development"),
    ("Game", "applications-games"),
    ("Graphics", "applications-graphics"),
    ("Network", "applications-internet"),
    ("AudioVideo", "applications-multimedia"),
    ("Audio", "applications-multimedia"),
    ("Video", "applications-multimedia"),
    ("Office", "applications-office"),
    ("Education", "applications-education"),
    ("Science", "applications-science"),
    ("Settings", "applications-system"),
    ("System", "applications-system"),
    ("Utility", "applications-utilities"),
)

# Where an alias may point, besides the glyphs directory: any small one-colour icon of Breeze.
ALIAS_DIRS = tuple(
    (theme, f"{context}/22") for theme in ("breeze-dark", "breeze")
    for context in ("apps", "actions", "places", "devices", "categories", "preferences",
                    "status", "mimetypes", "emblems")
)

CANVAS = 64        # the icon's own coordinate system
SHAPE_RADIUS = 30  # leaves a 2 px margin
GLYPH_SIZE = 40    # the glyph's box, centred
BLEED_SCALE = 0.85 # solid brand marks fill their whole box; other glyphs keep a margin
LINE_WIDTH = 1.25  # of drawn lines with no width of their own, close to Breeze's at this size
SMALL = 22         # "<icon>-symbolic": the glyph alone, in the text colour

SVG_NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG_NS)
ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")


@dataclass
class App:
    desktop_id: str
    name: str
    icon: str
    categories: list[str]


@dataclass
class Glyph:
    source: str
    path: Path | None  # None means: draw the letter
    detail: str        # what the report shows
    full_bleed: bool = False
    outline: bool = False  # draw a solid mark as its contour
    scale: float = 1.0     # this glyph's own size correction


# --- Finding applications and glyphs -----------------------------------------

def data_dirs() -> list[Path]:
    home = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    system = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":")
    # Flatpak adds these at login, but a bare shell may not have them.
    extra = [str(home / "flatpak/exports/share"), "/var/lib/flatpak/exports/share"]
    seen: dict[Path, None] = {}
    for d in [str(home), *system, *extra]:
        if d:
            seen.setdefault(Path(d), None)
    return list(seen)


def parse_desktop(path: Path) -> dict[str, str]:
    entry: dict[str, str] = {}
    section = ""
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return entry
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("["):
            section = line
        elif section == "[Desktop Entry]" and "=" in line and not line.startswith("#"):
            key, value = line.split("=", 1)
            entry.setdefault(key.strip(), value.strip())
    return entry


def visible_apps(dirs: list[Path]) -> list[App]:
    apps: dict[str, App | None] = {}
    for d in dirs:
        base = d / "applications"
        for path in sorted(base.rglob("*.desktop")) if base.is_dir() else []:
            desktop_id = str(path.relative_to(base)).replace("/", "-")
            if desktop_id in apps:
                continue  # an earlier directory overrides this one
            e = parse_desktop(path)
            hidden = (
                e.get("Type") != "Application"
                or e.get("NoDisplay") == "true"
                or e.get("Hidden") == "true"
                or not e.get("Icon")
            )
            apps[desktop_id] = None if hidden else App(
                desktop_id=desktop_id,
                name=e.get("Name", desktop_id),
                icon=e["Icon"],
                categories=[c for c in e.get("Categories", "").split(";") if c],
            )
    return sorted((a for a in apps.values() if a), key=lambda a: a.name.lower())


def icon_roots(dirs: list[Path]) -> list[Path]:
    roots = [Path.home() / ".icons", *(d / "icons" for d in dirs)]
    return [r for r in roots if r.is_dir()]


def first_file(candidates) -> Path | None:
    return next((p for p in candidates if p.is_file()), None)


def find_named(name: str, roots: list[Path], own: Path) -> Path | None:
    return first_file([
        own / f"{name}.svg",
        *(r / theme / sub / f"{name}{suffix}.svg"
          for r in roots for theme, sub in ALIAS_DIRS for suffix in ("-symbolic", "")),
    ])


def find_glyph(app: App, roots: list[Path], own: Path, aliases: dict[str, str],
               outlined: set[str] = frozenset(), scales: dict[str, float] | None = None) -> Glyph:
    glyph = pick_glyph(app, roots, own, aliases)
    if glyph.path:
        name = glyph.path.stem.removesuffix("-symbolic")
        glyph.outline = name in outlined
        glyph.scale = float((scales or {}).get(name, 1))
    return glyph


def pick_glyph(app: App, roots: list[Path], own: Path, aliases: dict[str, str]) -> Glyph:
    icon = app.icon
    # A path, absolute or not: a theme only answers to names
    absolute = "/" in icon
    letter = app.name[:1].upper()

    # An alias matches the Icon= value or, for launchers that share one, the desktop file.
    target = aliases.get(app.desktop_id.removesuffix(".desktop")) or aliases.get(icon)
    if target:
        hit = find_named(target, roots, own)
        if hit:
            return Glyph("alias", hit, hit.name,
                         full_bleed=hit.parent == own and not hit.stem.endswith("-line"))
        print(f"warning: alias {target!r} for {app.name} names no glyph", file=sys.stderr)

    hit = first_file([own / f"{Path(icon).stem if absolute else icon}.svg"])
    if hit:
        return Glyph("own", hit, hit.name, full_bleed=True)

    if absolute:
        return Glyph("initial", None, letter)

    hit = first_file(r / theme / "apps/22" / f"{icon}-symbolic.svg"
                     for r in roots for theme in ("breeze-dark", "breeze"))
    if hit:
        return Glyph("breeze", hit, hit.name)

    hit = first_file(r / theme / sub / f"{icon}-symbolic.svg"
                     for r in roots for theme in ("hicolor", "Adwaita")
                     for sub in ("symbolic/apps", "scalable/apps"))
    if hit:
        return Glyph("app", hit, hit.name)

    for category, generic in CATEGORY_ICONS:
        if category in app.categories:
            hit = first_file([
                own / f"generic-{generic.removeprefix('applications-')}-line.svg",
                *(r / theme / "categories/22" / f"{generic}-symbolic.svg"
                  for r in roots for theme in ("breeze-dark", "breeze")),
            ])
            if hit:
                return Glyph("generic", hit, generic)

    return Glyph("initial", None, letter)


# --- Drawing ------------------------------------------------------------------

def shape_svg(shape: str, colour: str, extra: str = "") -> str:
    c = CANVAS / 2
    if shape == "circle":
        return f'<circle cx="{c:g}" cy="{c:g}" r="{SHAPE_RADIUS}" fill="{colour}"{extra}/>'
    # A superellipse: rounder than a rounded rectangle, with no flat-to-curve joint.
    points = []
    for i in range(96):
        t = 2 * math.pi * i / 96
        x = c + SHAPE_RADIUS * math.copysign(abs(math.cos(t)) ** 0.5, math.cos(t))
        y = c + SHAPE_RADIUS * math.copysign(abs(math.sin(t)) ** 0.5, math.sin(t))
        points.append(f"{x:.2f},{y:.2f}")
    return f'<path d="M{" L".join(points)}Z" fill="{colour}"{extra}/>'


def is_paint(value: str) -> bool:
    return value.strip().lower() not in ("", "none", "transparent", "inherit")


def recolour_style(style: str, colour: str) -> str:
    out = []
    for declaration in style.split(";"):
        if ":" not in declaration:
            continue
        key, value = (part.strip() for part in declaration.split(":", 1))
        if key in ("fill", "stroke", "color", "stop-color") and is_paint(value):
            value = colour
        out.append(f"{key}:{value}")
    return ";".join(out)


def recolour(element: ET.Element, colour: str) -> None:
    """Every source paints differently: Breeze through currentColor
    and a stylesheet, GNOME's symbolic icons with fixed colours or none at all.
    Writing the colour on each element covers the three."""
    for el in element.iter():
        for key in list(el.attrib):
            if key.startswith("{") and not key.startswith(f"{{{SVG_NS}}}") and "xlink" not in key:
                del el.attrib[key]  # editor metadata
        el.attrib.pop("class", None)
        for key in ("fill", "stroke", "color", "stop-color"):
            if key in el.attrib and is_paint(el.attrib[key]):
                el.set(key, colour)
        if "style" in el.attrib:
            el.set("style", recolour_style(el.attrib["style"], colour))


def number(value: str | None, default: float) -> float:
    match = re.match(r"\s*([0-9.]+)", value or "")
    return float(match.group(1)) if match else default


SHAPES = ("path", "rect", "circle", "ellipse", "polygon", "polyline", "line")


def to_outline(root: ET.Element, colour: str) -> None:
    """Turn filled shapes into their contour, so a solid mark sits next to line
    glyphs without looking heavier."""
    for el in root.iter():
        if not isinstance(el.tag, str) or el.tag.rsplit("}", 1)[-1] not in SHAPES:
            continue
        style = {k.strip(): v.strip() for k, v in
                 (d.split(":", 1) for d in el.attrib.pop("style", "").split(";") if ":" in d)}
        fill = style.pop("fill", el.get("fill", colour))
        style.pop("stroke", None)
        if not is_paint(fill):
            continue  # an invisible spacer stays invisible
        el.set("fill", "none")
        el.set("stroke", colour)
        if style:
            el.set("style", ";".join(f"{k}:{v}" for k, v in style.items()))


def thin(root: ET.Element, background: str, width: float) -> None:
    """Breeze draws its lines as filled shapes one unit wide, which come out
    heavier than the line glyphs. A stroke in the background colour covers the
    edge of each shape from both sides and leaves the line thinner."""
    for el in root.iter():
        if not isinstance(el.tag, str) or el.tag.rsplit("}", 1)[-1] not in SHAPES:
            continue
        style = el.get("style", "")
        if is_paint(el.get("stroke", "")) or re.search(r"stroke\s*:\s*(?!none)", style):
            continue  # already a drawn line
        if not is_paint(el.get("fill", "x")) or re.search(r"fill\s*:\s*none", style):
            continue
        # A "stroke:none" in the style would win over the attributes set here.
        kept = [d for d in style.split(";") if d.strip() and not d.strip().startswith("stroke")]
        if kept:
            el.set("style", ";".join(kept))
        else:
            el.attrib.pop("style", None)
        el.set("stroke", background)
        el.set("stroke-width", f"{width:.3g}")
        el.set("data-thin", "1")


def edges_only(root: ET.Element) -> None:
    """Keep only the strokes that thin() added, for a layer that is drawn over
    the glyph in the colour of whatever lies behind it."""
    for el in root.iter():
        if not isinstance(el.tag, str) or el.tag.rsplit("}", 1)[-1] not in SHAPES:
            continue
        if el.get("data-thin"):
            el.set("fill", "none")
            el.attrib.pop("style", None)  # a "fill:" in it would win over the attribute
            del el.attrib["data-thin"]
        else:
            el.set("fill", "none")
            el.set("stroke", "none")
            el.attrib.pop("style", None)


SHAPES = ("path", "circle", "ellipse", "rect", "line", "polygon", "polyline")


def faint_layer(body: str, inherited: str, amount: float) -> tuple[str, str]:
    """Return the body and the attributes that draw it at this opacity.

    The plain answer is opacity on the group, but Qt draws such a group through a
    buffer, and System Settings' icon page, which paints into a scaled viewport,
    puts that buffer in the wrong place and size. fill-opacity and stroke-opacity
    have no buffer, but shapes that overlap would add up. So they are used only
    where the picture is the same: one shape with one paint, or lines that can be
    joined into one path. Anything else keeps opacity."""
    group = f' opacity="{amount}"'
    try:
        root = ET.fromstring(f'<g xmlns="{SVG_NS}">{body}</g>')
    except ET.ParseError:
        return body, group

    def declared(el: ET.Element, key: str) -> str | None:
        found = re.search(rf"(?:^|;)\s*{key}\s*:\s*([^;]+)", el.get("style", ""))
        return found.group(1).strip() if found else el.get(key)

    def paint(el: ET.Element, key: str, default: str) -> str:
        found = re.search(rf' {key}="([^"]*)"', inherited)
        return declared(el, key) or (found.group(1) if found else default)

    for el in root.iter():
        if any(declared(el, key) not in (None, "1", "1.0") for key in ("opacity", "fill-opacity", "stroke-opacity")):
            return body, group  # it already mixes opacities of its own
    shapes = [el for el in root.iter() if el.tag.rsplit("}", 1)[-1] in SHAPES]
    drawn = [(el, paint(el, "fill", "black") != "none", paint(el, "stroke", "none") != "none") for el in shapes]
    drawn = [entry for entry in drawn if entry[1] or entry[2]]
    for el in root.iter():  # a declared 1 would override what the group sets
        if el.get("style"):
            el.set("style", re.sub(r"(?:^|(?<=;))\s*(?:fill-|stroke-)?opacity\s*:[^;]*;?", "", el.get("style")))
        for key in ("opacity", "fill-opacity", "stroke-opacity"):
            el.attrib.pop(key, None)
    flat = f' fill-opacity="{amount}" stroke-opacity="{amount}"'
    if len(drawn) == 1 and not (drawn[0][1] and drawn[0][2]):
        return "".join(ET.tostring(child, encoding="unicode") for child in root), flat
    lines = [el for el, filled, stroked in drawn if stroked and not filled]
    plain = all(el in list(root) and el.tag.rsplit("}", 1)[-1] == "path" and set(el.attrib) <= {"d", "fill", "stroke"}
                and el.get("d", "").lstrip().startswith("M") for el in lines)
    if drawn and len(lines) == len(drawn) and plain:
        # One path is stroked as one figure, so where its lines meet nothing adds up
        return f'<path d="{escape(" ".join(el.get("d") for el in lines), quote=True)}"/>', flat
    return body, group


def glyph_svg(path: Path, colour: str, canvas: float, size: float, extra: str = "",
              outline: bool = False, background: str | None = None, edges: bool = False,
              fade: float | None = None) -> str:
    root = ET.parse(path).getroot()
    box = [float(v) for v in re.split(r"[ ,]+", (root.get("viewBox") or "").strip()) if v]
    if len(box) != 4:
        box = [0, 0, number(root.get("width"), 22), number(root.get("height"), 22)]
    min_x, min_y, width, height = box
    # Breeze keeps its own colour stylesheet inside <defs>. Left in, it would
    # compete with the one this icon declares.
    for parent in list(root.iter()):
        for child in list(parent):
            if not isinstance(child.tag, str):
                continue
            # Breeze also marks its 22-unit box with a rectangle that is all but
            # transparent, sometimes outside the drawing. Stacked layers would show it.
            faint = [child.get("opacity"), *re.findall(r"(?:^|;)\s*opacity\s*:\s*([0-9.]+)",
                                                         child.get("style", ""))]
            if child.tag.rsplit("}", 1)[-1] == "style" or any(v and float(v) < 0.05 for v in faint):
                parent.remove(child)
    recolour(root, colour)
    if path.stem.endswith("-line"):
        # Every line glyph gets the same width, whatever its collection chose.
        root.attrib.pop("stroke-width", None)
    if outline:
        to_outline(root, colour)
        root.set("fill", "none")
        root.set("stroke-linejoin", "round")
        root.attrib.pop("stroke-width", None)

    skip = ("style", "metadata", "namedview", "title", "desc")
    body = "".join(
        ET.tostring(child, encoding="unicode")
        for child in root
        if isinstance(child.tag, str) and child.tag.rsplit("}", 1)[-1] not in skip
    )
    # Shapes with no fill of their own take the root's, which Breeze sets to "none".
    inherited = "".join(f' {key}="{escape(root.get(key), quote=True)}"'
                        for key in ("fill", "stroke", "style", "stroke-width", "stroke-linecap",
                                    "stroke-linejoin") if root.get(key))
    if "fill=" not in inherited:
        inherited += f' fill="{colour}"'

    # A transform, not a nested <svg>: Qt's renderer, which Plasma uses, skips those.
    scale = size / max(width, height)
    if edges and not (background and LINE_WIDTH < scale):
        return ""  # nothing to thin, so this layer has nothing to draw
    if background and LINE_WIDTH < scale:
        thin(root, background, 1 - LINE_WIDTH / scale)
        if edges:
            edges_only(root)
        for el in root.iter():
            el.attrib.pop("data-thin", None)
        body = "".join(
            ET.tostring(child, encoding="unicode")
            for child in root
            if isinstance(child.tag, str) and child.tag.rsplit("}", 1)[-1] not in skip
        )
    if "stroke-width" not in inherited and "stroke-width" not in body and "stroke=" in body + inherited:
        # Line sets draw hairlines for large sizes; keep them readable in a panel.
        inherited += f' stroke-width="{LINE_WIDTH * canvas / CANVAS / scale:.3g}"'
    x = (canvas - width * scale) / 2 - min_x * scale
    y = (canvas - height * scale) / 2 - min_y * scale
    if fade is not None:
        body, attributes = faint_layer(body, inherited, fade)
        extra += attributes
    return f'<g transform="translate({x:g},{y:g}) scale({scale:g})"{extra}{inherited}>{body}</g>'


def letter_svg(letter: str, colour: str, canvas: float, extra: str = "") -> str:
    # The baseline is placed by hand: Qt's renderer has no dominant-baseline.
    size = canvas * 0.47
    return (f'<text x="{canvas / 2:g}" y="{canvas / 2 + size * 0.35:g}" '
            f'font-family="Inter, Noto Sans, sans-serif" font-size="{size:g}" font-weight="600" '
            f'text-anchor="middle" fill="{colour}"{extra}>{escape(letter)}</text>')


def drawing(glyph: Glyph, colour: str, canvas: float, size: float, extra: str = "",
            background: str | None = None, edges: bool = False, fade: float | None = None) -> str:
    if glyph.path:
        try:
            return glyph_svg(glyph.path, colour, canvas, size, extra, glyph.outline, background, edges, fade)
        except (ET.ParseError, OSError) as error:
            print(f"warning: cannot read {glyph.path}: {error}", file=sys.stderr)
    if fade is not None:
        extra += f' fill-opacity="{fade}"'
    return letter_svg(glyph.detail[:1].upper(), colour, canvas, extra)


# Colours a page shows when nothing rewrites the stylesheet, per variant:
# text, background and accent. Plasma replaces all three with the colour
# scheme's, so one drawing serves any scheme and accent.
FALLBACK = {
    "dark": ("#fcfcfc", "#0b0d14", "#00b09a"),
    "light": ("#232629", "#f4f5f7", "#00b09a"),
}
# How much accent the shape takes. On a light scheme a faint wash is lost
# against a light panel, so it takes more and gets an edge in the accent.
# On the dark one, 0.16 left the shape hardly apart from the panel.
TINT = {"dark": 0.4, "light": 0.6}
# The edge keeps the shape apart from a highlight behind it: at 0.4 the dark
# shape is the color Plasma gives a hovered or selected item.
EDGE = {"dark": 1.0, "light": 0.85}
# How much the glyph moves from the accent towards the text colour. A light
# scheme needs more, or a pale accent such as yellow disappears on the shape.
# On the dark one the glyph is the text colour outright: Plasma paints the accent of an
# icon with the selection's dark shade, which is nearly the shape's own colour.
SHADE = {"dark": 1.0, "light": 0.8}
# Dark lines on a light shape look thinner than light lines on a dark one.
LINE_SCALE = {"dark": 1.0, "light": 1.3}


def scheme_style(variant: str) -> str:
    text, background, accent = FALLBACK[variant]
    return ('<style type="text/css" id="current-color-scheme">'
            f'.ColorScheme-Text{{color:{text};}}.ColorScheme-Background{{color:{background};}}'
            f'.ColorScheme-Accent{{color:{accent};}}</style>')


def icon_body(glyph: Glyph, shape: str, background: str, colour: str, accent: bool = False,
              variant: str = "dark") -> str:
    # A contour reads lighter than a solid mark, so it can use the whole box.
    size = GLYPH_SIZE * glyph.scale * (BLEED_SCALE if glyph.full_bleed and not glyph.outline else 1)
    # Only glyphs on Breeze's 22-unit grid are thinned: brand marks and
    # applications' own symbols are solid figures, not lines.
    on_grid = (glyph.path is not None and glyph.source in ("alias", "breeze", "generic")
               and not glyph.full_bleed and not glyph.outline and not glyph.path.stem.endswith("-line"))
    if not accent:
        return shape_svg(shape, background) + drawing(
            glyph, colour, CANVAS, size, background=background if on_grid else None)

    # Everything is painted through the colour scheme's classes: the shape in
    # the background colour with a wash of accent, and on it the glyph in the
    # accent, pushed towards the text colour so that it stands out on light
    # and on dark.
    def layer(css: str, attributes: str = "", **options) -> str:
        return drawing(glyph, "currentColor", CANVAS, size,
                       f' class="ColorScheme-{css}"{attributes}', **options)

    # The shape is one path, so fill-opacity and stroke-opacity give the same
    # picture as opacity. They are used because Qt draws an element that has
    # opacity through a buffer, and System Settings' icon page, which paints
    # into a scaled viewport, puts that buffer in the wrong place and size.
    # The glyph layers go through faint_layer, for the same reason.
    parts = [
        scheme_style(variant),
        shape_svg(shape, "currentColor", ' class="ColorScheme-Background"'),
        shape_svg(shape, "currentColor", f' class="ColorScheme-Accent" fill-opacity="{TINT[variant]}"'),
        layer("Accent"),
        layer("Text", fade=SHADE[variant]),
    ]
    if on_grid:
        # The thinning strokes repeat the two coats of the shape they cover.
        parts.append(layer("Background", background="currentColor", edges=True))
        parts.append(layer("Accent", background="currentColor", edges=True, fade=TINT[variant]))
    if EDGE[variant]:
        parts.append(shape_svg(shape, "none", f' class="ColorScheme-Accent" stroke="currentColor" '
                                              f'stroke-width="1" stroke-opacity="{EDGE[variant]}"'))
    return "".join(parts)


def small_body(glyph: Glyph) -> str:
    """The glyph with no shape, written as "<icon>-symbolic". Tray items ask for
    that name, and without it Plasma falls back to "<icon>" in this theme, shape
    included, before it looks at Breeze. Plasma rewrites this stylesheet, so the
    glyph follows the colour scheme like Breeze's own tray icons."""
    size = SMALL * (0.8 if glyph.full_bleed or not glyph.path else 1)
    return ('<style type="text/css" id="current-color-scheme">.ColorScheme-Text{color:#fcfcfc;}</style>'
            + drawing(glyph, "currentColor", SMALL, size, ' class="ColorScheme-Text"'))


def svg_document(body: str, width: float, height: float) -> str:
    return (f'<svg xmlns="{SVG_NS}" xmlns:xlink="http://www.w3.org/1999/xlink" '
            f'width="{width:g}" height="{height:g}" viewBox="0 0 {width:g} {height:g}">{body}</svg>\n')


THEMES = {  # variant: directory, name, themes to inherit from
    "dark": ("katze-mono", "Katze Mono", "breeze-dark,breeze,hicolor"),
    "light": ("katze-mono-light", "Katze Mono Light", "breeze,hicolor"),
}

INDEX_THEME = """\
[Icon Theme]
Name={name}
Comment=One-colour application icons, generated by katze-mono.py
Inherits={inherits}
FollowsColorScheme=true
Directories=apps/symbolic,apps/scalable

[apps/symbolic]
Size=22
MinSize=8
MaxSize=512
Context=Applications
Type=Scalable

[apps/scalable]
Size=64
MinSize=32
MaxSize=512
Context=Applications
Type=Scalable
"""

# Small, an icon sits in a menu, a side panel or a title bar, among Breeze's
# line icons, and the shape is a blot with a glyph too small to read. Below
# 32 px every icon is the glyph alone, in the text colour.
PLAIN_DIRECTORY = "apps/22"
PLAIN_SECTION = """
[apps/22]
Size=22
MinSize=8
MaxSize=31
Context=Applications
Type=Scalable
"""


def pass_through(output: Path, names: set[str], roots: list[Path],
                 parent: str = "breeze-dark") -> tuple[str, list[str]]:
    """Plasma shortens a name it cannot find ("preferences-system-bluetooth" to
    "preferences-system") inside this theme before it asks Breeze, so an icon
    written here would replace every Breeze icon named after it. Link those
    icons into this theme, in directories declared like Breeze's, and return
    the lines to add to index.theme."""
    for old in output.rglob("*"):
        if old.is_symlink():
            old.unlink()
    base = next((r / t for t in dict.fromkeys((parent, "breeze-dark", "breeze")) for r in roots
                 if (r / t / "index.theme").is_file()), None)
    if base is None:
        return "", []
    index = configparser.RawConfigParser(strict=False, interpolation=None)
    index.optionxform = str
    index.read(base / "index.theme", encoding="utf-8")

    sections: dict[str, str] = {}
    for file in base.glob("*/*/*.svg"):
        stem = file.stem
        if not any(stem.startswith(f"{name}-") and stem != f"{name}-symbolic" for name in names):
            continue
        directory = str(file.parent.relative_to(base))
        if not index.has_section(directory):
            continue
        target = output / "breeze" / directory
        target.mkdir(parents=True, exist_ok=True)
        (target / file.name).symlink_to(file.resolve())
        sections[f"breeze/{directory}"] = "".join(f"{k}={v}\n" for k, v in index.items(directory))
    return "".join(f"\n[{directory}]\n{body}" for directory, body in sorted(sections.items())), list(sorted(sections))


def other_copies(output: Path, roots: list[Path], have: list[str]) -> tuple[str, list[str]]:
    """This theme can be installed twice: with the image, in /usr/share/icons, and
    in the home directory, with the user's own applications. Plasma reads the
    files of both but only the index.theme of the first, the home's. A directory
    that only the other copy declares, such as the Breeze icons it links or its
    small icons, would not be searched, and "folder-documents" would be shortened
    to this theme's "folder". Return those sections, to declare them here too."""
    sections: dict[str, str] = {}
    for root in roots:
        index_file = root / output.name / "index.theme"
        if not index_file.is_file() or index_file.resolve() == (output / "index.theme").resolve():
            continue
        index = configparser.RawConfigParser(strict=False, interpolation=None)
        index.optionxform = str
        try:
            index.read(index_file, encoding="utf-8")
        except (configparser.Error, OSError):
            continue
        for directory in index.sections():
            if directory.startswith("breeze/") and directory not in have:
                sections.setdefault(directory, "".join(f"{k}={v}\n" for k, v in index.items(directory)))
    return "".join(f"\n[{d}]\n{body}" for d, body in sorted(sections.items())), sorted(sections)


# --- Commands -----------------------------------------------------------------

def print_report(rows: list[tuple[App, Glyph]], only: str | None, roots: list[Path], own: Path) -> None:
    counts = Counter(g.source for _, g in rows)
    shown = [(a, g) for a, g in rows if only in (None, g.source)]

    width = min(max((len(a.name) for a, _ in shown), default=4), 32)
    for a, g in shown:
        note = "  (absolute Icon= path)" if a.icon.startswith("/") else ""
        print(f"{g.source:8} {a.name[:width]:{width}}  {a.icon}  ->  {g.detail}{note}")

    print(f"\n{len(rows)} applications")
    for source in SOURCES:
        n = counts[source]
        print(f"  {source:8} {n:3}  {n * 100 // max(len(rows), 1):3}%")
    if not own.is_dir():
        print(f"No own glyphs yet: {own} does not exist.")


def write_sheet(path: Path, rows: list[tuple[App, Glyph]], args) -> None:
    columns, cell_w, cell_h = 8, 132, 112
    light = args.follow_accent and args.variant == "light"
    name_colour, source_colour = ("#232629", "#7f8c8d") if light else ("#c8d0d8", "#6c7a89")
    cells = []
    for i, (app, glyph) in enumerate(rows):
        x, y = (i % columns) * cell_w, (i // columns) * cell_h
        body = icon_body(glyph, args.shape, args.background, args.glyph_colour, args.follow_accent,
                         args.variant)
        cells.append(
            f'<g transform="translate({x + (cell_w - CANVAS) / 2:g},{y + 10})">{body}</g>'
            f'<text x="{x + cell_w / 2:g}" y="{y + 90}" font-family="sans-serif" font-size="11" '
            f'text-anchor="middle" fill="{name_colour}">{escape(app.name[:19])}</text>'
            f'<text x="{x + cell_w / 2:g}" y="{y + 103}" font-family="sans-serif" font-size="9" '
            f'text-anchor="middle" fill="{source_colour}">{glyph.source}</text>'
        )
    width = columns * cell_w
    height = math.ceil(len(rows) / columns) * cell_h
    background = f'<rect width="{width}" height="{height}" fill="{"#e6e8eb" if light else "#000000"}"/>'
    path.write_text(svg_document(background + "".join(cells), width, height), encoding="utf-8")
    print(f"Wrote {path}")


def write_theme(output: Path, rows: list[tuple[App, Glyph]], args, roots: list[Path]) -> None:
    icons = output / "apps/scalable"
    small = output / "apps/symbolic"
    plain = output / PLAIN_DIRECTORY
    plain.mkdir(parents=True, exist_ok=True)
    icons.mkdir(parents=True, exist_ok=True)
    small.mkdir(parents=True, exist_ok=True)
    written: set[str] = set()
    skipped = []
    for app, glyph in rows:
        if "/" in app.icon:
            # A theme cannot replace a path, and a relative one ("../x") would be
            # written outside this theme
            skipped.append(app.name)
            continue
        if app.icon in written:
            continue  # several launchers share the icon; the first decides
        body = icon_body(glyph, args.shape, args.background, args.glyph_colour, args.follow_accent,
                         args.variant)
        try:
            (icons / f"{app.icon}.svg").write_text(svg_document(body, CANVAS, CANVAS), encoding="utf-8")
            (small / f"{app.icon}-symbolic.svg").write_text(svg_document(small_body(glyph), SMALL, SMALL),
                                                            encoding="utf-8")
        except OSError as error:
            # One launcher with an odd name must not cost every other icon
            print(f"warning: no icon for {app.name}: {error}", file=sys.stderr)
            continue
        written.add(app.icon)
        (plain / f"{app.icon}.svg").write_text(svg_document(small_body(glyph), SMALL, SMALL), encoding="utf-8")
    # Remove icons of applications that are gone, so reruns do not pile up.
    for old in [*icons.glob("*.svg"), *small.glob("*.svg")]:
        if old.stem.removesuffix("-symbolic") not in written:
            old.unlink()
    for old in plain.glob("*.svg"):
        if old.stem not in written:
            old.unlink()
    for stale in (output / "apps/small", output / "places/22"):  # earlier layouts of this theme
        if stale.is_dir():
            for old in stale.glob("*.svg"):
                old.unlink()
            stale.rmdir()
    _, name, inherits = THEMES[args.variant]
    extra, directories = pass_through(output, written, roots, inherits.split(",")[0])
    extra = PLAIN_SECTION + extra
    directories = [PLAIN_DIRECTORY, *directories]
    more, more_directories = other_copies(output, roots, directories)
    extra += more
    directories += more_directories
    index = INDEX_THEME.format(name=name, inherits=inherits).replace("Directories=apps/symbolic,apps/scalable",
                                ",".join(["Directories=apps/symbolic,apps/scalable", *directories]))
    (output / "index.theme").write_text(index + extra, encoding="utf-8")
    # Plasma keeps drawn icons until the theme directory's date changes, and
    # rewriting a file in place does not change it.
    for directory in (icons, small, output):
        os.utime(directory)

    print(f"Wrote {len(written)} icons to {output}")
    if skipped:
        print("Not themed, because their launcher names an icon file: " + ", ".join(skipped))


def main() -> int:
    # The glyphs and choices live in /usr/share/katze/katze-mono; the same
    # relative path finds them in the repository.
    here = Path(__file__).resolve().parents[2] / "share/katze/katze-mono"
    data_home = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))

    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--report", action="store_true",
                        help="list the glyph source of every application and write no theme")
    parser.add_argument("--only", choices=SOURCES,
                        help="with --report, list only applications that use this source")
    parser.add_argument("--sheet", type=Path, metavar="FILE.svg",
                        help="write one picture with every icon and write no theme")
    parser.add_argument("--output", type=Path,
                        help="theme directory (default: ~/.local/share/icons/katze-mono, "
                             "or katze-mono-light for the light variant)")
    parser.add_argument("--shape", choices=("circle", "squircle"), default="squircle")
    parser.add_argument("--background", default="#12233a", help="shape colour (default: %(default)s)")
    parser.add_argument("--glyph-colour", default="#8ab4d8", help="glyph colour (default: %(default)s)")
    parser.add_argument("--follow-accent", action="store_true",
                        help="let Plasma paint the icons with its colour scheme and accent")
    parser.add_argument("--variant", choices=tuple(FALLBACK), default="dark",
                        help="with --follow-accent: which Breeze to inherit from, and the "
                             "colours shown outside Plasma (default: %(default)s)")
    parser.add_argument("--glyphs", type=Path, default=here / "glyphs",
                        help="directory of hand-drawn glyphs, as <icon>.svg (default: %(default)s)")
    parser.add_argument("--aliases", type=Path, default=here / "aliases.toml",
                        help="table of application icon to glyph name (default: %(default)s)")
    parser.add_argument("--all-aliases", action="store_true",
                        help="also write an icon for every alias, installed or not: for a theme "
                             "built before the applications arrive, such as Flatpaks")
    args = parser.parse_args()

    aliases: dict[str, str] = {}
    skip: set[str] = set()
    outlined: set[str] = set()
    scales: dict[str, float] = {}
    if args.aliases.is_file():
        with args.aliases.open("rb") as f:
            table = tomllib.load(f)
        aliases = table.get("aliases", {})
        skip = set(table.get("skip", {}).get("icons", []))
        outlined = set(table.get("outline", {}).get("glyphs", []))
        scales = table.get("scale", {})

    dirs = data_dirs()
    roots = icon_roots(dirs)
    apps = visible_apps(dirs)
    if args.all_aliases:
        seen = {app.icon for app in apps} | {app.desktop_id.removesuffix(".desktop") for app in apps}
        apps += [App(f"{name}.desktop", name, name, []) for name in aliases
                 if name not in seen and "/" not in name and " " not in name]
    if args.follow_accent:
        global LINE_WIDTH
        LINE_WIDTH *= LINE_SCALE[args.variant]
    rows = [(app, find_glyph(app, roots, args.glyphs, aliases, outlined, scales))
            for app in apps if app.icon not in skip]

    if args.report:
        print_report(rows, args.only, roots, args.glyphs)
    if args.sheet:
        write_sheet(args.sheet, rows, args)
    if not args.report and not args.sheet:
        write_theme(args.output or data_home / "icons" / THEMES[args.variant][0], rows, args, roots)
    return 0


if __name__ == "__main__":
    sys.exit(main())
