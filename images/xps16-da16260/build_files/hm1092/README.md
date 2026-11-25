# hm1092: driver of the infrared camera (Himax HM1092)

The kernel finds the sensor since 7.3 but has no driver for it. This is the one posted to linux-media, version 8, with four changes of ours. It goes away when Fedora's kernel has one. What follows is the audit of 2026-11-25.

Scope: the whole file (sha256 7727a1d6...1c7127). The register tables cannot be explained line by line: they come from the Windows driver.

Verdict: nothing malicious found. Not blocked for this use, with the conditions below.

## Provenance
- Same as xps-fedora's patches 0032 (Ramshouriesh R, v6), 0033 (Jake Steinman, v1, "Assisted-by: Claude", tested on a DA16260) and 0038 (Onuralp Sezer), plus our three lines (Y10 to SGRBG10). Rebuilt from the patches and compared.
- Rebuilding gives the same unsigned .ko (sha256 0f306c8a...). The signed one is that plus the signature.
- The 648x368 register table has the addresses and final values of Jake Steinman's separate extraction (238 entries), except exposure (360 instead of 180), frame length (one line), the group-hold bit, and 3 gain registers the controls write anyway.
- Patchwork API, 2026-11-25: v8 (2026-10-25, three patches) and a newer 19.2 MHz v2 (2026-11-06) exist, all "new". Not read: the site and lore refuse automated reads. Not in master (404).

## Code
- Does: i2c writes to one sensor, its clock, reset pin and supplies, and fixed-range V4L2 controls.
- Does not: network, files, firmware loading, debugfs, sysfs, variable-size allocation, copies from user memory, raw memory or PCI access (checked in the symbol list).
- Build with W=1 and sparse, and gcc -fanalyzer: no code warnings. checkpatch was not run.

## Findings
1. Low: hm1092_set_ctrl only skips on pm_runtime_get_if_in_use() == 0. A negative answer would go on and drop a reference it never took. It needs runtime PM off, which I found no way to reach from user space. Fix: <= 0.
2. Low: no chip ID check. Jake's other driver reads 0x1091.
3. Low: crop (0,0)/1294x734 is outside its own bounds (8,8)/1280x720. Harmless here.
4. Low: 0038 defers for as long as the endpoint is missing; the author's later revisions return -ENXIO instead (search summary).
5. Info: reports Bayer for a mono sensor (our change), so libcamera could offer it as a colour camera. Not seen so far with it loaded by hand; not tested when it loads at boot.

## Around the driver (matter more)
- Privacy: the session user has rw access to the sensor and video nodes, so any program of theirs can watch the infrared camera with no light on. A udev rule must take that away. The lamp needs root.
- Suspend: intel-ipu7-isys refuses to suspend while a stream is open (-EBUSY), so the reader must be short and stop before sleep.
- CPU cache: stock intel-ipu7 isys never flushes it for a capture, so a frame read through mmap can hold old 64-byte blocks.
- Exposure is fixed: kenners22/omarchy-xps14-face-unlock reports about 95% of the frame saturated in sunlight.

# Version 8, audited the same day
- Files from hiresello/omarchy-delight (760ed0c), which says they are verbatim; a third-party copy, not checked against the list. The new file equals the body of its "as posted" copy. Jitsusama/core.nix (e1a3527) carries v7, which differs from v8 only in crop bounds, client_info and set_fmt.
- Against the audited v6: <= 0 in set_ctrl (finding 1 fixed), crop bounds are the full array (finding 3 fixed), digital gain limited to 0x3ff, set_fmt dropped, client_info argument, no wait for the endpoint. No register table changed.
- Ours (hm1092.c, sha256 5d0b992e...): v8 plus four changes: SGRBG10, no client_info (not in 7.3), set_fmt back, and the endpoint wait (findings 4 and 5 stay).
- W=1, sparse and -fanalyzer: no code warnings; same kernel symbols as v6. checkpatch printed nothing, so not counted. Loaded on 2026-11-25 on kernel 7.3.4, signed with the owner's module key under Secure Boot: 30 frames of 648x368, no black blocks, no kernel errors, last row dark.
- The 2026-11-06 patch (19.2 MHz v2) was not found outside Patchwork and is not read.
- capture.c drops the cache: 0 black blocks in 12 runs of 30 frames on CPU 0 kept awake, with the sensor's test pattern and v6 loaded.
