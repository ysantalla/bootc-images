# Breeze Dark Custom

A KDE Plasma 6 desktop theme based on **Breeze Dark**, with visual modifications to the taskbar widgets.

## Where it lives

This theme is part of the `bootc-images` base image, which installs it in `/usr/share/plasma/desktoptheme/` and makes it the default for new users. The color scheme is next to it in the image, in `/usr/share/color-schemes/BreezeDarkCustom.colors`.

To try a change without building an image, copy this folder to `~/.local/share/plasma/desktoptheme/` and run `plasma-apply-desktoptheme breeze-custom`. The folder name is the theme ID, so keep it matching the `Id` in `metadata.json`.

## File structure

```
breeze-custom/
├── colors          # Color palette (based on stock Breeze Dark)
├── plasmarc        # Shell visual effects (contrast, saturation, transparency)
├── metadata.json   # Theme metadata (ID: breeze-custom)
└── widgets/
    ├── tasks.svgz  # Taskbar indicators (customized)
    └── clock.svg   # Clock widget
```

Any widget not present in the `widgets/` folder is automatically inherited from the system **Breeze Dark** theme.

## Customized widgets

### tasks.svgz

Visual indicators for the taskbar (active window, hover, minimized, etc.).

Indicator colors follow the active system color scheme (including the accent
color) via Plasma's stylesheet mechanism: elements use `fill:currentColor`
plus a `ColorScheme-*` class, and Plasma rewrites the embedded
`<style id="current-color-scheme">` block at load time.

| Role                        | Class                         | Breeze Dark fallback |
|-----------------------------|-------------------------------|----------------------|
| Focus / progress / active   | `ColorScheme-ButtonFocus`     | `#3daee9`            |
| Hover / focus glow          | `ColorScheme-ButtonHover`     | `#93cee9`            |
| Attention                   | `ColorScheme-NeutralText`     | `#f67400`            |
| Normal / minimized (mono)   | `ColorScheme-Text` + opacity  | `#eff0f1`            |
| Group expander chip         | `ColorScheme-Highlight`       | `#3daee9`            |
| Group expander dots         | `ColorScheme-HighlightedText` | `#fcfcfc`            |

## Editing SVG widgets

`.svgz` files are gzip-compressed SVGs. To edit them:

```bash
# Decompress
zcat widgets/tasks.svgz > /tmp/tasks.svg

# Edit /tmp/tasks.svg with a text editor or Inkscape

# Recompress
gzip -9 -c /tmp/tasks.svg > widgets/tasks.svgz

# Apply changes
plasma-apply-desktoptheme breeze-custom
```

## Breeze Dark color reference

| Role           | RGB            | Hex       |
|----------------|----------------|-----------|
| Window bg      | 32, 35, 38     | `#202326` |
| View bg        | 20, 22, 24     | `#141618` |
| Text           | 252, 252, 252  | `#fcfcfc` |
| Accent (link)  | 29, 153, 243   | `#1d99f3` |
| Positive       | 39, 174, 96    | `#27ae60` |
| Negative       | 218, 68, 83    | `#da4453` |
| Neutral        | 246, 116, 0    | `#f67400` |
| Visited        | 155, 89, 182   | `#9b59b6` |

## Resources

- [Plasma Theme Development — KDE Docs](https://develop.kde.org/docs/plasma/theme/)
- [Plasma SVG element IDs](https://develop.kde.org/docs/plasma/theme/theme-elements/)
