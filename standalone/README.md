# standalone/ — fxcm v26 Linux port

`fxcm.cpp` is Kaido Orav's standalone fxcm model, v26 (GPL-3), from
https://github.com/kaitz/fxcm (master @ 2025-09). It contains the fx3-generation
model improvements that were never integrated into a published fx3-cmix build.
`states.cpp` is his state-table tool, for reference.

Local changes (kept minimal for diffability against upstream):
- `PLAINTEXT` define disabled → v26 mode (expects dictionary-encoded input,
  i.e. the 586,459,020-byte processed enwik9 / our /mnt/work/proxy/coded_* slices).
- `<mem.h>` / `<windows.h>` includes guarded for non-Windows.

Build: `clang++-17 -O3 -march=native -std=c++17 -m64 fxcm.cpp -o fxcm`
Usage: `fxcm c input output` / `fxcm d input output`
