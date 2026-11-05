#!/usr/bin/env bash
# zsh + Starship + JetBrainsMono Nerd Font + Konsole/Yakuake defaults.
# Starship and the font are not in Fedora's repos: pinned GitHub releases, checked by sha256.
# To update one, change its version and checksum here.
set -euxo pipefail

STARSHIP_VERSION=1.27.0
STARSHIP_SHA256=3b94758850901717eb36aa1b53f8492c1322506ec6d41273bc6151e79ed8e4a1
NERD_FONTS_VERSION=3.5.1
JETBRAINS_SHA256=04d5e8f903693f9dd13e16f867e994834e681eb3c72c0d337a770dcda09010cf

work=$(mktemp -d)

# Starship
curl -fsSL --retry 3 -o "$work/starship.tar.gz" \
  "https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-x86_64-unknown-linux-gnu.tar.gz"
echo "${STARSHIP_SHA256}  $work/starship.tar.gz" | sha256sum -c -
tar -xzf "$work/starship.tar.gz" -C "$work" starship
install -m 0755 "$work/starship" /usr/bin/starship

# Font: only the four monospace styles a terminal uses
curl -fsSL --retry 3 -o "$work/font.tar.xz" \
  "https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERD_FONTS_VERSION}/JetBrainsMono.tar.xz"
echo "${JETBRAINS_SHA256}  $work/font.tar.xz" | sha256sum -c -
fontdir=/usr/share/fonts/jetbrains-mono-nerd
mkdir -p "$fontdir"
tar -xJf "$work/font.tar.xz" -C "$fontdir" --no-same-owner OFL.txt \
  JetBrainsMonoNerdFontMono-Regular.ttf \
  JetBrainsMonoNerdFontMono-Bold.ttf \
  JetBrainsMonoNerdFontMono-Italic.ttf \
  JetBrainsMonoNerdFontMono-BoldItalic.ttf
chmod 0644 "$fontdir"/*

rm -rf "$work"

# zsh: load our defaults, and skip the first-run wizard for users without a ~/.zshrc
echo 'source /usr/share/bootc-images/zshrc' >> /etc/zshrc
cat >> /etc/zshenv <<'ZSHENV'
[[ -o interactive && ! -e "${ZDOTDIR:-$HOME}/.zshrc" ]] && touch "${ZDOTDIR:-$HOME}/.zshrc"
ZSHENV

# New users get zsh. Konsole and Yakuake open zsh for everyone through the profile.
sed -i 's|^SHELL=.*|SHELL=/usr/bin/zsh|' /etc/default/useradd
printf '\n[Desktop Entry]\nDefaultProfile=bootc-images.profile\n' >> /etc/xdg/konsolerc

# Yakuake starts with the session (F12 opens it)
mkdir -p /etc/xdg/autostart
cp /usr/share/applications/org.kde.yakuake.desktop /etc/xdg/autostart/
