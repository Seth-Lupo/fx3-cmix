# RESEARCH-CANDIDATES — literature pass results (2026-06-10)

Sources: encode.su threads 4161 (fx-cmix HP) and 4116 (fxcm, incl. post-2024 development), kaitz's
Google docs (changes timeline, improvement graphs, predictor-gains), kaitz's GitHub (fx3-cmix,
fxcm v26, fx2-cmix), starlit repo, Mahoney LTCB. encode.su is Cloudflare-blocked; all thread
content retrieved via Wayback Machine snapshots (Feb–Mar 2026, current through Sept 2025 posts).

---

## ⚡ The headline finding

**Kaido Orav (kaitz) has already built and published most of fx3-cmix — and stopped at 0.954%.**

- Repo: https://github.com/kaitz/fx3-cmix (GPL-3.0, last README update 2026-04-26, "Unsubmitted")
- His measured result (Windows exe): **S1 = 437,663 + S2 = 109,297,964 → S = 109,735,627**
  = 0.9545% better than fx2-cmix. The 1% threshold is **S ≤ 109,685,196 — he is 50,431 bytes short.**
- Runtime 46.5 h (adjusted from 81.43 h at Geekbench-5 score 800); RAM "~10,058,856 kB" — note this
  is *marginally over* 10 GB if GB = 10^9 bytes; may itself be a blocker he hasn't resolved.
- **Why he stopped:** the integrated fx3-cmix main-file decompression produces a mismatch
  ("compressed stream is identical up to some point"); standalone fxcm round-trips fine. He suspects
  the floating-point mixer / compiler; the same phenomenon forced him to *remove a component* from
  fx2-cmix. Asserts don't fire. (encode.su 4116 p2, post ~24, Mar–Jun 2025.)
- The model code is published as **fxcm v25/v26** (Sept 2025, github.com/kaitz/fxcm releases) "in the
  hope that it will not be lost and may have some value … for generating new ideas", including **a new
  article-order file** that beat his previous order.

Strategic implication: the highest-EV path is not inventing new models — it is (1) reproducing his
published ~1,057 KB of gains on top of our fx2-cmix baseline, (2) fixing the determinism bug that
blocked him, (3) finding the last ~50–150 KB (+ safety margin) from ordering/tuning/binary-size, and
(4) keeping RAM strictly under 10 GB. All of his code is GPL-3 and the Hutter Prize tradition is
building on prior winners (fx2 itself is fast-cmix + starlit + cmix-hp work); credit accordingly.

### Kaitz's measured post-fx2 progress ladder (standalone fxcm, input = 586,459,020-byte processed enwik9)

| Step | Output bytes | Δ gain | What changed |
|---|---|---|---|
| baseline (fx2-era fxcm + sentence parse 57k + re-added fx2-removed component) | 115,277,855 | — | — |
| basic sentence management | 115,169,938 | 107,917 | SentenceContext, 64 sentences |
| Shelwien sh_v2f | 115,152,995 | 16,943 | mixer/sse component |
| Shelwien mod_sse + sh_v2f | 114,955,554 | 197,441 | SSE stage replacement |
| (unlabeled, slower) | 114,494,959 | 460,595 | ~12 h slower; mixer/context expansion wave |
| (unlabeled) | 114,297,617 | 197,342 | |
| (unlabeled) | 114,228,877 | 68,740 | |
| (unlabeled) | 114,059,824 | 169,053 | |
| DMC model w/ smart reset | 113,946,568 | 113,256 | "knowing when to reset" is the trick; 8 MB RAM |
| "10 lines of source code" | 113,792,605 | 153,963 | unidentified; "transfers 1:1 into fx-cmix" |
| new article order | 113,644,838 | 147,767 | shipped with fxcm v26 archive |
| … further steps | 113,575,910 → 113,213,281 | ~430k | order/memory/misc |
| + PPM etc. (final) | 112,461,931 | ~750k | 8,991 MB RAM, 75,266 s on his old box |

