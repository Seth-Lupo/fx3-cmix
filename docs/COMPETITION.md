# Hutter Prize — Competition Facts

*Verified against http://prize.hutter1.net/ and hrules.htm on 2026-06-10.*

## The task
Losslessly compress `enwik9` (first 10^9 bytes of English Wikipedia XML dump) into a
self-extracting archive. Total size **S = S1 + S2** where:
- **S1** = size of the compressor executable (or zipped source)
- **S2** = size of the self-extracting archive `archive9` it produces

Alternative split (comp + decomp + archive) allowed: S = len(comp9a) + 2×len(decomp9) + len(archive9.bhm); the 2× drops to 1× if comp = decomp. fx2-cmix uses the self-extracting form.

## The numbers
| Quantity | Value |
|---|---|
| Current record L (fx2-cmix, Oct 2024) | **110,793,128 bytes** |
| fx2-cmix S1 (executable) | 441,463 bytes |
| fx2-cmix S2 (archive) | 110,351,665 bytes |
| Minimum winning claim | 1% → **S ≤ 109,685,196 bytes** |
| Required saving for 1% | ≥ 1,107,932 bytes |
| Award | 500,000€ × (1 − S/L) |

No submission has beaten fx2-cmix as of June 2026.

## Resource constraints
- Time: **< 70,000/T hours** on the test machine, where T = its Geekbench 5 single-core score. (fx2 test machine T=1026 → 68.2 h limit; fx2 used 47.5 h equivalent — ~30% headroom exists.)
- **Single CPU core**, no GPU.
- **< 10 GB RAM** (fx2 peaked at ~9.52 GB with PPM mmap_to_disk=true).
- **< 100 GB HDD** for temporaries (fx2 used ~21 GB).
- Linux or Windows x86-64 (or x86-32) executable. No network, no external files.
- Compression and decompression each must satisfy the limits; for fx2 they are roughly symmetric (~47 h each on T≈1026 hardware).
- Command-line option lengths count toward S.
- Compressor may be enwik9-specific; may fail on any other input.

## Submission process
Email to Matt Mahoney, James Bowery, Marcus Hutter with links to archive, source under OSI license, machine description + Geekbench 5 score, timing/memory data, and a document explaining the algorithmic ideas. 30-day public comment period before award.

## Reference points
- fx2-cmix compresses enwik9 (after transform: 934,220,400 bytes) → 110,111,245 bytes in ~228,590 s (~63.5 h on their dev machine).
- Header overhead: comp_dict + comp_order + header are appended to the binary (~441 KB total S1, of which the dictionary ~292 KB compressed and article order are significant parts).
- nncp (unconstrained, GPU) is only ~3% better than fx2-cmix on LTCB — the constrained frontier is tight; 1% is a serious but plausible target.
- Lineage: PAQ → paq8hp → cmix → cmix-hp (2021, Knoll) → fast-cmix (Saurabh Kumar 2023) → fx-cmix (Kaido Orav + Knoll, 2024) → fx2-cmix (Oct 2024). ~20 years of incremental tuning; cheap wins are mostly gone.
