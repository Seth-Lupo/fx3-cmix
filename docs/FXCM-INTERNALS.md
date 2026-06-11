# FXCM Internals (src/models/fxcmv1.cpp) — verified map for experiment design

> Source of truth: `src/models/fxcmv1.cpp` (4824 lines, `#define VERSION 22` at fxcmv1.cpp:108)
> plus glue in `src/predictor.cpp` and `src/context-manager.cpp`. All line numbers verified
> against source on 2026-06-10. Sizes in MiB unless noted.

fxcm is a self-contained paq8/fxcm-style bit predictor compiled into the cmix ensemble as a
single multi-output model. It exports **431 probabilities per bit**
(`num_models = 439+1-2-7` at fxcmv1.cpp:93) which become individual layer-0 inputs in
`predictor.cpp:182-187`, plus its own final mixed prediction. It also exports `wrtcxt`
(fxcmv1.cpp:45, set at :4494 from `deccode`) which the cmix side uses as mixer context
`mx19cxt` (context-manager.cpp:205) — i.e. fxcm's dictionary-word decoder steers a cmix mixer.

---

## 1. Memory budget

### 1.1 Container semantics (read this first — the Init() arg is NOT always the byte size)

| Type | Element | Assoc. | Actual bytes vs `Init(m,…)` arg | Init at |
|---|---|---|---|---|
| `ContextMap` (`cmC`) | `E<7,64>` 64 B bucket, 7 slots | 7-way | **= m** (`tmask=(m>>6)-1`, 64 B/bucket) | fxcmv1.cpp:921 |
| `ContextMap1` (`cmC1`) | `E<3,32>` 32 B bucket, 3 slots | 3-way | **= m/2** (`tmask=(m>>6)-1` but 32 B/bucket) | fxcmv1.cpp:1126 |
| `ContextMap2` (`cmC2`) | `E1<14,128>` 128 B bucket, 14 slots | 14-way | **= 2·m** (`m=m1*2` at :1361, 128 B/bucket) | fxcmv1.cpp:1359 |
| `RunContextMap` | 4 B element, 4-way MTF | 4-way | = m | fxcmv1.cpp:680 |
| `StateMap1` | U32 per context | direct | = 4·n | fxcmv1.cpp:630 |
| `SmallStationaryContextMap` | U16 | direct | = 2·(2^bits)·255 | fxcmv1.cpp:752 |
| `APM<S>` | U16 (in-object array) | direct | = 2·S·33 | fxcmv1.cpp:1541-1562 |

Each ContextMap* additionally owns one 1 KiB `StateMap` (256×U32) per context slot — negligible.

### 1.2 ContextMap2 instances (the big spenders) — all `Init` calls in `PredictorInit()`, fxcmv1.cpp:3276-3311

| Instance | Init arg (bytes) | **Actual MiB** | #ctx | State table | st2 | keep | line |
|---|---|---|---|---|---|---|---|
| cmC2[0] (orders 3–5) | 8·4096·4096 | 256 | 3 | STA6 | p1 | 0xf0 | 3276 |
| cmC2[1] (order 6) | 16·4096·4096 | **512** | 1 | STA6 | p1 | 0xf0 | 3277 |
| cmC2[2] (order 8) | 8·4096·4096 | 256 | 1 | STA6 | p1 | 0xf0 | 3278 |
| cmC2[3] (order 13) | 8·4096·4096 | 256 | 1 | STA6 | p1 | 0xf0 | 3279 |
| cmC2[4] (word/number) | 8·4096·4096 | 256 | 2 | STA6 | p1 | 0xf0 | 3280 |
| cmC2[5] (sentence words) | 8·4096·4096 | 256 | 6 | STA6 | p1 | 0xf0 | 3281 |
| cmC2[6] (order-2 + 2bit stream) | 4096·4096/64 | 0.5 | 1 | STA1 | p1 | 0 | 3282 |
| cmC2[7] (indirectBrByte) | 2·4096·4096 | 64 | 1 | STA5 | p1 | 0xf0 | 3283 |
| cmC2[8] (streams/brackets) | 8·4096·4096/2 | 128 | 4 | STA4 | p1 | 0 | 3284 |
| cmC2[9] (pWord hash, link/sen words) | 8·4096·4096 | 256 | 4 | STA6 | p1 | 0xf0 | 3296 |
| cmC2[10] (indirect byte/word) | 8·4096·4096 | 256 | 6 | STA5 | p1 | 0xf0 | 3297 |
| cmC2[11] (words/spaces/indirect) | 8·4096·4096 | 256 | 5 | STA5 | p1 | 0xf0 | 3298 |
| cmC2[12] (x4 sparse, word/column) | 8·4096·4096 | 256 | 2 | STA6 | p1 | 0xf0 | 3299 |
| cmC2[13] (word 2–3 grams) | 16·4096·4096 | **512** | 2 | STA6 | p1 | 0xf0 | 3300 |
| cmC2[14] (word(2)·stream3bR) | 4·4096·4096/2 | 64 | 1 | STA6 | p1 | 0xf0 | 3304 |
| cmC2[15] (BrFcIdx/fc/stream3bR) | 8·64·4096 | 4 | 1 | STA1 | p0 | 0 | 3305 |
| cmC2[16] (fword/lang-links) | 4096·4096/2 | 16 | 1 | STA6 | p1 | 0xf0 | 3310 |
| cmC2[17] (paragraph words, verbs) | 2·4096·4096 | 64 | 2 | STA6 | p1 | 0xf0 | 3311 |
| **subtotal** | | **3668.5** | 44 | | | | |

