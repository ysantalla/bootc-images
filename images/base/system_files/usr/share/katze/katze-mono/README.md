# Katze Mono

An icon theme for Plasma, generated for the applications that are installed:
each one gets a thin line glyph on a dark rounded shape. Everything that is
not an application icon is inherited from Breeze.

The image is built with the icons of its own applications, in
`/usr/share/icons/katze-mono` and `katze-mono-light`. `katze-icons.service`
adds each user's own at login, in the same themes under
`~/.local/share/icons`. The script is `/usr/libexec/katze/katze-mono.py`.

```bash
python3 katze-mono.py --report            # which glyph each application gets, and from where
python3 katze-mono.py --sheet all.svg     # one picture with every icon
python3 katze-mono.py --follow-accent                   # dark theme, painted by the colour scheme
python3 katze-mono.py --follow-accent --variant light   # light theme, in katze-mono-light
/usr/libexec/plasma-changeicons katze-mono
```

Run it again after installing applications. Plasma keeps icons it has already
drawn, so log out and in, or restart `plasma-plasmashell.service`, to see a
regenerated theme. `/usr/libexec/plasma-changeicons breeze-dark` goes back.

## Design rules

- **One shape.** A squircle (or `--shape circle`) of 60 units on a 64 unit
  canvas, `#12233a`.
- **One colour.** `#8ab4d8` on `#12233a`, or the colour scheme's with
  `--follow-accent`: the shape is the scheme's background with a wash of the
  accent, and the glyph is the accent moved a little towards the text colour,
  more so on a light scheme. The same drawing serves any scheme and accent;
  the two variants only differ in which Breeze they inherit from and in the
  colours shown outside Plasma.
- **Lines, not fills.** Lines are 1.25 units wide (`LINE_WIDTH`). Line glyphs
  are drawn at that width whatever their collection uses, Breeze's filled
  lines are thinned to it, and solid marks listed under `[outline]` are drawn
  as their contour.
- **One size.** The glyph's box is 40 units (`GLYPH_SIZE`). `[scale]` corrects
  a glyph that looks small or large in it.
- **The application's own mark first.** A brand is drawn with its mark; a
  generic glyph is the last resort before the name's initial.

## Where a glyph comes from

In order: `aliases.toml`, a file in `glyphs/` named after the icon, Breeze's
`apps/22` symbolic icon, the application's own symbolic icon, a category
glyph, the initial.

`aliases.toml` is where the choices live: `[aliases]` points an application at
a glyph, `[outline]` lists solid glyphs to draw as contours, `[scale]` holds
size corrections and `[skip]` leaves an application with its original icon.
`glyphs/README.md` lists where the glyph files come from and their licences.

## What Plasma does with colours

- An icon theme is only repainted if its `index.theme` says
  `FollowsColorScheme=true`.
- Inside the panel and the launcher, the colours come from the Plasma style.
  A style that ships a `colors` file, as `breeze-custom` does, keeps its own
  blue whatever the accent is. The icons only follow the accent there with a
  Plasma style that has no `colors` file.
- After the accent changes, the panel keeps the icons it had drawn until
  `plasma-plasmashell.service` restarts.

## What Plasma does with names

- A tray item asks for `<icon>-symbolic`. The theme writes that name too, with
  the glyph alone in the text colour, or Plasma would fall back to `<icon>`
  and put the shape in the tray.
- Plasma shortens a name it cannot find (`preferences-system-bluetooth` to
  `preferences-system`) inside this theme before it asks Breeze. For every
  icon written here that Breeze has longer names for, the theme links
  Breeze's files under `breeze/`.
- Applications that draw their own tray icon (Slack sends a 22 px picture)
  cannot be themed.
- A launcher whose `Icon=` is a file path cannot be themed either; the script
  names them when it finishes.