Rule of thumb he stated: standalone-fxcm gains translate ~50–60% into full-compressor S
("fxcm 1.2 MB → about 6–700 KB on fx2-cmix"); the sentence/DMC/"10-lines" trio he said transfers ~1:1.

### What changed in his fx3 (from README + v26 changelog)

cmix side: WUS ~10% of updates skipped; 16 mixers; 6 predictions generated; **PPM moved from
14 GB disk-mmap to 1,750 MB in-RAM** (kills the disk-thrash failure mode Mahoney hit, frees wall-time).
fxcm side (v26): codeword-vs-codeword comparison for dictionary words (not text strings);
ContextMap(128) predictions 6/5→5/4 with one shared internal StateMap; ContextMap(32) 5/4→4/3,
StateMap preds removed; StationaryMap×2; codewords in WordsContext; SentenceContext (64 sentences,
similarity by codeword overlap, 53% match threshold), 4 sentence-context groups (lists/tables/
wikilinks/regular); Pronoun word type in stemmer; **InDirectStateMap with order-w mixing of primary
predictions (paq9a/zpaq-style), 22 contexts**; partial-sentence contexts; SparseMatchModel removed;
4 SmallStationaryContextMaps removed; mixers 12→24 in 3 layers; ~40% layer-0 mixer updates skipped;
prediction skipping after 'See also'/'References'/'Bibliography'/'External links'/Category lines;
small ContextMaps reset per article (StateMap preserved); ~610 fxcm predictions, ~487 fed to cmix.

---

## (a) Ranked candidate experiments

EV = expected reduction in S (full pipeline, not standalone fxcm). Runtime/RAM deltas vs fx2-cmix
baseline (~47.5 h equiv, 9.52 GB). Difficulty: S < 1 day, M ≈ days, L ≈ weeks (on top of harness).
Ranking = expected value per effort *under our constraints*, accounting for dependency order.

