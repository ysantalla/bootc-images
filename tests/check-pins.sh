#!/usr/bin/env bash
# Lists the downloads that shell.sh and dictation.sh pin by version and checksum and that have a newer
# release. Nothing else watches them: Dependabot only knows the GitHub Actions.
# Prints one line per outdated pin, "<name> <pinned> <latest> <releases URL>", and nothing
# when all are current. Needs `gh`, logged in or with GH_TOKEN.
set -euo pipefail

cd "$(dirname "$0")/.."
scripts=(images/base/build_files/shell.sh images/xps16-da16260/build_files/dictation.sh)

pinned() { sed -n "s/^$1=//p" "${scripts[@]}"; }
latest() { gh api "repos/$1/releases/latest" --jq .tag_name | sed 's/^v//'; }

check() { # check <name> <variable in those scripts> <owner/repository>
  local have want
  have=$(pinned "$2")
  want=$(latest "$3")
  [[ -n $have && -n $want ]] || { echo "cannot compare $1: pinned '$have', latest '$want'" >&2; return 1; }
  if [[ $have != "$want" ]]; then
    echo "$1 $have $want https://github.com/$3/releases"
  fi
}

check Starship STARSHIP_VERSION starship/starship
check "Nerd Fonts" NERD_FONTS_VERSION ryanoasis/nerd-fonts
check Voxtype VOXTYPE_VERSION peteonrails/voxtype
check "OpenVINO GenAI" OPENVINO_VERSION openvinotoolkit/openvino.genai
