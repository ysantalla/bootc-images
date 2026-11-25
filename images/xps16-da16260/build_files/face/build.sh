#!/usr/bin/env bash
# Face unlock, in a build stage of its own, so the image gets no compiler and no OpenVINO headers:
# compiles katze-face against the OpenVINO GenAI SDK that dictation.sh puts in the image (same version and
# checksum, read from there), and fetches its two models, pinned by commit and sha256. Output in /out.
set -euxo pipefail

eval "$(grep -E '^OPENVINO_(VERSION|SHA256)=' /ctx/dictation.sh)"
: "${OPENVINO_VERSION:?}" "${OPENVINO_SHA256:?}"

# opencv_zoo: YuNet (MIT) finds the face, SFace (Apache 2.0) describes it
ZOO=https://github.com/opencv/opencv_zoo/raw/eb9f4f2d4b79b58e5513b5d25d5f0243a8357bf4/models
YUNET_SHA256=ebafce4e3c118d6554634be5c27ab333b4c047a9a8c3faf1d7cf93101c22f0f0
YUNET_LICENSE_SHA256=c83b8120c50ccbd4c4f96edf53141bdd566ebb8f8e9227e415326aa1b1aba958
SFACE_SHA256=0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79
SFACE_LICENSE_SHA256=cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30

work=$(mktemp -d)
mkdir -p /out/models /out/licenses

fetch() { # url sha256 destination
  curl -fsSL --retry 3 -o "$3" "$1"
  echo "$2  $3" | sha256sum -c -
}
fetch "$ZOO/face_detection_yunet/face_detection_yunet_2026may.onnx" "$YUNET_SHA256" /out/models/yunet.onnx
fetch "$ZOO/face_detection_yunet/LICENSE" "$YUNET_LICENSE_SHA256" /out/licenses/yunet-LICENSE
fetch "$ZOO/face_recognition_sface/face_recognition_sface_2021dec.onnx" "$SFACE_SHA256" /out/models/sface.onnx
fetch "$ZOO/face_recognition_sface/LICENSE" "$SFACE_LICENSE_SHA256" /out/licenses/sface-LICENSE

fetch "https://storage.openvinotoolkit.org/repositories/openvino_genai/packages/${OPENVINO_VERSION%.*}/linux/openvino_genai_ubuntu24_${OPENVINO_VERSION}_x86_64.tar.gz" \
  "$OPENVINO_SHA256" "$work/openvino.tar.gz"
mkdir "$work/sdk"
tar -xzf "$work/openvino.tar.gz" -C "$work/sdk" --strip-components=1 --no-same-owner
lib=$work/sdk/runtime/lib/intel64

FLAGS=(-std=gnu17 -O2 -Wall -Wextra -Werror -fstack-protector-strong -D_FORTIFY_SOURCE=3 -fPIE -pie -Wl,-z,relro,-z,now)
# The image has the SDK's libraries here (dictation.sh). RPATH, not RUNPATH, which libopenvino_c's own
# libraries would not search
gcc "${FLAGS[@]}" -I"$work/sdk/runtime/include" -o /out/katze-face /ctx/face/katze-face.c \
  -L"$lib" -Wl,-rpath-link,"$lib:$work/sdk/runtime/3rdparty/tbb/lib" -Wl,--disable-new-dtags,-rpath,/usr/lib/openvino-genai/runtime/lib/intel64 \
  -lopenvino_c -lm
gcc "${FLAGS[@]}" -o /out/katze-face-check /ctx/face/katze-face-check.c

# The self-test loads the models from where the image has them
mkdir -p /usr/share/katze/face
cp /out/models/* /usr/share/katze/face/
LD_LIBRARY_PATH="$lib:$work/sdk/runtime/3rdparty/tbb/lib" /out/katze-face --self-test

rm -rf "$work"