### 1.3 ContextMap (`cmC`, 7-way) — fxcmv1.cpp:3291-3308

| Instance | Init arg | MiB | #ctx | Table | line |
|---|---|---|---|---|---|
| cmC[0] (paragraph/column/list/table switch + indirect) | 16·4096 | 0.0625 | 7 | STA2 | 3291 |
| cmC[1] (stream3b·word0, x4, indirectBrByte) | 64·2·4096 | 0.5 | 3 | STA5 | 3292 |
| cmC[2] (indirectByte, o2+repeat flag) | 2·4096 | 0.008 | 2 | STA2 | 3293 |
| cmC[3] (stream tails + linkword/number) | 32·4096 | 0.125 | 2 | STA2 (st2_p2) | 3302 |
| cmC[4] (bracket context + c1, set at :3752) | 512·4096 | 2 | 1 | STA1 | 3307 |
| cmC[5] (first-char context + c1, set at :4170) | 512·4096 | 2 | 1 | STA1 | 3308 |
| **subtotal** | | **4.7** | 16 | | |

### 1.4 ContextMap1 (`cmC1`, 3-way, actual = arg/2) — fxcmv1.cpp:3286-3315

| Instance | Init arg | MiB | #ctx | Table | line |
|---|---|---|---|---|---|
| cmC1[0] (first-char/column) | 32·4096 | 0.0625 | 2 | STA6 (st2_p0, skip2=0) | 3286 |
| cmC1[1] (word00, o2, fc) | 2·32·4096 | 0.125 | 3 | STA7 | 3287 |
| cmC1[2] (streams, firstWord, word pair) | 32·4096 | 0.0625 | 4 | STA2 | 3288 |
| cmC1[3] (masked streams, x4) | 128·4096 | 0.25 | 2 | STA1 (st2_p0) | 3295 |
| cmC1[4] (stream/word/number/fc) | 16·4096 | 0.031 | 5 | STA7 | 3289 |
| cmC1[5] | — **never initialized or mixed (dead slot)** | 0 | — | — | — |
| cmC1[6] (word type + paragraph word) | 16·4096 | 0.031 | 1 | STA6 | 3313 |
| cmC1[7] (local word contexts) | 16·4096 | 0.031 | 4 | STA2 | 3315 |
| **subtotal** | | **0.59** | 21 | | |

### 1.5 Everything else in fxcm

| Object | Definition | Size | line |
|---|---|---|---|
| `rcmA[0]` RunContextMap | `Init(1*4096*4096, 6)` (rcm_ml=6) | 16 MiB | 3263 |
| `smA[0..2]` StateMap1 (match model) | 1<<9, 1<<19, 1<<16 ctx, limit 1023 | 2 KiB + 2 MiB + 256 KiB | 3231-3233 |
| `scmA[0..6]` SmallStationary | bits 8,8,8,9,8,8,7 | ≈0.81 MiB total | 3235-3241 |
| `apmA0` APM<256> | 256·33·2 B | 16.5 KiB | 3206 |
| `apmA1`, `apmA2` APM<0x10000> | each 65536·33·2 B | 4.125 MiB ×2 | 3207-3208 |
| `apmA3..5` APM<0x40000> | each 262144·33·2 B | 16.5 MiB ×3 | 3209-3211 |
| `mxA[0..9]` Mixer1 weights | M·N·2 B, N=512 (see §3) | **308 MiB** total | 3244-3253, 3265 |
| `mxA[10..11]` final mixers | M=224/1, N=16 | 7 KiB | 3254-3255 |
| MatchModel2 hash table | 0x200000 × 16 B (`mHashN=4` U32s) | 32 MiB | 4783-4784, 3339-3348 |
| `smatch` SparseMatchModel table | `U32 Table[1024*1024]` | 4 MiB | 1663 |
| `ind3` (cmix-mirror indirect) | `U16 ind3[0x2000000]` | 64 MiB | 3158 |
| `buffer` history | `U8 buffer[0x1000000]` | 16 MiB | 3170 |
| `t1/t2/wp/cwbuf` indirect tables | 0x100·4 + 0x10000·4 + 0x10000·4 + 0x1000 | ≈0.52 MiB | 3155-3157, 3172 |
| **fxcm grand total** | | **≈ 4,175 MiB ≈ 4.1 GiB** | |

Mixer weight detail (N=512 shorts per context-row; `setTxWx` allocates `N*M`, bias init 129 at :570):
mxA[0] M=2048 → 2 MiB; mxA[1] 1536 → 1.5; mxA[2] 6144 → 6; mxA[3] 2048 → 2; mxA[4] 1536 → 1.5;
mxA[5] 7168 → 7; mxA[6] 16384 → 16; mxA[7] 16384 → 16; **mxA[8] 0x20000 → 128; mxA[9] 0x20000 → 128**.
mxA[8] is keyed on `deccode` (dictionary word index, :4495); mxA[9] on bpos/fails/lstmex (:4661).

### 1.6 Whole-program memory picture (for context)

