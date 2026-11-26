# Local language models on the XPS (idea, not implemented)

Noted on 2026-11-26 for later. Nothing here is in the image or tested on this machine. It comes from
`onuralpszr/xps-fedora` (commit `98e8400`), mostly its `docs/local-llm.md`, `packages/ollama/`,
`packages/llama-cpp/` and `tools/ai-local/`, measured there on a DA16260 with **32 GB**. The owner's has 64 GB.

## What xps-fedora found

- **The GPU can use at most three quarters of the RAM.** Mesa's Vulkan driver (ANV) gives the integrated GPU a heap of
  3/4 of system memory (`vulkaninfo`, `memoryHeaps[0]`): 23.18 GiB with 32 GB, so about 48 GB here. Model, context
  cache and buffers must fit in it, and what the desktop needs comes out of the rest.
- **Models that fit and work for agents** (llama.cpp b11513, Vulkan, on battery):
  | Use | Model | GPU memory | Speed |
  |---|---|---|---|
  | Agent, 64K context | gpt-oss-20b MXFP4 | 13.2 GB | 27 tokens/s; first reply of an agent in 37 s |
  | Long answers | Qwen3-30B-A3B-Instruct-2507 | 15 to 23 GB | 45 tokens/s on a short context |
  | Coding | Qwen3-Coder-30B-A3B-Instruct | like Qwen3-30B | not measured |
- **On Vulkan here, flash attention and a quantized context cache both slow down as the context grows**: with 14K
  tokens already in it, Qwen3-30B wrote 23 tokens/s with a 16-bit cache and flash attention off, and 2 tokens/s with
  an 8-bit cache and flash attention on. Use `-fa off` and a 16-bit cache, and pay for it in memory.
- **OpenVINO did not work for big models:** GenAI on the GPU ran out of memory loading a 16 GB int4 model (the upload
  briefly needs twice that), and on the NPU a MoE model was still compiling after 15 minutes. Vulkan on the GPU is the
  path for language models; the NPU stays with dictation.
- **The `xe` driver keeps freed GPU pages in a pool** after a model is unloaded (`GPUReclaim` in `/proc/meminfo`,
  14 GB after the 30B model). The kernel takes them back under pressure, but `free` does not count them as available.
- During a reply the server keeps the GPU 100% busy and the CPU near 10%. What decides whether the desktop stays usable
  is memory: keep the model well under the heap and leave several GB for the browser.

## Their packaging

- Ollama 0.40.13 built with a Vulkan backend (`libggml-vulkan` in `/usr/lib/ollama/vulkan`), a system service and a
  sysusers file. Fedora 45 itself has Ollama 0.24.0 (`ollama`, `ollama-vulkan`, `ollama-rocm`) and llama.cpp b9840.
- llama.cpp with Vulkan, OpenVINO (CPU, GPU or NPU; Q4_0 models for the NPU) and ROCm backends.
- `tools/ai-local/ai-local`: starts and stops `llama-server` as a user service with a model from `~/models/gguf`,
  and `ai-load-monitor.py` prints GPU and NPU memory and busy time once a second, without root.

## How it would fit Katze OS

Their packages are references to audit, not to install (`CLAUDE.md`, non-goals). Options, best first:

1. **Ollama's own container under rootless Podman**, with `/dev/dri` and its Vulkan backend on, started by a
   `mise` task or a user quadlet that is not enabled by default. The image stays as it is, the version is always
   current, and the models live in the home directory.
2. **Fedora's `ollama` and `ollama-vulkan`** in `xps16-da16260`: the least work, but 0.24 is far behind.
3. **llama.cpp in an Incus container with the GPU**, which matches the owner's idea of heavy stacks in Incus with
   resource limits (`CLAUDE.md`, "Incus at boot"), at the cost of more setup.

Before choosing: on the XPS, run gpt-oss-20b through option 1 with `-fa off` and a 16-bit cache, and measure speed,
GPU memory, what is left for the desktop, and the battery. Check that the container sees the Arc B390 through
Vulkan (`vulkaninfo` inside it) and that SELinux lets it open `/dev/dri`.
