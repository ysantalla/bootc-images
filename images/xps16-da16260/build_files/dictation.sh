#!/usr/bin/env bash
# Voice dictation on the NPU or the GPU: Voxtype, and the part of Intel's OpenVINO GenAI SDK it needs.
# Fedora's OpenVINO has no NPU plugin and no GenAI. The driver for the NPU is Fedora's.
# Pinned releases, checked by sha256. To update one, change its version and checksum here,
# and try it first: the SDK has the compiler, which has to suit Fedora's driver and firmware.
set -euxo pipefail

VOXTYPE_VERSION=1.3.1
VOXTYPE_SHA256=5b771a18c1d76afe208eab8c6e118f858600e6e137de2a10d7630e781a6a0ffa
OPENVINO_VERSION=2026.4.1.0
OPENVINO_SHA256=b8ba7b6e5ae7899e63e5e3c7f9d022ad8a4207247521e46c507f6f3ef23ea2c5

work=$(mktemp -d)

# The binary with ONNX is the one that has OpenVINO. AVX2, since Panther Lake has no AVX-512.
curl -fsSL --retry 3 -o "$work/voxtype" \
  "https://github.com/peteonrails/voxtype/releases/download/v${VOXTYPE_VERSION}/voxtype-${VOXTYPE_VERSION}-linux-x86_64-onnx-avx2"
echo "${VOXTYPE_SHA256}  $work/voxtype" | sha256sum -c -
install -Dm0755 "$work/voxtype" /usr/bin/voxtype

curl -fsSL --retry 3 -o "$work/openvino.tar.gz" \
  "https://storage.openvinotoolkit.org/repositories/openvino_genai/packages/${OPENVINO_VERSION%.*}/linux/openvino_genai_ubuntu24_${OPENVINO_VERSION}_x86_64.tar.gz"
echo "${OPENVINO_SHA256}  $work/openvino.tar.gz" | sha256sum -c -
mkdir "$work/sdk"
tar -xzf "$work/openvino.tar.gz" -C "$work/sdk" --strip-components=1 --no-same-owner

# Without the other model formats (but ONNX, for face unlock), the headers and the samples
to=/usr/lib/openvino-genai/runtime/lib/intel64
from=$work/sdk/runtime/lib/intel64
tbb=$work/sdk/runtime/3rdparty/tbb/lib
mkdir -p "$to" /usr/share/licenses/openvino-genai
for lib in openvino openvino_c openvino_genai openvino_genai_c openvino_ir_frontend openvino_onnx_frontend; do
  # The soname: libopenvino.so.2641 and the like
  soname=$(basename "$(find "$from" -name "lib$lib.so.*" | awk '{ print length, $0 }' | sort -n | head -1 | cut -d' ' -f2-)")
  install -m0755 "$from/$soname" "$to/$soname"
  ln -s "$soname" "$to/lib$lib.so"
done
install -m0755 -t "$to" "$from"/libopenvino_{tokenizers,intel_cpu_plugin,intel_gpu_plugin,intel_npu_plugin}.so \
  "$from"/libopenvino_intel_npu_{compiler,compiler_loader,vm_runtime}.so "$tbb"/libtbb.so.12 "$tbb"/libtbbmalloc.so.2
install -m0644 "$from/cache.json" "$to/"
install -m0644 -t /usr/share/licenses/openvino-genai "$work"/sdk/docs/licensing/* "$work/sdk/runtime/3rdparty/tbb/TBB-LICENSE"

rm -rf "$work"

# Nothing starts until the user has the model: see dictation-setup.sh
systemctl --global enable katze-dictation.service katze-ydotoold.service