| Component | Size | Where |
|---|---|---|
| **PPMD arena** | **14,000 MB** (`SASize<<20` = 13.67 GiB), order 25 | predictor.cpp:56 `byte_model_.emplace(25, 14000, …)`; ppmd.cpp:140-141; **mmap'd to disk**: `mmap_to_disk = true` at ppmd.cpp:33 |
| fxcm | ≈4.1 GiB | this file |
| cmix indirect hashes | `hashes_ind1/ind2` 0x1000000×8 B = 128 MiB each; `hashes_ind3` 0x2000000×8 B = 256 MiB; `hashes_ind5` tiny | context-manager.cpp:60-64 |
| cmix shared_map_ | 256·400000 = 97.7 MB (`vector<unsigned char>`) | context-manager.cpp:59 |
| cmix history_ | grows ~1 B/input byte (≈0.93 GB over enwik9) | context-manager.h:88 |
| match models (cmix side) | 10 models, ≤2,000,000 entries each | predictor.cpp:88, 99 |
| **LSTM** | `Lstm(vocab, vocab, 200 cells, 1 layer, horizon 128, lr 0.03, clip 10)` — order ~10 MB incl. Adam moments; negligible | predictor.cpp:131-132, lstm.h:16-18 |

Compile-time defines (build_and_construct_comp.sh:6-13): `SEED=923` (runner.cpp:320 srand),
`UPDATE_LIMIT=3000` (Adam step-decay cap in lstm-layer.hpp:43-57,158). Neither is used inside fxcmv1.cpp.

---

## 2. Context inventory (what feeds the predictors)

All `set()`/`sets()` wiring happens once per byte inside `modelPrediction()` at `bpos==0`
(fxcmv1.cpp:3721-4495). `sets()` marks a slot skipped for that byte (zero inputs, :985-990).

### 2.1 Feature vocabulary (built per byte, :3721-4243)

- **Order-N byte hashes** `t[1..13]`: rolling `t[i]=t[i-1]*primes[i]+c1+i*256` (:3775-3777). A
  "duplicate end byte" trick re-rolls them on `$ ] | ) [` boundaries (:3761-3773) so contexts
  reset at wiki-markup seams.
- **Quantized byte streams**: `wrt_2b/wrt_3b/wrt_4b` map bytes to 2/3/4-bit classes (:47, :67,
  :1750). `stream2b/3b/4b` = serial streams; `stream2bR/3bR` = non-repeating (only on class
  change, :4068-4083); `stream3bMask*` track word boundaries (:3932-3935). Word-type events
  inject markers into these streams (§2.3).
- **Word hashes**: `word0` (current, ×2104, :3811), `word1..3` (previous, ×83/53/47,
  :3885-3887), aged on `.` and LF (:4484-4487). `word00` (link-aware variant, :3881),
  `firstWord` (:3894), `linkword` (inside `[...]`, :3814), `senword` (sentence, :3815),
  `lastWT` (nibble history of word types, :3673), `h=word0*271` (:3813).
- **Stemmed word streams** (`WordsContext`, :2076): `worcxt` = sentence (all words),
  `worcxt1` = paragraph, `worcxt2` = typed-word stream — see §2.3 for gating. Each stores
  stem hash, type flags, surrounding bytes, capitalization (vec of 256).
- **Indirect contexts** (:4210-4228): `indirectByte` (order-1 byte history table `t1`),
  `indirectWord` (order-2 via `t2`), `indirectBrByte` (2-bit-stream history keyed by bracket
  context, :4218-4219), `indirectWord0Pos` (distance to last occurrence of word0 via `wp`,
  :4221-4224), `ind3` (25-bit cmix-style double indirect, :4226-4228).
- **Structure**: `brcxt` (brackets `(){}[]<>`, :3317/2068), `qocxt` (quotes, pop-mode),
  `fccxt` (line-first-char stack), `htcxt` (HTML-entity, limit 0xfff), `colcxt`
  (ColumnContext: rows, table cells via `{| |- | ||`, above-cell byte; col length cap 31,
  :1919-2066). `BrFcIdx`/`FcIdx` = 3-bit compressed bracket/first-char class via `fcy`/`fcq`
  LUTs (:3599-3618, :4087-4167).
- **Parsing state flags**: `isMath/isPre/isNowiki/isText` (tag boundary detection,
  :3946-3963), `isParagraph`, `fc` (first char of line), `utf8left`, `u8w` (UTF-8 word hash,
  :4231-4241), `number0/1, numlen0/1` (number parser, :3857-3871), `deccode` (decoded
  dictionary word index, :3824-3851).

### 2.2 Slot-by-slot wiring (gating column = condition that replaces set with sets()/0)

