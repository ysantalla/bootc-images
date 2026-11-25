#!/usr/bin/env bash
# Gets the speech model for voice dictation (790 MB), once for each user, and compiles it.
#   dictation-setup.sh          keeps the device in use (the NPU, unless it was changed)
#   dictation-setup.sh gpu      transcribes on the GPU from now on
#   dictation-setup.sh npu      back to the NPU
# Run it without sudo. Nothing that is said leaves the machine: only this downloads something.
set -euo pipefail

repository=OpenVINO/whisper-large-v3-turbo-int8-ov
revision=b568445dd5dc8c695bde596f8acbb4694fd6ba64
dir=${XDG_DATA_HOME:-$HOME/.local/share}/voxtype/models/openvino-whisper-large-v3-turbo-int8-ov

[[ $EUID != 0 ]] || { echo "Run it without sudo" >&2; exit 1; }

system=/etc/voxtype/config.toml
config=${XDG_CONFIG_HOME:-$HOME/.config}/voxtype/config.toml
case ${1-} in
"") ;;
npu | gpu)
  if [[ ! -e $config ]]; then
    mkdir -p "$(dirname "$config")"
    { echo "# A copy of $system, for this user"; cat "$system"; } > "$config"
  fi
  sed -i '/^\[openvino\]/,/^\[output\]/ s/^device = .*/device = "'"${1^^}"'"/' "$config"
  grep -qx "device = \"${1^^}\"" "$config" || { echo "No device line in [openvino] of $config: change it by hand" >&2; exit 1; }
  ;;
*) echo "usage: dictation-setup.sh [npu|gpu]" >&2; exit 2 ;;
esac

files() { # sha256 and name
  cat <<'LIST'
3c51f66c4c21f9e126970078f11ae77a78c74aee8df606ee9daba86e467108e0 added_tokens.json
bfd92c097547ab12cb42abae8008be5a59a91fdc5ab39acce24489eb8a3e8a86 config.json
4617fcca458af3b91a103143aaac919c1ab6680b552d7abd10811b7248bd77b4 generation_config.json
2df2990a395e35e8dfbc7511e08c12d56018d8d04691e0133e5d63b21e154dc6 merges.txt
bf1c507dc8724ca9cf9903640dacfb69dae2f00edee4f21ceba106a7392f26dd normalizer.json
9da38e88cec069ad54699d627f1c59d36c36a3dfb54b5e1bb5cfdf5832efaf03 openvino_config.json
c064991cbafc4381567d29972b7013dc24026de9c326d03eb1e6e4fc44aa959f openvino_decoder_model.bin
aeb09fafbf1c0cbf84baf30f46763436005822faf3b365359b8de0aa04f03047 openvino_decoder_model.xml
f2b3c47825a1089525ff65c0c8e49271e1dee69a401a04fc827ac2de5b7766e4 openvino_detokenizer.bin
6e106a14f14b0771b46b7948a99b1d819ff93b2455b7da8f47761ab9dba9dc56 openvino_detokenizer.xml
0590a8f35f96d57801c55990028d917821ac721026e34b7f3f59d7561fc908e6 openvino_encoder_model.bin
60713d4ed3a8ac8ee020e11c4737ec276d14cabc6a082537bddf2c00ba6ce070 openvino_encoder_model.xml
adfa3d9a2920d0f314121270a960ab331ec0f05838544bb8ecaaa422282a6fd4 openvino_tokenizer.bin
cba304e7bad54773b9d2cbccfbc8501117ecf2e3c0f4f5331742a0a3c9feed93 openvino_tokenizer.xml
654cf18d3e163b948ceaf9766da56ce0b52de265d58673cf61c9376f126bd499 preprocessor_config.json
baea4ea09372eb4fca86b4e4346139fd73cb807d5087e9de0948e971739c3e74 special_tokens_map.json
3c75940dfce3a294fca7041a5faff011677f1b68fa85e47511bb8cf6dccaded6 tokenizer_config.json
5c1bf30c9e716e1477bedef846b01be0013daecb89e9e3ef7ab89b23c178df1b tokenizer.json
6788c80b082e9b0d1393147d3a3e62ba19285ac0c82ace8e5ef00f37ead58971 vocab.json
LIST
}

mkdir -p "$dir"
# Last the file that the services look for, so they never see half a model
files | grep -v openvino_encoder_model.xml > "$dir/.files"
files | grep openvino_encoder_model.xml >> "$dir/.files"
while read -r sum name; do
  [[ -e $dir/$name ]] && echo "$sum  $dir/$name" | sha256sum --status -c - && continue
  echo "Downloading $name"
  curl -fL --retry 3 --progress-bar -o "$dir/.part" "https://huggingface.co/$repository/resolve/$revision/$name"
  echo "$sum  $dir/.part" | sha256sum --status -c - || { echo "$name is not the file that was expected" >&2; rm -f "$dir/.part"; exit 1; }
  mv "$dir/.part" "$dir/$name"
done < "$dir/.files"
rm -f "$dir/.files"

echo "Compiling it, the first time only: about two and a half minutes for the NPU, seconds for the GPU"
silence=$(mktemp --suffix=.wav)
trap 'rm -f "$silence"' EXIT
python3 -I -c '
import sys, wave
with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
    w.writeframes(bytes(64000))' "$silence"
LD_LIBRARY_PATH=/usr/lib/openvino-genai/runtime/lib/intel64 voxtype transcribe "$silence" > /dev/null

systemctl --user restart katze-ydotoold.service katze-dictation.service
echo "Ready. Meta+H starts dictating, and Meta+H again writes what you said."