| # | Idea | Source / evidence | Exp. win (bytes on S) | Runtime Δ | RAM Δ | Diff | Confidence |
|---|---|---|---|---|---|---|---|
| 1 | **Fix the FP-mixer decompression-determinism bug** (deterministic float: `-ffp-contract=off`, no FMA/x87 drift, or convert float mixer to fixed-point; bisect with stream-divergence harness) | kaitz blocked on this in *both* fx2 and fx3; encode.su 4116 p2 #24 | gates ~1,000k (enables #2); also re-enables the component fx2 had to delete (~10–50k alone) | ~0 | 0 | M | High that it's fixable; this is a debugging task with a known repro |
| 2 | **Port kaitz's fxcm v26 model into our fx2 base** (sentence contexts, InDirectStateMap×22, codeword compares, 24 mixers, CM prediction trims, per-article resets, skip-after-References) | fxcm v26 release + fx3-cmix README; his measured S = 109,735,627 | 900,000–1,060,000 (to ~0.95%) | +10–15 h (fits: fx2 used ~47/68 h) | +1–2 GB inside cap if PPM shrunk (#3) | L | High — published, measured end-to-end by the author |
| 3 | **PPM in RAM at ~1,750 MB** (drop mmap_to_disk; shrink arena from 14,000 MB) | fx3-cmix README; Mahoney's test showed disk-thrash → 50% CPU | net ~0 direct; frees ~5–10 h wall + removes I/O risk + frees RAM headroom for #2/#8 | −several h wall | −7+ GB vs disk variant's working set | S–M | High (author shipped it); verify PPM-order-25 loss vs smaller arena on proxy |
| 4 | **Adopt kaitz's 2025 article order file** (ships in fxcm v26 archive) | +147,767 standalone fxcm; Byron measured the 2024 reorder at +212,578 in full cmix | 100,000–200,000 | 0 | 0 | S | High; zero runtime cost, drop-in input file |
| 5 | **Find the "10 lines of source code" change** by diffing fxcm v24→v26 | +153,963 standalone, "transfers 1:1", "without additional resources" | ~150,000 | ~0 | ~0 | S–M (archaeology) | Med-high — exists, identity unknown until diffed |
| 6 | **DMC model with smart (delayed/conditional) reset** | +113,256 standalone; "result transferred 1:1 in fx-cmix"; 8 MB RAM, "tiny bit slower" | ~100,000 | +0.5–1 h | +8 MB | M | High — author quantified; DMC code exists in paq8 family to crib |
| 7 | **Shelwien mod_sse + sh_v2f SSE-stage replacement** | +197,441 standalone (combined) | ~100,000–120,000 | +~0.3 h | +450 MB | M | Med-high; components are public (Shelwien's green/sh samples) |
| 8 | **ContextMap memory rebalance** per his predictor-gains doc: cm8, cm20 (then cm0–5,18–23) want 32×4096×4096; "total individual gain 1,618,xxx bytes for +5 GB" | predictor-gains Google doc (doc 3); fxcm thread post 25 (+57,399 on enwik8-slice from mem bump alone) | 150,000–400,000 (combined, after dedup vs #2) | ~0 | +2–5 GB → only viable with #3 done | S–M (knob sweep) | High that gains exist; exact split with #2 unknown — measure |
| 9 | **Sentence management / SentenceContext alone** (if #2 staged) | +107,917 +57k standalone | ~80,000–100,000 | +small | +300 MB | M | High (in v26 code) |
| 10 | **Re-run article ordering with 2026 embeddings + TSP** (replace t-SNE+k-means with starlit-style TSP over modern doc embeddings; also fix the ~10k REDIRECTs kaitz admits he missed of 85,560) | starlit repo (doc2vec+TSP); kaitz: "found only 75k maybe, so I missed something"; LTCB textdata notes | 50,000–150,000 over #4 | 0 (offline precompute) | 0 | M | Medium — ordering gains have repeatedly beaten expectations (3 wins in a row) |
| 11 | **Replace LSTM-as-PPM-mixer with simpler mixer** | timeline #39: "time reduction ~10 h test / 6 h prize, 45→39 h" semi-tested | 0 direct; buys 6 h budget to fund #2's slowdown | −6 h | ~0 | M | Medium — semi-tested by author, compression-neutrality must be verified |
| 12 | **Mixer weight-update-skipping retune (~10% skip) + layer-0 ~40% skip** | fx3 README; fx2 already has WUS; arXiv 2012.02792 is the only paper kaitz found | 10,000–30,000 + speed | −1–2 h | 0 | S | Med-high |
| 13 | **Context skipping on long matches** (skip 11/85 CM contexts when MatchLen>61; >15 in templates/tables; tune conditions per file position) | 4116 p2 #9/#13: +2,244 then +8,786 with ~69 MB skipped, plus speed | 10,000–30,000 (mostly speed → budget) | −0.5–1 h | 0 | S | High it's safe; modest size |
| 14 | **State-table search** (replace MCM-derived table in cmix w/ multiple variants; more STA3/STA5-class swaps in fxcm; tune the runtime `Init(s0..s6)` generator params) | timeline #1/#4/#33 ("tested"/"semi-tested"); paq8-table swap cost −319,523 → sensitivity is huge | 50,000–150,000 | ~0 | 0 | M | Medium — search space large, harness-friendly |
| 15 | **Binary-size diet**: direct mixer contexts (−1 KB binary per mixer), simpler code, better compression of comp_order/comp_dict blobs (order file alone is ~197 KB raw) | 4116 p2 #58: "gain can be probably 50 KB… maybe max 100 KB for archive+compressor"; fx2 commit "reduce compressor size by improving compression of article reorder file" | 30,000–100,000 | 0 | 0 | S–M | Med-high; S1 bytes = S2 bytes |
| 16 | **Pronoun + further word types in stemmer; word-type-conditioned context switching** ("Article followed by Noun 64.7%"; None-words 23–56%) | 4116 p2 #5 spreadsheet; v26 has Pronoun | 20,000–60,000 (beyond #2) | +small | 0 | M | Medium |
| 17 | **More enwiki-specific transforms** (timeline #6 "tested ok 18.01.24"; entity/template/link markup beyond current WIT single-pass) | timeline; fx2 shipped single-pass transform (+disk −12 GB, faster, better) | 30,000–80,000 | ±0 | 0 | M | Medium |
| 18 | **Direct contexts replace hashed on high orders** (`context*prime+data`, "avoid full hashed context at all cost except APM") | timeline #20 (author's explicit design rule) | 20,000–60,000 + speed | −small | 0 | M | Medium |
| 19 | **Dictionary re-optimization done right** (strip ALL html entities first — his Feb-2024 retry failed for this reason; original word2vec-class reorder won +322,299 standalone in 2023; consider word counts from cmix-processed input) | 4116 p1 #50; timeline #5; thread 4161 p2 #58 | 0–100,000 | 0 | 0 | M | Low-medium — one clean win, one failure; high variance |
| 20 | **Match-model enlargement** (fxcm match hash table "is also small, maybe double memory will help"; fx2 deleted 6 cmix match models — revisit 1–2 best under freed time) | fxcm thread post 25; ARCHITECTURE.md lever #1 | 20,000–60,000 | +0.5–2 h | +0.5–1 GB | S–M | Medium |
| 21 | **Gap-removal in similar-data contexts** ("if similar data continues after a small gap, remove gap data — some lists, col ctx") | timeline #21 (untested author idea) | 10,000–40,000 | ~0 | 0 | M | Low — untested |
| 22 | **New structural context family** (another bracket/column/quote/first-char-like context; e.g., infobox-key context, link-target-class context) | timeline #22 (open author wish) | 20,000–80,000 | +small | +small | L | Low — open-ended research |
| 23 | **UPDATE_LIMIT / SEED / mixer-LR sweeps** (23 mixer LRs, deltas 200/400/0.5, APM/SSE params, aux ×15 discretization) | ARCHITECTURE.md tunable surface; timeline #24 "most parameters need re-tuning (slow)" | 20,000–60,000 cumulative | ~0 | 0 | S (automatable) | Med-high in aggregate, tiny each |
| 24 | **LSTM hyperparameter tune only** (cells/lr/horizon of the existing 200-cell LSTM; do NOT port paq8px LSTM — failed) | timeline #10; cmix v21 notes | 10,000–40,000 | ±1 h | ±small | S | Medium |
| 25 | **Better REDIRECT/census/Image: handling in transform** (delete-and-regenerate redirect boilerplate as a transform rather than relying on ordering) | kaitz's ordering notes; mattmahoney textdata (85,560 redirects) | 20,000–50,000 | ~0 | 0 | M | Low-medium |

**Dependency note:** #1 gates #2; #3 creates the RAM headroom that #2/#8/#20 spend; #11–#13 create
the time headroom that #2/#6 spend. Run #4/#5 immediately (zero-cost). The sum of #1–#8 at midpoint
estimates ≈ 1.4–1.6 MB — comfortably past the 1,107,932-byte requirement with margin for the
~50% standalone→full attenuation already baked into the "Exp. win" column.

---

## (b) What the authors already tried and rejected — do not repeat

From the changes-timeline doc, encode.su threads 4161/4116, and fx3 README:

1. **paq8px LSTM port** — "tested paq8px LSTM version, no, or failed porting, slower" (timeline #10).
2. **LSTM update skipping** — "semi tested. NO" (timeline #11).
3. **Parsing See also/References/External links into separate streams pre-compression** — "No gains
   10.03.2024" (timeline #27). NB: the *cheap* version (skip predictions after these markers) DID
   work and is in v26 — the failure was the heavyweight stream-separation variant.
4. **New dictionary, Feb-2024 attempt** — negative gain (entities not stripped first); 7z-ppm proxy
   said +80 KB but real pipeline lost. Lesson: dictionary work must use entity-clean, *cmix-processed*
   input, and proxy compressors mislead here (4161 p2 #58, timeline #5).
5. **Reducing predictor count while growing mixer set** — "size OK, count no" (timeline #26).
6. **cmix mixer parameter tuning / removing useless mixers** — "tested, OK, not really so-so"
   (timeline #29/#30) — only mildly useful, already harvested in fx2.
7. **Word-dependent context state-table re-tuning** — "can't be renewed, too much work" (timeline #23);
   requires backporting model to paq8pxv cfg (timeline #19, "hard").
8. **A third model after DMC** — "after a few model resets, the result was negative and remained so
   (large drops)" (4116 p2 #22). The *insight that worked* was reset policy, not more models.
9. **Weight regularizer in mixer** — "bad idea", replaced by weight-update skipping (4161 p2 #58);
   already gone in fx2.
10. **DMC naïvely** (no reset policy, big memory) — "memory too high, results non-existent" in
    fx-cmix; only the smart-reset version wins (4116 p2 #20).
11. **Manual dictionary tweaks** — "improvements were quickly eaten up after 10–20 MB" (4116 p1 #50);
    only global embedding-based reorder worked.
12. **Increasing memory on most ContextMaps** — "increasing memory on any other [than cm8/cm20/etc.]
    will degrade compression a lot" (fxcm thread post 25). Rebalance, don't blanket-increase.
13. **Adding every fxcm prediction to cmix mixers** — "one good predictor in fxcm can make compression
    worse in cmix, and a lot" (4161 p2 #62); fx2 deliberately forwards a single bias instead — keep.
14. **statemap update limits on state-based input** — "actually bad for state based input" (4116 p1 #54).
15. Known hazard, not a rejection: **the FP component removed from fx2** because decompression
    mismatched — the determinism bug (#1 above) is long-standing and reproduces across compilers.

Author's own ceiling estimates for context: Feb 2024 "0.23% done… might be able to achieve 0.50%, no
more"; by 2025 he actually reached 0.954% standalone-verified — his pessimism was wrong by 2×, but
the published trajectory has clearly flattened near 1%.

---

## (c) Key links

- encode.su fx-cmix (HP) thread: https://encode.su/threads/4161-fx-cmix-(HP) (Cloudflare-blocked;
  use Wayback: http://web.archive.org/web/20260215040047/https://encode.su/threads/4161-fx-cmix-(HP)
  and …/page2 snapshot 20260302095617)
- encode.su fxcm dev thread (post-fx2 progress, DMC, sentences, v25/v26, fx3 bug report):
  https://encode.su/threads/4116-fxcm (Wayback page2 snapshot 20260311063929)
- kaitz fx3-cmix (unsubmitted 0.954%): https://github.com/kaitz/fx3-cmix
- fxcm v26 release (model code + new article order): https://github.com/kaitz/fxcm/releases/tag/v26
- fx2-cmix: https://github.com/kaitz/fx2-cmix · fx-cmix: https://github.com/kaitz/fx-cmix
- fxd dictionary transform: https://github.com/kaitz/fxd · wit2: https://github.com/kaitz/wit2
- Changes-timeline doc (39 numbered ideas w/ tested-status):
  https://docs.google.com/document/d/14nNIMAFC11lNFD-WrLQbGLIuRqqcKKBnUtrxy-tc0Rc/
- Improvement-graphs doc (fx-cmix→fx2 category gains: 100k + 100k order + 180k + 290k NLP + 190k +
  70k + 70k(bug) − 16k(fix) + 80k ≈ 1,064k): https://docs.google.com/document/d/1DW0Lqr_y-yAIvPpGua56j1Y3gRaMS5yt2RuQy5xgGMk/
- Predictor-gains doc (per-ContextMap memory-doubling gains, Σ ≈ 1.618 MB for +5 GB):
  https://docs.google.com/document/d/1wVZnTOOwdiImjyG3hwxNnZUvMWp17iCCC_5MWAoQdh8/
- Hutter-Prize group, fx2 comment period: https://groups.google.com/g/Hutter-Prize/c/NcFEFMNMsd8
- LTCB (frontier: nncp v3.2 107.3 MB GPU-unconstrained; cmix v21 108.2 MB no-Hutter-limits;
  jax-compress Mar-2026 113.4 MB): https://www.mattmahoney.net/dc/text.html
- enwik9 structure notes (85,560 redirects etc.): https://www.mattmahoney.net/dc/textdata.html
- starlit (doc2vec + TSP article ordering): https://github.com/amargaritov/starlit
- paq8px (stemmer origin; LSTM there already tried & rejected for this use):
  https://github.com/hxim/paq8px · thread: https://encode.su/threads/342-paq8px
- WUS paper kaitz cited for mixer update skipping: https://arxiv.org/pdf/2012.02792
- Hutter Prize rules: http://prize.hutter1.net/hrules.htm

### Open questions for Phase 1/2
1. Diff fxcm v24 ↔ v26 to identify the "+153,963 in 10 lines" change (candidate #5).
2. Does kaitz's fx3 repo code actually contain the v26-era model, or only fx2+order (code commits
   stop Aug 2024; README claims 2025-era results)? Compare against fxcm v26 sources.
3. Reproduce his decompression divergence: build fx3/v26, compress 50 MB slice, find first divergent
   bit, attribute (FP contraction? uninitialized read? table overflow?).
4. RAM: his 10,058,856 kB is over a 10^9-bytes-GB reading of the limit — confirm committee's GB
   definition and budget to 9.7 GB to be safe.
5. Quantify overlap between candidate #2 (v26 port) and #8 (memory rebalance) — the predictor-gains
   doc predates v26 and some gains are likely already absorbed.

---

## 2026-06-12 research refresh (post-port, post-sweep synthesis)

Field check (LTCB Jun 2026): no CPU-feasible movement since fx2. jax-compress (Knoll, Mar 2026) = TPU, ineligible. nncp v3.2 107.26M = transformer class, ~100× our time budget. **Our candidate's projected ~108.8M ≈ cmix v21's unconstrained 108.24M — the port has nearly exhausted the context-mixing class within prize limits.** Empirical confirmation from our sweeps: every parameter surface (STA generators, mixer sizes, LSTM lr, PPM order) is at a flat optimum.

Ranked post-T3 margin levers (engaged only if first T3 lands in 0.95–1.0%):
1. **CM memory rebalance @T2 tier** (candidate #8) — only author-measured 6-figure upside left; freed −547MiB from trims funds it. T2 datapoints (~10h each) on lab2-class box.
2. **Modern-embedding article reorder** (candidate #10 upgraded) — ordering over-delivered 3 submissions running (+322K dict-era, +212K starlit-era, +147K v26); every existing order used doc2vec/t-SNE-class embeddings; 2026 sentence-transformers are categorically better. Mac-side prep free. Full-pipeline validation only (T3-expensive) → prep now, validate on demand.
3. **Gating-context search** — GLN theory (Veness et al., arXiv:1910.01526; cmix is its flagship instance) says capacity is in gating context functions, not mixer params. fx's 24 gating contexts are hand-picked; search alternatives per-mixer at T1 (~1h/datapoint). The one architecture-level idea with theory behind it that kaitz never systematized.
4. **Adaptive-LR mixer** (paq8px-proven, Pais) — cheap probe on fxcm final chain; modest expectation given kaitz's LR tuning history.

Closed lines (do not reopen): STA generator params (full surface swept flat), export pruning (load-bearing, +1,199 @T1), order-file delta coding (real-cmix inverted the xz proxy, +8,882 — proxy-trap case study #2), all of §(b).