| Slot | Context recipe | Gated by | line |
|---|---|---|---|
| cmC2[0] ×3 | orders 3,4,5 (`t[3..5]`) | skip when `fc==SPACE && c1==SPACE` | 3779-3784 |
| cmC2[1] | order 6 `t[6]` | — | 3785 |
| cmC2[2] | order 8 `t[8]` | — | 3786 |
| cmC2[3] | order 13 `t[13]` | — | 3787 |
| cmC[4] | `brcxt.context<<8 + c1` | — | 3752 |
| cmC2[4] ×2 | `word00+number0*191+numlen0+u8w`; `h+word1` | col<2 / fc==SPACE; 2nd also `lastfc=='&'` or utf8 | 4250-4261 |
| cmC2[17] ×2 | `worcxt1.Word(1)*53+Word(2)*11+h+(lastWT&0xf)`; `worcxt.Last(1,Verb)+worcxt.Word(1)*83+h` | `brcxt.cxt==LESSTHAN`; **Verb-typed lookup** | 4262, 4375 |
| cmC2[5] ×6 | `h+word2*71`; `worcxt.Word(4)*53+worcxt1.Word(1)+h+stream3b&511`; `worcxt.Last(4,Type(4)^Verb)*53+sVerb+h`; `fword*53+worcxt1.Word(1)+h`; `worcxt2.Word(1)+Word(2)*11+word00+c1`; `worcxt2.LastIf(1,Type(1)&Verb)*11+word00+c1` | ESCAPE/col<2/utf8/fc==SPACE; rest also `brcxt==LESSTHAN`. **Heavy stemmer gating: Verb/sVerb lookups** | 4264-4282 |
| cmC1[6] | `h+(worcxt.Type(1)&0x1FF)+worcxt1.Word(1)` | **word-type bits 0-8 in context** | 4284 |
| cmC2[6] | `(stream2b&15)<<16 + t[2]&0xffff` (order 2) | — | 4285 |
| cmC2[7] | `indirectBrByte` | ESCAPE/utf8/`fccxt==CURLYOPENING` → set(0) | 4287-4290 |
| cmC2[8] ×4 | indirectBrByte+stream4b+BrFcIdx; `stream3bR*4+stream2b&3`; fccontext+stream3bR+BrFcIdx; `c4&0xffffff+stream2b` | 4th skipped when `fccontext==HTLINK` | 4292-4298 |
| cmC1[0] ×2 | lastfc/fccontext/stream3b/brcontext; lastfc+order-3 bytes | — | 4300-4301 |
| cmC1[1] ×3 | `stream2b&3 + word00*11`; `c4&0xffff` (o2); fc/c1/stream2b | — | 4303-4305 |
| cmC1[2] ×4 | stream2b+stream3b; `c1 + col*(c1==SPACE)`; `isParagraph?firstWord:fc<<11`; `91*83*worcxt.Word(1)+89*word0` | 4th: ESCAPE/fc==SPACE/utf8 | 4307-4314 |
| cmC1[4] ×5 | `c1+(stream3b&0xe38)<<6`; `worcxt.fword*11+BrFcIdx`; `c1+word0+number0*191`; o2+fccontext+fc; stream3bR+stream2b | 1st: fc==SPACE | 4316-4324 |
| cmC[0] ×7 | **mode switch**: paragraph → (fword, h+firstWord*89, word0*53+c1+BrFcIdx) vs column → (above byte+collen+streams, h+firstWord*89, above/col/numlen/above1); list (`lastfc=='*'`) → (word0+fccontext+BrFcIdx, c1, word0) vs table → (wrt_2b[above-cell byte]+fccontext, above-cell byte+c1, word0+wrt_2b[above-cell]); 7th: `indirectByte&0xff00 + 257*worcxt.Word(1)*53+c1` | all skipped on ESCAPE; 7th on isMath | 4327-4354, 4361 |
| cmC[1] ×3 | `(stream3b&0x7fff)*word0+BrFcIdx`; `x4&0xff0000ff + stream3b`; `indirectBrByte&0xffff + stream3b` | — | 4356-4358 |
| cmC[2] ×2 | c1+indirectByte+fc; `c4&0xffff + (c2==c3)` | — | 4363-4364 |
| cmC1[3] ×2 | `(stream3b&stream3bMask)*256 | stream2b&stream2bMask` (word-boundary masked); `x4` | — | 4366-4367 |
| cmC2[9] ×4 | `257*pWord.Hash + fccontext + 193*(stream3b&stream3bMask)` (**stemmed word**); fc+stream2bR+c1; `x4&0xffff00+brcontext+fccontext`; `linkword` / `senword*1471+c1` / 0 | isMath skips; HTML/`<` skips 4th | 4370-4389 |
| cmC2[16] | `worcxt.fword*83+(stream2b&15)*11+brcontext` (category/language links) | — | 4374 |
| cmC2[10] ×6 | `indirectByte`; indirectByte+streams; `x4>>16 + stream2b`; c1-or-codeword + indirectWord; fccontext/BrFcIdx/o2/stream2b; indirectWord+streams | 5th: isMath | 4391-4397 |
| cmC2[11] ×5 | words/spaces bitmaps+streams+isParagraph; `c1+stream3b<<5`; `stream2bR*16+BrFcIdx`; indirectByte+stream2bR+brcontext; `indirectWord0Pos + indirectByte` | 5th: `fccontext==FIRSTUPPER && brcontext==SQUAREOPEN` | 4399-4409 |
| cmC2[12] ×2 | sparse `x4` (`(x4&0x80f00000)+((x4&0x0000f0ff)<<12)`); paragraph → `h+worcxt.Word(1)*53*79+Word(3)*53*47*71` vs column → above bytes / `c4<<16` if col==31 | ESCAPE/HTLINK/`{`/isMath/isPre; column: HTLINK/`<`/htcxt | 4412-4434 |
| cmC2[13] ×2 | `worcxt.Word(1)*83*1471 - word0*53 + worcxt.Word(2)`; `h+Word(2)*53*79+Word(3)*53*47*71` (**stemmed 3-grams**) | giant gate: ESCAPE/utf8/`{`/HTLINK/HTML/htcxt/fc==SPACE/isPre/`&`/`<`/isMath/col<2/backslash (:4436) | 4436-4447 |
| cmC[3] ×2 | stream3bR/stream2b/fc/BrFcIdx; `(linkword?linkword:word0)*3301 + number0*3191` | — | 4450-4452 |
| cmC2[14] | `BrFcIdx + worcxt.Word(2)*(stream3bR&stream3bRMask2) + (worcxt.Type(1)&0x1ff)` (**type bits in context**) | same giant gate as cmC2[13] | 4454-4463 |
| cmC1[7] ×4 | `worcxt1.Word()+word00`; `worcxt.Word(2)+word0*191+stream3bR&63`; `word0*191+stream3bR&63`; `indirectWord0Pos&0xffff*191+word0+stream3bR&63` | ESCAPE/utf8/fc==SPACE | 4466-4474 |
| cmC[5] | `fccxt.context&0xff00 + c1 + (stream2b&12)*256 + (brcontext+brcxt.last())<<24` | — | 4170 |
| cmC2[15] | `BrFcIdx*256 + fc + (stream3bR&0xFFF)<<16` | — | 4490 |
| rcmA[0] | `word3*53 + c1 + 193*(stream3b&0x7fff)` | — | 4248 |
| scmA[0..6] | c1; `c2*isParagraph`; indirectWord>>16; stream3b&0x1ff; stream2b&0xff; brcontext; `isParagraph+2*(stream3bR&0x3f)` | — | 4476-4482 |
| smA[0..2] (match) | denselength/expectedBit/bpos; expectedByte/bpos/c1; delta-mode expectedByte/c0 | active only with a live match | 3569-3578 |

### 2.3 Where the stemmer (word-type) logic gates things

The Porter2-derived `EnglishStemmer` (:2581-3127) assigns `Type` flags
(Verb/Noun/Adjective/Plural/Article/Conjunction/Adposition/Male/Female/Number/… enum at
:2289-2310) at word end inside `setbufstem()` (:3645-3690). Gates driven by it:

1. **Stream membership** (:3682-3688): `worcxt` ← all words; `worcxt1` ← excludes
   `Conjunction|Article|Male|Female|Number|ConjunctiveAdverb` and requires
   `brcxt.cxt!=LESSTHAN`; `worcxt2` ← only words *with* a type, additionally excluding
   `Adposition|AdverbOfManner`.
2. **Word-order skip** (:3883-3888): `word1..3` are not shifted for
   `ConjunctiveAdverb|Conjunction` words (disabled after `blpos>463139793`).
3. **Bit-stream markers** (:3889-3912): Number → `+1` into stream3b/3bR; Conjunction →
   `<<7` (and clears `senword`); Article → `+2`; Adposition (or PresentParticiple in
   paragraph) → repeats last 2-bit class into stream2b/2bR.
4. **AdverbOfManner removal** in paragraphs (:3914-3918); **Article+Noun merge** rewrites
   the sentence stream (:3920-3931); consecutive **Numbers merge** (:3674-3680);
   "last word was 'the' ⇒ Noun" heuristic via `lastArt` (:3666-3671); `sVerb` = hash of
   last verb (:3663).
5. **Context lookups by type**: `worcxt.Last(…,Verb)`, `LastIf(…,Verb)` (cmC2[5], cmC2[17]),
   `Type(1)&0x1ff` direct type bits (cmC1[6], cmC2[14]), `lastWT` nibbles (cmC2[17]),
   `getWT()` 4-bit class (:3627-3643).
6. **Time-gated word lists**: `VerbWords1` matching disabled after `x.blpos>451531986`
   (:3119); `deccode` updates stop after `blpos>448131719` (:3837, :3848).
7. **MatchModel2 seeding**: `worcxt.Word(1)` stem hash is a 4th match-hash candidate source
   (:3532-3536).

---

## 3. Per-bit hot path

Entry: `FXCM::Perceive(bit)` (:4820) → `update1()` (:4679) → `modelPrediction()` (:3717).

### 3.1 Train phase (`update1`, every bit, :4679-4717)

- 12 × `Mixer1::update()` (:4702-4713): each is one AVX2 `train()` pass —
  **10 passes of N=512** (32 `_mm256` iterations each) + 2 passes of N=16.
  Error deadzone `elim` is adapted per byte: `+1` (cap 256) when last byte had no fails,
  `-1` (floor 0, cap 16) otherwise (:4688-4691) — this is the "skip updates when
  predicting well" speed lever; with err inside ±elim, `train` is skipped entirely (:543, :495).
- fails/failz bookkeeping (:4719-4725), thresholds `e_l[bpos]` (:3141) and 848.

### 3.2 Predict phase (`modelPrediction`)

Per **byte** (bpos==0 only, :3721-4495): all parsing of §2.1, stemmer on word end, 13 order
hash updates, ~81 context `set()` hashes, MatchModel2 update (4 hash-table probes + inserts,
:3510-3541), SparseMatchModel update (4 hashes, :1679-1719).

Per **bit**, in order:

| Step | Work | Mixer inputs added | lines |
|---|---|---|---|
| 7 × `scmA.mix(sscmrate)` | U16 EMA update, rate 7/8 | 14 (7 stretched + 7 linear) | 4501-4507 |
| `MatchModel2mix()` | candidate update, best-pick; ≤3 `smA` StateMap1 set+update | 7 | 4509, 3544-3595 |
| `smatch.p()` | bit-check vs expectedByte | 2 | 4510, 1721-1747 |
| **31 × ContextMap.mix()** (18 cmC2 + 6 cmC + 7 cmC1) covering **81 context slots** | per live slot: state transition `nex()`, BH bucket probe on bpos 0/2/5 (14/7/3-way checksum scan = the main cache-miss source), `StateMap.set` (1 U32 RMW), run-byte check | ~6 per slot ≈ 480 | 4512-4548, mix1 at 1025/1230/1464 |
| `rcmA[0].mix()` | MTF hash probe | 1 | 4549 |
| LSTM input | `stretch(lstmpr)` | 1 | 4663 |
| **10 × `mxA[0..9].p1()`** | dot_product N=512 (32 AVX2 madd iters each) | 10 (into mxInputs2) | 4664-4673 |
| 2 × final `p1()` N=16 | mxA[10] (224 ctx), mxA[11] (1 ctx) | — | 4675 |
| output | `squash((mxA[10]*7 + mxA[11] + 4)>>3)` | — | 4675 |

`x.mxInputs1.ncount` is fixed at `(515+16+1-5*2-2*2)&-16 = 512` (:3265) — every one of the
10 big dot products and trains runs over the full 512 vector regardless of how many inputs
are semantically live. **mxA count × N is the dominant per-bit FLOP cost: 10×512 MACs predict
+ 10×512 train ≈ 10K MACs/bit, plus ~81 hash-bucket touches/bit.**

### 3.3 APM/SSE chain (back in `update1`, :4730-4754)

6 APM stages per bit, each a 33-point interpolated table with rate-controlled update:

```
pu = (apmA0.p(pr, c0, rate=3) + 7*pr + 4) >> 3                  :4730
pu = apmA3.p(pu, (c0*2)^AH1, rate)                               :4738
pv = apmA1.p(pr, (c0*8)^hash(29,failz&2047), rate+1)             :4740
pv = apmA4.p(pv, hash(c0, stream2b|stream2bR sel by fails, s3bR), rate)  :4743-4746
pt = apmA2.p(pr, (c0*32)^AH2, rate)                              :4748
pz = apmA5.p(pu, (c0*4)^hash(min(9,pz), x5&0x80ff), rate)        :4750
pr = fails ? (6pt+pu+11pv+14pz+31)>>5 : (4pt+5pu+12pv+11pz+31)>>5  :4752-4753
```

`rate = 6 + (blpos>14*256*1024) + (blpos>28*512*1024)` (:4695). `AH1/AH2` from `x5` hash
(:4492-4493). Each intermediate is exported to cmix via `AddPrediction` (:4739-4754).

---

## 4. Hyperparameter census

### 4.1 fxcm mixers (fxcmv1.cpp:3244-3255)

| Mixer | M (contexts) | shift1 | elim | uperr | role / context (set at) |
|---|---|---|---|---|---|
| mxA[0] | 2048 | 237 | 8 | 69 | streams 2b/3b + BrFcIdx (:4566-4571) |
| mxA[1] | 1536 | 204 | 8 | 19 | c0/words/stream3bR/FcIdx (:4579-4586) |
| mxA[2] | 6144 | 70 | 1 | 34 | words+ordX+stream2b (:4590) |
| mxA[3] | 2048 | 54 | 1 | 23 | bpos+words|numbers+c0 (:4606) |
| mxA[4] | 1536 | 55 | 1 | 24 | c0/streams/ordX/isMatch/isParagraph (:4626-4646) |
| mxA[5] | 7168 | 55 | 1 | 24 | ordW+streams+FcIdx (:4650) |
| mxA[6] | 0x4000 | 70 | 1 | 34 | stream3bR+words+stream2b (:4594) |
| mxA[7] | 0x4000 | 55 | 1 | 24 | stream3b+BrFcIdx+words+isMatch (:4655-4658) |
| mxA[8] | 0x20000 | 55 | 1 | 24 | **deccode** = dictionary word idx (:4495) |
| mxA[9] | 0x20000 | 55 | 1 | 24 | bpos+fails+**lstmex** (:4661) |
| mxA[10] | 224 | 6 | 0 | 4 | final: ordX/BrFcIdx/stream2b/words (:4613) |
| mxA[11] | 1 | 6 | 0 | 4 | final helper, ctx 0 |

Related: initial weight 129 (:570); err = `((y<<12)-pr)*uperr/4` clamped ±32K (:538-543);
prediction `dot*shift1>>11` (:550, :555); final blend `(mx10*7 + mx11 + 4)>>3` (:4675);
elim adaptation bounds 256 / 16 (:4689-4691).

### 4.2 ContextMap scaling tables (per-instance, 27 slots — direct tuning vector)

- `c_r[27]` run-context multiplier (:3136)
- `c_s[27]` StateMap-prediction multiplier `st1` (:3137)
- `c_s3[27]` state-prior multiplier `st32` (:3138)
- `c_s4[27]` one-sided state multiplier `st8` (:3139)
- `st2_p1 = 12`, `st2_p2 = 14` linear-prediction multipliers (:4778-4781); `st2_p0` is all-zero.
- `kep` (keep flag OR'd into BH LRU nibble): 0xf0 vs 0 per instance (§1 tables).
- `skip2` (adds the st2 input): 1 for most, 0 for cmC1[0], cmC[1], cmC[2], cmC1[3], cmC2[15], cmC1[6]… (see Init args, col 7).

### 4.3 Adaptive-rate / SSE constants

| Constant | Value | Effect | line |
|---|---|---|---|
| `e_l[8]` | {1830,1997,1973,1851,1897,1690,1998,1842} | per-bpos fail threshold | 3141 |
| failz threshold | 848 | secondary fail counter | 4725 |
| `tri/trj` | {0,4,3,7}/{0,6,6,12} | fails→pz APM context | 3132, 4732-4734 |
| apmA0 rate | 3 (+ blend 7:1 with pr) | first SSE stage | 4730 |
| APM `rate` | 6 (+1 at blpos>3.67M, +1 at >14.68M) | stages 2-6 | 4695 |
| final APM blends | 6/1/11/14 vs 4/5/12/11 (>>5) | fails-conditional | 4752-4753 |
| `sscmrate` | 0→1 at blpos>14*256*1024 | scmA learning-rate slowdown | 4693, 768 |
| SmallStationary rate | `r+7`, divisors 4 and 8 | scm input scaling | 767-774 |
| StateMap1 limit | 1023 (smA all three) | count cap | 3231-3233 |
| `dt[i]` | 4096/(i+2) | StateMap1 adaptation curve | 4760-4763 |
| RunContextMap `rcm_ml` | 6 (default 8) | run scaling when count even | 3263, 680-690 |
| `cxtMask` init / skip logic | per-cm | zero first-occurrence contexts | 925, 1029 |

### 4.4 Match models

| Constant | Value | line |
|---|---|---|
| MatchModel2 orders `LEN1/LEN2/LEN3` | 5 / 7 / 9 bytes | 3351-3353 |
| `MAXLEN` | 62 | 3143 |
| `MINLEN_RM` (recovery) | 3 | 3350 |
| `matchN` candidates / `mHashN` positions | 4 / 4 | 3455, 3340 |
| hash table | 0x200000 entries | 4783 |
| input scale | `sign*(length<<5)`; denselength piecewise at 16 | 3572, 3563-3567 |
| SparseMatchModel configs | minLen {3,4,6,5}, stride {1,1,2,1}, MaxLen 64, MinLen 2, 4 hashes, 1M-entry table | 1648-1669 |
| SparseMatch input scale | `sign*(min(len-1,32)<<5)`, `sign*(1<<min(len-2,3))*min(len-1,8)<<4` | 1734-1735 |

### 4.5 Structure parsers

| Constant | Value | line |
|---|---|---|
| ColumnContext line cap | 31 (`Init(l=31)`), row buffer 2048 | 1934, 1922 |
| BracketContext stack | 512 deep; distance limit 256 (U8) / 4095 for htcxt | 1862, 3324 |
| WordsContext depth | 256 words (`vec<…,64*4>`) | 2077-2080 |
| MTFList size | 4 (= NumHashes) | 1664 |
| word-hash multipliers | 2104, 271, 83/53/47, 89/91/79/71/1471/3301/3191/193/257/11 | 3811, 3885-3887, §2.2 |
| dict split | dict1size=80, dict2size=32 (codeword decode) | 363-364 |
| **blpos magic gates** | 451531986 (VerbWords off, :3119); 448131719 (deccode freeze, :3837/:3848); 463139793 (conj word-order skip off, :3884) | |
| buffer/window | 16 MiB (`BMASK=0xffffff`) | 3170-3171 |

### 4.6 cmix-glue layer (predictor.cpp)

| Item | Value | line |
|---|---|---|
| PPMD | order 25, 14000 MB | 56 |
| LSTM | 200 cells, 1 layer, horizon 128, lr 0.03, clip 10 | 131-132 |
| LSTM override | output exactly 0.0/1.0 bypasses entire ensemble | 223-225, 243-245 |
| layer-0 mixer lrs | 23 mixers: 0.005 ×8, 0.0005 ×4, 0.001 ×6, 0.002 ×2, 0.0007, 0.0003 (layer-1) | 143-170 |
| indirect deltas | 200 (word), 400 (double-indirect), 300 (bracket) | 60, 117, 52 |
| match models | limit 200, delta 0.5, ≤2e6 entries | 88, 97-99 |
| bracket model | (200, 10, 100000) | 47 |
| layer weight decay | 1.0e-4 | 135-136 |
| auxiliary context | avg(fxcm, LSTM) discretized ×15 | 229-231 |
| SSE (final) | Shelwien SSEi: 7 quant levels, SCALElog 15 | mixer/sse.cpp:22-35 |
| build defines | SEED=923, UPDATE_LIMIT=3000 | build_and_construct_comp.sh:6-7 |

---

## 5. State-table generation (`StateTable`, fxcmv1.cpp:237-339)

Each bit-history state is a point `(x, y)` = (#zeros, #ones) on a bounded lattice, packed
into ≤256 states of 4 bytes: `{next-if-0, next-if-1, x, y}`. Six tables are generated at
startup and copied into `STA1..STA7` (:342-347):

```
statetable.Init(s0,s1,s2,s3,s4,s5,s6, table)   // fxcmv1.cpp:334
//             b[0..4] = per-y caps on x; b[5] = cap on x+y for dual states; mdc = s6
STA1: (28, 28, 31, 29, 23, 4, 17)   :4787  → cmC2[6,15], cmC[4,5], cmC1[3]
STA2: (32, 28, 31, 28, 21, 5,  6)   :4788  → cmC1[2,7], cmC[0,2,3]
STA4: (31, 27, 30, 27, 24, 4, 27)   :4789  → cmC2[8]
STA5: (33, 31, 31, 24, 20, 4, 33)   :4790  → cmC2[7,10,11], cmC[1]
STA6: (28, 29, 30, 30, 23, 3, 22)   :4791  → cmC2[0-5,9,12,13,14,16,17], cmC1[0,6]
STA7: (28, 29, 33, 23, 23, 6, 14)   :4792  → cmC1[1,4]; also pre1[] precalc (:4793)
```

Mechanics:

- **`num_states(x,y)`** (:244): a lattice point is representable iff `y < 5` (B=5; by
  symmetry the minority count never exceeds 4) and `x < b[y]`. It yields **2 states**
  instead of 1 when `y>0 && x+y < b[5]` — the duplicate encodes "which bit came last",
  giving recency information for young, mixed histories. So `s0..s4` set how far the
  majority count can run for minority counts 0..4 (the shape of the LFU lattice), and
  `s5` sets the radius of the "remember last bit" zone.
- **`discount(x)`** (:251): when the *opposite* bit arrives, a majority count `x>2`
  collapses to `min(x, mdc-1)`. **`s6=mdc` is the nonstationarity knob**: small (STA2's 6)
  ⇒ aggressive forgetting on contradiction; large (STA5's 33) ⇒ nearly-stationary counts.
- **`next_state(x,y,b)`** (:260): increments the observed side, discounts the other, then
  projects back onto the representable lattice by walking down
  (`x=(x*(y-1)+y/2)/y; --y`) until `t[x][y]` exists — i.e. out-of-lattice histories are
  re-scaled proportionally.
- **`generate()`** (:283): enumerates lattice points in increasing total count `x+y`
  (so state index ≈ maturity, which ContextMap uses as the LRU-replacement priority,
  comment at :806-808), assigns state numbers, then fills `ns[state*4]` with both
  transitions; stops at 256 states (:315, :328). `Init` memcpys the 1024-byte table (:337).

Downstream consumers of `n0,n1` (`ns[s*4+2..3]`): `StateMap.Init` priors
(`(n1*3+1)/(n0+n1)` :602-606), `ContextMap` `st8/st32` precalc (:958-973) and `pre()`
(:913-917), `pre2`/`pre1` (:1600-1605).

**Experiment surface**: 6 tables × 7 small ints, evaluated cheaply (table regenerates at
startup; no format coupling). fx2 already gained by swapping one table; nothing constrains
s-vectors to the current values besides `state≤256` saturation — note `generate()` silently
truncates when the lattice exceeds 256 states, so larger b-values trade breadth of the
mature region against the dual-state recency zone. Per-table assignment (which STA each cm
uses, §1 tables) is an equally cheap discrete search axis — e.g. all the big word maps share
STA6 (mdc=22) while the indirect maps got STA5 (mdc=33).

---

## 6. Quick wins / oddities noticed while mapping

1. **cmC1[5] is a dead slot** — declared in `ContextMap1 cmC1[8]` (:3202) but never
   Init'd or mixed; harmless but indicates the array sizes are not load-bearing.
2. **mxA[8]+mxA[9] are 256 MiB of the 308 MiB mixer budget** (0x20000 contexts each)
   keyed on `deccode` and `bpos/fails/lstmex`; their M could be halved/reshaped for
   memory to feed e.g. cmC2[13] (word 3-grams, currently 512 MiB at 14-way).
3. All 10 big mixers share **N=512** even though only ~510 inputs are live; the
   `(515+16+1-…)&-16` arithmetic (:3265) means adding ≤ a few inputs is "free" in
   FLOPs (rounds within the same 512), removing 3+ models saves a full AVX2 stripe only
   at multiples of 16.
4. The three **blpos magic constants** (:3119, :3837, :3848, :3884) are tuned to enwik9
   article positions — they must be re-tuned for any change to the preprocessor ordering.
5. `ContextMap2.Init` asserts `sizeof(E<3,32>)==32` (:1375) — copy-paste from
   ContextMap1; the real element is `E1<14,128>`. Cosmetic.
6. `apmA1/apmA2` masks (`&0xffff`) address only half of their `0x8000*2`-context tables'
   33-point rows... they are sized S=0x10000 and masked to 0xffff — exactly full. apmA3-5
   are S=0x40000 masked `&0x3ffff` — also full. No waste, but rates (3/6/7/8) and the two
   blend-weight vectors (:4752-4753) are pure tuning numbers.
