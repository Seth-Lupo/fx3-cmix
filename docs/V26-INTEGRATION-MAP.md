# V26 Integration Map — porting standalone fxcm v26 into the fx2-integrated model

> Sources read line-by-line on 2026-06-10:
> `standalone/fxcm.cpp` (5,861 lines, kaitz fxcm v26 + our ~30 marked Linux/UB edits),
> `src/models/fxcmv1.cpp` (4,824 lines, VERSION 22, the fx2-integrated model),
> `src/predictor.cpp` (cmix glue), `src/models/fxcmv1.h`.
> Cross-references: `docs/FXCM-INTERNALS.md` (verified fx2 map), `docs/RESEARCH-CANDIDATES.md`
> (§kaitz ladder). Line refs are `fxcm.cpp:N` (standalone v26) and `fxcmv1.cpp:N` (fx2).
> The stemmer bodies are byte-identical except the Pronoun addition (verified by
> whitespace-normalized diff of fxcm.cpp:2502-3061 vs fxcmv1.cpp:2581-3140).

---

## 1. Interface delta (standalone I/O vs cmix glue)

### 1.1 Entry points and driver

| Aspect | standalone v26 | fx2-integrated |
|---|---|---|
| Driver | own range coder `Encoder` + `main()` (fxcm.cpp:5641-5861); calls `code()/decode()` → sets `x.y` → `update()` → `ResetPredictions()` | cmix coder; `FXCM::Perceive(bit)` sets `fxcmv1::x.y` then `predictor_->update()` → `update1()` + `ResetPredictions()` (fxcmv1.cpp:4801-4823, predictor.cpp:312) |
| Per-bit update fn | `update()` (fxcm.cpp:5524-5615) | `update1()` (fxcmv1.cpp:4679-4756) |
| Prediction fn | `modelPrediction()` no args (fxcm.cpp:4836) | `modelPrediction(x.c0,x.bpos,x.c4)` (fxcmv1.cpp:3717, called :4727) |
| Final output | internal `pr`, consumed by own coder | `pr` never used by cmix directly; cmix consumes the exported predictions array |
| Pretrain path | none | `Predictor::Pretrain` calls `fxcm_model_.Predict()` only (predictor.cpp:316-348) — fxcm sees no pretrain bits |

### 1.2 Prediction export — reconciling 560 (standalone) vs 431 (fx2 exported)

Both files funnel **every mixer input** through `AddPrediction` inside `Inputs::add`, but the
semantics differ:

- **fx2** (fxcmv1.cpp:93-106, 188-197): `num_models = 439+1-2-7 = 431`;
  `AddPrediction(squash(p))` stores **float probabilities** (`p * 1/4095`) in
  `std::valarray<float> model_predictions`, exported via `FXCM::Predict()`
  (fxcmv1.cpp:4812-4818) and fanned into cmix layer-0 (predictor.cpp:182-187).
  Items deliberately *excluded* from export via `prediction_index--`:
  per-slot "new context" marker `add(32*2)` in all three ContextMap classes
  (fxcmv1.cpp:1000,1009,1020,1206,1215,1225,1440,1449,1459), the SSCM linear duplicate
  (:774), and the two cmix-LSTM feedback inputs (:4663, :4674).
- **standalone** (fxcm.cpp:82-94, 166-176): `num_models = 560`;
  `AddPrediction(clp(p))` stores **stretched shorts** (−2047..2047) in
  `short *model_predictions1`. Nothing leaves the process: the vector is the input of the
  four internal "fp mixers" `mxA2[0..3]` (`setTxWx(num_models, model_predictions1)`,
  fxcm.cpp:3667-3668). Excluded via `prediction_index--`: SSCM linear duplicate (:843) and
  the 19 per-context `pre1[state]` inputs of the DirectStateMaps (:3394).

Composition of the 560: ~505 layer-0 inputs (mxInputs1) + 17 layer-1 inputs (mxA[0..16]
outputs, :5496-5512) + 6 layer-2 inputs (mxA[17] + mxA1[0..4], :5513-5519) +
`AddPrediction(64)` bias (:5368) + 7 update-level values `stretch(pr)`, `pu, pv, pv', pt, pz,
pr_final` (:5570-5596). The fx3-cmix README's "~610 fxcm predictions, ~487 fed to cmix" implies
the integrated fx3 exported a *subset*; our port must choose: (a) export all 560 as floats
(mechanical: re-add `conversion_factor`, squash at add-time), or (b) replicate kaitz's split —
keep mxA2/mmmO equivalents on the cmix side (see §4) and export ~487. The 431→560 delta is
dominated by: +new CM slots (≈ +94 from cmC2[18..20], cmC44, cmC4[8], cmcr×9, cmcr2×4,
cmCR×3 minus per-slot trims, see §2), +13 extra mixer outputs, +StationaryMap×2 (4),
+DirectStateMap mix outputs (5), −SparseMatchModel (2), −4 SSCMs (4), −marker inputs
(the `32*2` markers are gone entirely in v26 classes).

### 1.3 Contexts shared with cmix

- fx2 exports `wrtcxt = deccode` (fxcmv1.cpp:45, set at :4494) which cmix uses as `mx19cxt`
  mixer context (context-manager.cpp:205; mixer added predictor.cpp:152). **The standalone has
  no `wrtcxt`** — `deccode` only feeds its own `mxA[8].cxt` (fxcm.cpp:5486). Port must re-add
  the export (one line at the same spot, after parseByte).
- fx2 consumes cmix LSTM: `extern int lstmpr, lstmex` (fxcmv1.cpp:44; producer predictor.cpp:175,
  310-311), injected as 2 mixer inputs (:4663, :4674) and as mxA[9] context (:4661). The
  standalone has neither; v26's mxA[9].cxt is `(stream3bR&511)*256+FcIdx*32+isParagraph*16+
  (lastWT&15)` (fxcm.cpp:5487). Port decision: keep the LSTM inputs (they are load-bearing in
  fx2) and re-map them into the 544-wide input vector; keep lstmex either as an extra mixer or
  fold into mxA[9]'s new context.
- New export candidates from v26 for cmix-side mixer contexts (§4): `stream5b` (fxcm.cpp:5237),
  `PState/PStateH` (:3517), `mstate` (:4833/5366), `isXML` (:3153).

### 1.4 Dictionary loading

| | standalone v26 | fx2-integrated |
|---|---|---|
| Source | `fopen("english.dic","rb")` from cwd, hard crash if absent (fxcm.cpp:453-465) | `fopen(".dict","rb")`, tolerated if absent via `isDictLoaded` (fxcmv1.cpp:407-423); `.dict` is produced by the cmix self-extract/runner (runner.cpp:356,413,452; readalike_prepr/self_extract.h:79) |
| Word lengths | `dictWLen[44515]` stored (fxcm.cpp:345,388) — needed by `procWord` to emit decoded chars | not stored; fx2 keeps `so` pointer only (fxcmv1.cpp:433-435) |
| Special codewords | captures 28 codeword indices at load: `cwTEXT/NOWIKI/MATH/PRE/PAGE/IMAGE/CATEGORY/USER/WIKIPEDIA/TABLE/TD/SEE/ALSO/EXTERNAL/LINKS/REFERENCES/BIBLIOGRAPHY/IS/WITH/THE/ON/IN/WWW/HTTP/ISBN…` (fxcm.cpp:353-427) | none — tag state machines are byte-pattern driven (fxcmv1.cpp:3946-3963) |
| In-stream detection | partial codeword decode per byte (`dcw/dcwl`, fxcm.cpp:4287-4303) — same mechanism as fx2 (:3824-3851) | same |

Port: keep `.dict` + `isDictLoaded`, add `dictWLen` and the cw\* capture loop to fx2's
`loaddict`; everything downstream of B3 (§2) depends on this.

### 1.5 Input-vector geometry

- fx2: `BlockData<528+32> x` with `mxInputs1.ncount=(515+16+1-5*2-2*2)&-16 = 512` and
  `mxInputs2.ncount=16` (fxcmv1.cpp:215, 3265-3266); 12 mixers total.
- v26: `BlockData<544> x` plus `Inputs<64> mxInputs2`, `Inputs<64> mxInputs4`;
  `ncount` 544/32/16 (fxcm.cpp:196, 188-190, 3653-3655); 18+6+4 mixers (+4 `mmmO` Mix units,
  +14 Mix units inside DirectStateMaps).
- Both run fixed-N AVX2 dot products over the whole vector regardless of live inputs, so every
  catalog step below that adds/removes inputs must keep `ncount` consistent and ≤ S, in
  multiples of 16 for free FLOPs.

---

## 2. Ordered change catalog (incremental port sequence)

Conventions: **Diff** S/M/L = port difficulty. **RT** = round-trip test point: build, compress
+ decompress a 50 MB dictionary-coded slice (`prof_input`/proxy), assert byte-identical
round-trip and record size delta; "RT-full" adds the full-pipeline cmix run. Every step leaves
a buildable binary; the order is chosen so the count-changing steps are isolated and the
fx2-removed determinism suspect lands last.

Summary table (port order):

| # | Change | Diff | kaitz gain (standalone bytes) | ΔRAM |
|---|---|---|---|---|
| 1 | Match-model hash table ×2 | S | unmeasured | +32 MiB |
| 2 | Final SSE blend retune | S | unmeasured | 0 |
| 3 | st2_p1 12→13; retire st2_p2 | S | unmeasured | 0 |
| 4 | Mixer WUS cap 256→319 | S | part of "~40% L0 skip" | 0 |
| 5 | APM A4/A5 halved + templated APM | S | unmeasured | −16.5 MiB |
| 6 | Remove SparseMatchModel | S | (re-removal) | −4 MiB |
| 7 | Remove 4 SmallStationaryContextMaps | S | unmeasured | −0.6 MiB |
| 8 | Pronoun word type | S | part of #16 in RESEARCH-CANDIDATES | 0 |
| 9 | skipM1 long-match context skipping | S | +2,244 then +8,786 (thread 4116 p2 #9/#13) | 0 |
| 10 | Codeword machinery (cw\*, procWord, tag FSMs) | M | gates many below | ~0 |
| 11 | See-also/References/Category skipping | S | in v26 changelog (cheap variant works) | 0 |
| 12 | PState/PStateH page-state contexts | S | unmeasured | 0 |
| 13 | worcxt0/worcxt3; Word0(); drop word1..3 | M | unmeasured | ~0 |
| 14 | Number-position indirect (np[]) | S | unmeasured | +0.3 MiB |
| 15 | StationaryMap ×2 | S | unmeasured | +127 MiB |
| 16 | wt3cxt/wt4cxt type-hash contexts + cmC2[20] | M | unmeasured | +256 MiB |
| 17 | SentenceContext ×4 + cmC2[18,19] | L | ≈ +107,917 ("basic sentence management") | +193 MiB |
| 18 | cmcr sparse-indirect family (s5bByte/indirect2/3/s2Word0) | M | unmeasured | +288 MiB |
| 19 | XML model + cmC44 | M | unmeasured | +32 MiB |
| 20 | ContextMap3/4 class swap + scaling retune | L | inside the unlabeled ladder waves (~896k total) | ~0 |
| 21 | CM memory bumps (cmC2[4,5,8], cmC[0], cmC4[1,2,4,6]) | S | cf. predictor-gains doc / candidate #8 | +642 MiB |
| 22 | Per-article CM resets | S | "DMC-like reset insight"; v26 changelog | 0 |
| 23 | Mixer restructure 12→24, 3 layers | L | inside ladder waves | +166 MiB |
| 24 | fp-mixer bank mxA2×4 + mmmO final chain | M | plausibly the "Shelwien mod_sse+sh_v2f" +214,384 | +105 MiB |
| 25 | DirectStateMap ×5 (InDirectStateMap, order-w mixing) | M (high risk) | re-adds fx2-removed component (~10-50k) | +609 MiB |

### Step 1 — Match-model hash table ×2

- **Where**: fxcm.cpp:5802-5803 (`mhashtablemask=0x200000*2-1`) vs fxcmv1.cpp:4783-4784
  (`0x200000*1`). Everything else in MatchModel2 is identical (verified fxcm.cpp:3771-4027 vs
  fxcmv1.cpp:3339-3595, including the `worcxt.Word(1)` 4th hash both have).
- **What**: doubles match-position table 32→64 MiB.
- **Deps**: none. **Diff**: S. **RT**: RT after change; expect tiny gain (kaitz: "match table
  is small, maybe double memory will help", thread post 25).

### Step 2 — Final SSE blend retune

- **Where**: fxcm.cpp:5594-5595 vs fxcmv1.cpp:4752-4753. The `fails` path is unchanged
  (6,1,11,14); the clean path changes `(4·pt+5·pu+12·pv+11·pz)` → `(4·pt+7·pu+12·pv+9·pz)`.
- **Deps**: none. **Diff**: S (2 constants). **RT**: yes.

### Step 3 — st2_p1 multiplier 12→13; retire st2_p2

- **Where**: fxcm.cpp:5789-5792 vs fxcmv1.cpp:4778-4781; consumer change: cmC[3] uses
  `st2_p1` in v26 (fxcm.cpp:3707) where fx2 used `st2_p2` (fxcmv1.cpp:3302).
- **What**: the linear ContextMap secondary input scale becomes 13/256·(p−2048) for all users.
- **Deps**: none. **Diff**: S. **RT**: yes (two sub-steps if you want finer bisect: multiplier,
  then cmC[3] table swap).

### Step 4 — Mixer weight-update-skipping cap 256→319

- **Where**: fxcm.cpp:5531-5537 (`elim=max(256+63, elim+1)` on clean bytes, over all 18 L0
  mixers) vs fxcmv1.cpp:4686-4691 (`max(256, elim+1)` over 10).
- **What**: after any zero-fail byte the error deadzone jumps to ≥319 (≈ skip more updates);
  this is the fxcm-side half of the "~40% of layer-0 mixer updates skipped" claim.
- **Deps**: none (apply to fx2's 10 mixers now, re-extend in step 23). **Diff**: S.
- **RT**: yes — also wall-clock check; this is a speed lever.

### Step 5 — APM sizes / templated APM

- **Where**: fxcm.cpp:1414-1437 (`APM<B>` template with internal `mask`, in-object `t[S*33]`)
  and instances :3554-3559 (`APM<8>,<16>,<16>,<18>,<17>,<17>`) vs fxcmv1.cpp:1542-1563 and
  :3206-3211 (`APM<256>, <0x10000>×2, <0x40000>×3`) with explicit `&0x3ffff/&0xffff` masks at
  call sites (:4738-4750).
- **What**: apmA4/apmA5 halve 0x40000→0x20000 contexts; apmA0 256→256 (B=8), A1/A2/A3
  unchanged sizes. The standalone p() also takes `y` explicitly — cosmetic (fx2 passes x.y too).
- **Deps**: none. **Diff**: S. **RT**: yes. ΔRAM −16.5 MiB.

### Step 6 — Remove SparseMatchModel

- **Where (fx2 only)**: struct fxcmv1.cpp:1653-1772, instance :3225 (`// 2 inputs to fp`),
  `smatch.Init()` :3326, `smatch.p()` :4510. Absent from standalone (v26 changelog: "removed").
- **What**: −2 mixer inputs, −4 MiB table, −4 hash probes/byte. Adjust `ncount` arithmetic
  (fxcmv1.cpp:3265) and `num_models` by −2.
- **Deps**: none. **Diff**: S. **RT**: yes + RT-full (export count changes → cmix layer-0
  width changes; this is the first step that touches predictor I/O width).

### Step 7 — Remove 4 SmallStationaryContextMaps

- **Where**: fx2 has 7 (`scmA[0..6]` Init fxcmv1.cpp:3235-3241, set :4476-4482, mix
  :4501-4507); v26 keeps 3 (fxcm.cpp:3599-3601, :5219-5221, :5301-5303): `c1` (8 bits),
  `stream3b&0x1ff` (9 bits), `brcxt.cxt` (8 bits).
- **What**: drop `c2*isParagraph`, `indirectWord>>16`, `stream2b&0xff`,
  `isParagraph+2*(stream3bR&0x3f)`. −8 mixer inputs (−4 exported), −0.6 MiB.
- **Deps**: none. **Diff**: S. **RT**: yes + RT-full.

### Step 8 — Pronoun word type

- **Where**: enum bit `Pronoun=(1<<20)` fxcm.cpp:2211; `Pronouns[14][5]` table :2239-2254;
  `MatchesAnyP` :2172-2179; stemmer fallback branch :3045-3052 (the **only** stemmer diff vs
  fx2, see header note); `getWT` maps Pronoun→2 (:4049); new `getWT3` (:4054-4077) returns
  21 for Pronoun. fx2 anchor points: enum fxcmv1.cpp:2289-2310, stemmer else-chain :3105-3127,
  `getWT` :3627-3643 (fx2 has no `getWT3`).
- **What**: words matching the pronoun table get a type; `Word.NextW` records which column
  (case form) matched (:2174-2177) — note `NextW` is set but not yet consumed anywhere.
- **Deps**: none, but `getWT3` is consumed by steps 16 and 23 (`oldwt1`, fxcm.cpp:4807).
- **Diff**: S. **RT**: yes.

### Step 9 — skipM1: context skipping on long matches

- **Where**: fxcm.cpp:3482, 4180-4186 (computation: thresholds 61/15/15/15/5/5/13 by
  template/table/link/list/heading/quote/paragraph state), gates at :4845 (cmC2[0]),
  :4885 (cmC2[5] slot 0, threshold 61 inline), :4986-4993 (cmC2[8]), :5000-5005 (cmC4[0]),
  :4979 (cmC2[6], inline `isMatch>61`), :5101 (cmC2[17]), :5187 (cmC2[14]). No fx2 equivalent.
- **What**: replaces `set()` with `sets()` for expensive contexts while the match model is
  confident; mostly a speed lever with small direct gain.
- **Deps**: none (all predicates exist in fx2; apply gates to the fx2-named instances:
  cmC2[6]/cmC2[8]/cmC1[0]→cmC4[0] analog etc.). **Diff**: S. **RT**: yes; measure time.
- **kaitz gain**: +2,244 then +8,786 plus ~69 MB of skipped context work (encode.su 4116 p2).

### Step 10 — Codeword machinery (decoded-dictionary comparisons)

- **Where (v26)**: `dictWLen` fxcm.cpp:345/388; cw\* capture :353-427; `decodeWord`
  simplification :467-471; `cwSTR/cwCOLON` :3458; `procWord` (decode codeword → emit chars
  into `cwbuf`/stemmer) :4148-4161; codeword-driven tag FSMs `isText/isNowiki/isMath/isPre/
  page-end` :4426-4443 (compare `cwSTR==cwTEXT/cwNOWIKI/cwMATH/cwPRE/cwPAGE`); colon-link
  logic via `cwCOLON==cwIMAGE/cwCATEGORY/cwUSER/cwWIKIPEDIA` :4670-4687; `WordsContext`
  grows `codeword` vector + `codesum` + `Code()/CodeR()` accessors :1868-1949.
- **Where (fx2)**: byte-pattern versions of the same FSMs fxcmv1.cpp:3946-3963; `loaddict`
  without lengths :368-381; WordsContext without codewords :2076-2219.
- **What**: "codeword-vs-codeword comparison for dictionary words (not text strings)" —
  cheaper and more reliable tag/section detection; foundation for sentence similarity (step
  17), wt4cxt (16), skipping (11), page resets (22).
- **Deps**: none. **Diff**: M (touches loaddict, parse loop, WordsContext layout; keep
  `isDictLoaded` fallback for the integrated build, §1.4). **RT**: yes — this step should be
  size-neutral-ish by itself; its value is enabling later steps.

### Step 11 — Prediction skipping after See also/References/External links/Category

- **Where**: `skipSeeExternal` detection fxcm.cpp:4809-4823 (heading `== Word(s) ==` whose
  codewords are cwSEE+cwALSO / cwEXTERNAL+cwLINKS / cwREFERENCES / cwBIBLIOGRAPHY); gates at
  :4879 (cmC2[17]), :5078 (cmC[1]), :5093 (cmC4[3] x4 slot), :5101 (cmC2[17] slot 2), :5199
  (cmC4[7]). `isCategory` detection :4679-4682 and :4824-4828; gates :5015 (cmC4[2]),
  :5142/:5158/:5170 (cmC2[12], cmC2[13] gate list), :5188 (cmC2[14]).
- **Deps**: step 10. **Diff**: S. **RT**: yes.
- **Note**: the heavyweight variant (separate streams) was tested and rejected by kaitz —
  do not extend this beyond `sets()` gating (RESEARCH-CANDIDATES §b.3).

### Step 12 — PState/PStateH page-structure state

- **Where**: enum + state fxcm.cpp:3510-3517; transitions :4199-4202 (text-tag end),
  :4643-4649 (line first-char → PTopic/PText/PTemplate), :4679-4683 (PCategory); context
  consumers :5031 (`cmC4[4].set(h+PStateH)`), :5043/:5056 (`cmC[0]` word/list slots get
  `+PStateH`), later mxA[17] (step 23). `isPageStarted/isLongTOP/pageParag/pageSent`
  bookkeeping :3496-3498, 4199, 4211, 4494-4495 (pageParag/pageSent feed step 22's
  `lastPTOP` heuristic, :4457-4458).
- **Deps**: step 10 (isText via cwTEXT). **Diff**: S. **RT**: yes.

### Step 13 — worcxt0/worcxt3 undecoded/tag word streams; Word0(); drop word1..3

- **Where (v26)**: instances fxcm.cpp:3567-3571 (worcxt0 "undecoded", worcxt3 "tag");
  `Word0(i)` multiplier-ladder accessor :2015-2031 (our UB fix at :2029); HT-tag tracking
  `isHTTAG/wasTag` :3491-3492, 4113-4119, 4133-4136; conj/conjadv skip now ungated
  :4372-4374 (**fx2's blpos gate 463139793 at fxcmv1.cpp:3884 is removed**); LF aging block
  :5223-5231 replaces fx2's `word1*83, word2*53, word3*47` aging (fxcmv1.cpp:4484-4488,
  3885-3887); consumers: `rcmA[0].set(worcxt0.Word0(3)+c1+193*(stream3b&0xfff))` :4863
  (fx2: `word3*53+c1+193*(stream3b&0x7fff)` :4248 — note mask change 0x7fff→0xfff),
  `cmC2[4].set(h+worcxt0.Word0(1))` :4877 (fx2 `h+word1` :4260), `cmC2[5].set(h+
  worcxt0.Word0(2)*71)` :4886 (fx2 `h+word2*71` :4267), `cmC4[8]`/`cmC2[19]` slots :4905,
  :4973; `worcxt3` feeds cmC2[12] tag-words slot :5148; removeWords calls :4742-4755.
- **What**: previous-word contexts move from three rolling scalars to a proper word stream
  with surrounding-byte/LF awareness; tag words get their own stream.
- **Deps**: step 10 (lastCW into Update calls). **Diff**: M. **RT**: yes.

### Step 14 — Number-position indirect

- **Where**: `np[0x10000]` fxcm.cpp:3454; `numberA` rolling hash + `np` update :4334-4343
  (also pushes Number-typed words into worcxt/worcxt0); `indirectNumberd0Pos` :4776-4782
  (overrides `indirectWord0Pos` when inside a number). No fx2 equivalent (fx2 number parse:
  fxcmv1.cpp:3857-3871; `h=h+c1` :4243 vs v26 `h=h+numberA+c1` :4806).
- **Deps**: none. **Diff**: S. **RT**: yes.

### Step 15 — StationaryMap ×2

- **Where**: struct fxcm.cpp:1444-1485 (dt-curve U32 counter map, 2 mixer inputs each, both
  exported); `maps1.Init(16,8); maps2.Init(16,8)` :3603-3604; `maps1.set(word0*191)`,
  `maps2.set(deccode>>2)` :5269-5270; mix :5299-5300. No fx2 equivalent.
- **What**: +4 mixer inputs; 63.7 MiB ×2.
- **Deps**: none (deccode exists in fx2). **Diff**: S. **RT**: yes + RT-full (count change).

### Step 16 — Sentence word-type hashes (wt3cxt/wt4cxt) + cmC2[20]

- **Where**: state fxcm.cpp:3521; updates :4364-4370 (`wt3cxt`=hash of getWT3 sequence,
  `wt3cxtW`=codeword+type hash excluding Nouns, `wt4cxtW`=partial-sentence codeword+type),
  flushes :4485, :4524, :4533; consumers `cmC2[20]` ×3 :4908-4910 (gated :4890),
  `cmC4[2].set(wt4cxtW1*191+word0)` :5016 (gated by isCategory), resets :4170, :4449, :4478,
  :4502, :4523. Instance `cmC2[20].Init(8*4096*4096,3,…)` :3725.
- **Deps**: steps 8 (getWT3), 10 (Code()), 13 (worcxt2 semantics unchanged but shared code
  paths). **Diff**: M. **RT**: yes. ΔRAM +256 MiB.

### Step 17 — SentenceContext: 64-sentence memory, 4 groups, similarity by codeword overlap

- **Where**: struct fxcm.cpp:2040-2099 (`SIMILARWORDS 64`; `Update` memcpy's the whole
  WordsContext; `SimilarSentence` scores codeword overlap, keeps best, discards <53% —
  `pres=53` :2065, scaling :2091-2093); instances `sencxt/sencxtL(lists)/sencxtT(tables)/
  sencxtCL(wikilinks)` :3574-3577; routing in `updateSen()` :4163-4173 + sentence-end updates
  :4519 ('.'), :4541 (';'), :4205-4214 (text-tag/table-end); consumers :4912-4973:
  `lastwor/lastwor1/lastwor3` selection by line type :4913-4926, `xword/xword1/simNoun/simVerb`
  :4927-4966, **new maps** `cmC2[18]` ×5 (:4945-4946, 4968-4970; Init 4*4096*4096, 5 ctx
  :3723) and `cmC2[19]` ×1 (:4972-4973; Init 2*4096*4096 :3724).
- **What**: the headline v26 feature — predicts list/table/link lines from previous similar
  sentences via reverse-order word lookup (`WordR/LastR/CodeR`, :1922-1953).
- **Deps**: steps 10 (codewords), 13 (worcxt fields), 16 recommended first (shares flush
  sites). **Diff**: L. **RT**: yes; expect the biggest single size move (~107.9k standalone;
  RESEARCH-CANDIDATES #9 estimates 80-100k full-pipeline).
- **Port note for bisectability**: instantiate cmC2[18]/[19] on the *fx2* ContextMap2 class
  first (6 inputs/slot); they migrate automatically in step 20.

### Step 18 — cmcr sparse-indirect family

- **Where**: tables `indirect2[256]`, `indirect3[256*256]` fxcm.cpp:3507-3508; `stream5b`
  (3-bit stream with >127 mapped to 'a') :3503-3504, :5237; `s5bByte[8]` last-3-bytes per
  5b-class :5250; `s2Word0[8*16]` word0 per (BrFcIdx, 2b-window) :3505, :5258; maps:
  `cmcr[0]` (1-byte and 2-byte indirect ⊕ indirectBrByte; Init 1*4096*4096, 2ctx :3689; sets
  :5241-5247), `cmcr[1..8]` (8× 2048*4096, 3 ctx each over `s5bByte[i]` ⊕ BrFcIdx/word0/
  deccode/stream5b/lastfc; :3690-3691, :5251-5256), `cmcr2[0..3]` (4× 1*4096*4096, 3 ctx over
  `s2Word0` lanes; :3693-3694, :5259-5264 — comment "disable after 77.00-89.53, 93.10-97.46%
  (enwik9)" is a *candidate* future blpos gate kaitz left unimplemented).
- **What**: 13 small reset-friendly CMs, 39 context slots; `nestList` flag :3501, :4588 gates
  cmcr word0 term :5253.
- **Deps**: step 10 (deccode semantics already in fx2). The instances also rely on
  ContextMap3's `reset()` only via step 22 (cmcr are *not* reset per article — only cmC4/cmC
  are; cmcr are candidates). **Diff**: M. **RT**: yes. ΔRAM +288 MiB.

### Step 19 — XML model + cmC44

- **Where**: paq8px-derived XML parser fxcm.cpp:3062-3333 (XMLTag cache 32, content-type
  flags incl. xISBN via `lastCW==cwISBN` :3149); outputs `xlU1/xlU2/xlU4` hashes + `isXML`
  (last tag <64 bytes ago, :3321) + 9-bit state `xmlS` (:3326-3331); instance `xml` :3582;
  called every bit :4842 (`xmlS=xml.p()`); consumer `cmC44` ×4 slots gated on isXML
  :5066-5076 (Init 1*4096*4096, 4 ctx :3687); mixer `mxA[16]` keyed `xmlS&1023` arrives in
  step 23 (:5494, gated input :5512, gated update :5548).
- **Quirk**: `xlU3` is declared (:3152) but never written — `cmC44.set(xlU3)` (:5069) is a
  constant-0 context slot. Port as-is for parity; flag for cleanup later.
- **Deps**: step 10 (cwISBN, lastCW). **Diff**: M. **RT**: yes.

### Step 20 — ContextMap3/ContextMap4 class swap (prediction-count trims, shared StateMap)

- **Where (v26)**: `ContextMap3` fxcm.cpp:980-1212; `ContextMap4` :1214-1403; global `rcpr`
  run-prediction table :953, precalc :5793-5800; `sc()` :893-896. Instance wiring
  :3671-3729.
  **Where (fx2)**: `ContextMap` (E<7,64>, 7-way) fxcmv1.cpp:887-1092; `ContextMap1`
  (E<3,32>) :1093-1325; `ContextMap2` (E1<14,128>) :1326-1540; per-instance `rc1[512]` run
  tables built from packed `c_r` arg (Init :921/:1126/:1359; packed arg format
  `c|(c_r<<8)|(c_s<<16)` at :3276-3315).
- **What** (all-in-one class change; this is the heart of the "ContextMap prediction
  reductions"):
  1. **Shared per-instance StateMap**: ContextMap3 keeps one `ts[256]` per instance
     (:1055-1060) with cross-slot dedup — `set(c,i)` skips updating a state already claimed
     by an earlier slot this bit (:1018-1032, upd() :1033-1037). Replaces fx2's per-slot
     1 KiB StateMaps. ("ContextMap(128) predictions 6/5→5/4 w/ one shared internal StateMap".)
  2. **st8 merged into st32 at table-build time** (:1073-1088, `st32[s]=(st8+st32[s])>>1`),
     removing the separate st8 input fx2 adds per slot (fxcmv1.cpp:1437-1441).
  3. **Marker input removed**: fx2's non-exported `add(32*2)` per slot is gone.
     Net per-slot mixer inputs: fx2 cmC2 6→v26 4 (skip2=1) / 5→3 (skip2=0).
  4. **ContextMap4** (3-way, replaces ContextMap1): drops live StateMap entirely; inputs are
     precalc `st9[s]` (state prior ×18, :1265-1267, only if skip2) + merged `st32[s]` + run
     = 3/2 per slot ("ContextMap(32) 5/4→4/3, StateMap preds removed").
  5. **Global run scaling** `rcpr` (ilog-based, `c<<(2+(~rc&1))`) replaces per-instance
     `c_r[27]`-scaled tables; `c_r` deleted.
  6. **7-way `ContextMap` class deleted** — fx2's cmC[0..5] become ContextMap3 (14-way,
     128-byte buckets): double the assoc and bytes for the same Init arg.
  7. **Parameter retune**: `c_s/c_s3/c_s4` (fxcm.cpp:3432-3434 vs fxcmv1.cpp:3136-3139):
     c_s[1..3] 26,28,31→32,32,32; c_s3[1..3] 33,34,28→32,32,32; c_s4[2..3] 9,5→12,12.
  8. **skip2 flips**: cmC2[1],[2],[3] lose their st2 input (skip2 1→0, fxcm.cpp:3672-3674
     vs fxcmv1.cpp:3277-3279); cmC[1],[2] keep st2_p0 (zeros) as before.
  9. **`reset()` methods** added (:1090-1097, :1286-1293) — consumed by step 22.
  10. **Instance index remap**: fx2 cmC1[0,1,2,4,3,6,7] → v26 cmC4[0,1,2,4,3,6,7] + new
      cmC4[8]; fx2 cmC1[5] dead slot dropped; v26 declares-but-never-inits cmC4[5] and
      cmCR[3..8] (new dead slots — keep arrays sized as written for parity).
- **Deps**: steps 6,7 done (input counts settle); contexts from steps 9-19 already wired so
  this step is *pure class/series substitution* — the slot recipes themselves are otherwise
  unchanged between the two files (verified for cmC2[0..17], cmC[0..5], cmC1→cmC4 series;
  the only recipe edits are the gating/PStateH/worcxt0 edits already landed in steps 9-17).
- **Diff**: L — every CM input count changes; recompute `ncount` (512→…), `num_models`,
  and per-mixer N. Do **not** combine with step 23; keep the 12-mixer fx2 bank for this RT.
- **RT**: yes + RT-full. This is the most likely step to surface count/ordering bugs — the
  cross-slot state dedup makes update order within an instance semantically load-bearing.

### Step 21 — CM memory rebalance

- **Where**: fxcm.cpp:3671-3729 vs fxcmv1.cpp:3276-3315. Diffs (Init-arg, same units both
  sides): cmC2[4] 8→16·4096·4096; cmC2[5] 8→16; cmC2[8] 4→8 (8·4096·4096/2 → 8·4096·4096);
  cmC[0] 16·4096→2·16·4096; cmC4[1] 2·32·4096→8·32·4096; cmC4[2] 32·4096→8·32·4096;
  cmC4[4] 16·4096→32·4096; cmC4[6] 16·4096→2·16·4096. Unchanged: cmC2[0-3,6,7,9-17],
  cmC[1-5], cmC4[0,3,7,8], rcmA.
- **Deps**: step 20 (arg format). **Diff**: S (knob sweep). **RT**: yes; this overlaps
  candidate #8 (predictor-gains doc) — measure each bump separately if budget allows.
- **ΔRAM**: +896 MiB Init-arg ⇒ +~642 MiB actual (CM3 actual = 2×arg for cmC2 entries;
  CM4 actual = arg/2).

### Step 22 — Per-article ContextMap resets

- **Where**: fxcm.cpp:4441-4470. On `</p…>` page tag (detected via `cwSTR==cwPAGE`): reset
  parser stacks (fccxt/brcxt/qocxt/htcxt/colcxt cells) and word streams; **CM resets**:
  `cmC4[1,2,4,6,7,8].reset()`, `cmC[0].reset()`, and `cmC[1].reset()` once every 64 "short"
  pages (`lastPTOP` shift-register of pages with <2 paragraphs and <5 sentences,
  :4456-4458, :4468). StateMaps inside are *not* reset ("StateMap preserved" — reset()
  clears only the BH bucket memory and slot pointers).
- **Deps**: steps 10 (cwPAGE), 20 (reset()). **Diff**: S. **RT**: yes.
- **Gain note**: this is the "knowing when to reset" idea from the DMC entry of the ladder
  applied to CMs; v26 changelog lists it explicitly. The **DMC model itself is NOT in
  fxcm v26** (no DMC struct in the file) — it lives elsewhere in his fx3-cmix; treat as a
  separate future candidate (#6).

### Step 23 — Mixer restructure: 12 → 24 mixers in 3 layers

- **Where (v26)**: banks fxcm.cpp:3527-3529 (`mxA[18]`, `mxA1[6]`, `mxA2[4]`); Init params
  :3612-3642; wiring :3653-3668; per-bit contexts :5371-5494; output plumbing :5496-5520
  (mxInputs2 gets mxA[0..16] — mxA[16] zeroed when !isXML :5512; mxInputs4 gets mxA[17] +
  mxA1[0..4]; final = `mxA1[5].p()`), update loop :5543-5557 (mxA[16] updated only when
  isXML :5548).
  **Where (fx2)**: fxcmv1.cpp:3244-3274 (12 mixers), contexts :4562-4661, output
  :4663-4675 (`squash((mxA[10]·7+mxA[11]+4)>>3)`).
- **What**:
  - fx2's final pair becomes layer-1: mxA[10](M=224)→mxA1[0] (same context formula,
    :5371 vs :4613), mxA[11](M=1)→mxA1[1]; new L1 members mxA1[2..4] (M=2048 each; ctx
    stream2b&0x3f / (stream2b&3)*4+wrt_2b[c0b] / ordX*4+wrt_2b[c0b], :5373-5375); new L2
    final mxA1[5] (M=2048, reads mxInputs4).
  - new L0 mixers: mxA[10] (M=0x10000, ctx c4&0xffff :5488), mxA[11] (M=0x4000,
    stream3b·256+c0 :5489), mxA[12] (oldwt1+stream2bR :5490 — needs `oldwt1=getWT3(
    worcxt2.Type(1))` :4807), mxA[13] (stream3bR&511 :5491), mxA[14]
    (BrFcIdx/FcIdx/wrt_3b[c0b] :5492), mxA[15] ((numbers|words)·16+stream2bR&15 :5493),
    mxA[16] (xmlS, gated), mxA[17] (PState·16+stream2b&15 :5378, fed to mxInputs4).
  - retuned existing mixers: mxA[0] M 2048→0x8000 & ctx widened to stream2bR/stream2b 12-bit
    (:5383-5388 vs :4566-4571), shift1 237→75, uperr 69→14; mxA[1] 204→75/19→14; mxA[2]
    M 6144→1536 with narrowed ctx (:5407 vs :4590), 70→30/34→38; mxA[3] 54→31/23→34;
    mxA[4] 55→53/24→23; mxA[5] M 7168→8192, 55→79; mxA[6] 70→75/34→20 + bpos-dependent ctx
    (:5413-5420 vs :4594); mxA[7..9] params unchanged but mxA[9] ctx is now
    stream3bR/FcIdx/isParagraph/lastWT (:5487) — **the fx2 lstmex context is displaced**
    (integration decision: keep lstmex as an extra ctx term or extra mixer).
  - input vector widens 512→544 (`BlockData<544>`, ncount fixed at :3653).
- **Deps**: steps 8 (getWT3), 12 (PState), 18 (stream5b for step 24's mxA2[2]), 19 (xmlS).
- **Diff**: L. **RT**: yes + RT-full + wall-clock (18×544-dot products ≈ +80% L0 mixer
  FLOPs vs fx2's 10×512).

### Step 24 — fp-mixer bank (mxA2×4) + mmmO final chain

- **Where**: `Mix` struct (int-weight 2-input logistic mixer, 24-bit weights, error-count
  warmup) fxcm.cpp:474-501; `mmmO[4]` :3586/:3597; `mxA2[0..3]` Init :3639-3642 (M = 256,
  256, 0x8000, 0x10000; shift 30, uperr 14) reading the **entire 560-entry prediction
  vector** (:3667-3668); contexts c1, c2, stream5b&0x7fff, stream2b&0xffff (:5598-5601);
  `mstate` (STA2-transition bit-history of the global stream, :4833, :5366) as mmmO context;
  cascade :5602-5614: `pu=mmmO[0](0,mp0) → mmmO[1](pu,mp1) → mmmO[2](pu,mp2) →
  mmmO[3](pu,mp3)`, final `pr=(squash(clp(pu))+pr·3)>>2`.
- **What**: this is the standalone's stand-in for the cmix float-mixer stage — in the
  integrated port these four mixers and the mmmO chain are **replaced by cmix layer-0/fp
  mixers** consuming the exported predictions (§4); only port them into fxcmv1.cpp if we
  choose to keep the model self-contained (then the 6 APM outputs + this chain's output are
  what's exported, "6 predictions generated").
- **Deps**: step 23 (the 560-vector composition must be final), step 18 (stream5b).
- **Diff**: M. **RT**: yes. Plausible attribution: the ladder's "Shelwien sh_v2f (+16,943)
  and mod_sse (+197,441)" entries are this Mix/mmmO + APM-stage rework — attribution
  uncertain, verify by measurement.

### Step 25 — DirectStateMap ×5 ("InDirectStateMap, 22 contexts, order-w mixing") — LAST

- **Where (v26)**: struct fxcm.cpp:3354-3401 — per set(): direct-indexed byte state table
  (`CxtState[(cx)&mask]`), per-context StateMap over the state, and a **chained 2-input Mix
  per context** (`pu = mmm[i-1].pp(pu, stretch(sm.pr), state)`, :3391-3392) so each instance
  emits ONE combined order-w prediction (`mix()` adds `pu>>2`, :5360-5364) plus per-set
  non-exported `pre1[state]` inputs; `pre1` is now a const table :3335-3352 (fx2 computed it
  via `pre2()`, fxcmv1.cpp:1600-1606). Instances :3546-3550, Init :3605-3610: dcsm(28-bit,
  5 ctx: word0×worcxt.Word(1..4)+c0, sets :5274-5278), dcsm0(28-bit, 6 ctx: h+worcxt1.
  Word(1..6), :5288-5293), dcsm1(20-bit, 2 ctx: indirectBrByte, cxtind3 — the cmix-style
  double-indirect, :5285-5286), dcsm2(26-bit, 3 ctx: word00+indirectBrByte+worcxt0,
  :5280-5282), dcsmN(25-bit, 3 ctx: h+worcxt.Code(1..3)+fccxt, :5295-5297). 19 contexts
  total (README's "22" counts loosely).
  **Where (fx2)**: dormant simpler version fxcmv1.cpp:1565-1599 and the tell-tale comment
  `//DirectStateMap dcsm; //1x5 inputs to fp` :3222-3223 — **this is the component kaitz
  removed from fx2 because decompression mismatched**.
- **Deps**: steps 10 (Code()), 13 (worcxt0), and the v26 STA7 table (already present).
- **Diff**: M code-wise; **highest determinism risk in the whole port** — land it last,
  behind a compile-time flag (`#ifdef FXCM_DCSM`), with the divergence harness armed.
- **RT**: yes + RT-full + cross-machine RT (compress on A, decompress on B) + compile-flag
  matrix (-O2/-O3, gcc/clang). ΔRAM +609 MiB (CxtState tables 256+256+1+64+32 MiB).

### Not ported / intentionally absent

- **fx2's blpos 463139793 conj gate** (fxcmv1.cpp:3884) — removed in v26 (step 13).
- **fx2's per-slot StateMaps, st8 input, c_r run multipliers, st2_p2** — superseded (steps 3, 20).
- **DMC with smart reset** (+113,256 ladder) — not in this file; separate candidate.
- **Article order file** — input asset, not code (candidate #4).
- Dead v26 code to carry as-is for diffability: `Mixer1::reset()` (fxcm.cpp:637-639, never
  called), `stream6b` (:3506), `wt3cxtW1` (written :4364, never read), `wasVerbH/wasNounH`
  (:3502, written only — kaitz's own comment "looks like this is not used?" :4800),
  `isLongTOP` (:3497), `xlU3` (step 19), `Word.NextW` (step 8), cmC4[5]/cmCR[3..8] dead slots.

---

## 3. Risk notes

### 3.1 Determinism / FP / order-of-evaluation

1. **The fx2-removed component is back** (step 25). fxcmv1.cpp:3222-3223 marks DirectStateMap
   as the thing fx2 had to delete; kaitz's fx3 divergence ("identical up to some point",
   asserts silent) reappeared with the v26-generation integration. The standalone arithmetic
   is **all integer** (Mix weights are ints; mmmO/mxA2 integer) — the divergence is therefore
   most plausibly in the *cmix-side float mixers consuming new fxcm outputs* (or in
   compress-vs-decompress state skew), not in the standalone math. Strategy: port everything
   up through step 24 with RT at each step; introduce step 25 and the §4 cmix-side changes
   one at a time with the stream-divergence harness (find first divergent bit, dump
   prediction vectors both sides).
2. **Float only at init**: `squashc/stretchc` use `exp/log/round` (fxcm.cpp:112-157) to build
   tables once. Same-binary-same-machine is safe; *different libm versions produce different
   tables* → archives are not portable across builds. Pin the toolchain; consider emitting
   the tables as constants before the final submission build.
3. **`Inputs::add` assert comment** — "fixme, when enabled compression is different"
   (fxcm.cpp:171): inputs outside ±2047 do occur and are clamped by `clp`; an NDEBUG-off
   build aborts. Keep NDEBUG; never gate behavior on assert side effects.
4. **Cross-slot state dedup makes mix order semantic** (ContextMap3::set/upd,
   fxcm.cpp:1018-1037): reordering `cm.mix()` calls or slot order changes predictions.
   Preserve the exact mix() sequence of fxcm.cpp:5299-5364.
5. **mmmO/dcsm comma-sequenced update-then-predict** (`mmm.update(x.y), pp(...)`,
   fxcm.cpp:3392, 5609-5612) — comma operator sequencing is defined; keep as-is, don't
   "clean up" into separate statements with reordered globals.
6. **Stale-tail dot products**: dot products always run over fixed N (544/32/16/560); entries
   beyond the current bit's adds hold previous-bit values. All gated components therefore
   `add(0)` instead of skipping (e.g. isXML :5512). Any port slip that *skips* an add
   desynchronizes compress/decompress only if the skip predicate uses future info — keep the
   add-zero discipline.
7. **Already-fixed UB sites (ours, marked)**: fxcm.cpp:2029 (`Word0` signed-overflow → U32),
   :5165 and :5235 (`c4<<16`/`c4<<8` signed-shift → U32 cast). Values match Windows two's-
   complement behavior, so parity with kaitz's builds is preserved. Audit for remaining
   signed shifts when merging into fxcmv1.cpp (fx2 has its own copies of some).
8. **`cxtMask=((1<C)-1)*2` quirk** (fxcm.cpp:1048 etc., same in fx2 :925) — `1<C` is a
   comparison, almost certainly meant `1<<C`. Identical bug both sides; do NOT fix (changes
   the initial skip mask ⇒ changes output).
9. **`percent` divide in Encoder::compress** (fxcm.cpp:5698) is I/O-only; irrelevant for the
   integrated port.

### 3.2 Memory budget (RAM ceiling < 10 GB strict; fx3 targets PPM 1750 MB in RAM)

fxcm v26 standalone footprint (computed from Init args; CM3 actual = 2×arg, CM4 = arg/2):

| Block | MiB |
|---|---|
| cmC2[0..20] (incl. new 18/19/20: 128+64+256) | 4,756 |
| cmC44 + cmcr[0..8] + cmcr2[0..3] | 320 |
| cmC[0..5] + cmC4[*] + cmCR[0..2] | ~13 |
| Mixers mxA (18, N=544) | ~474 |
| Mixers mxA2 (4 × M×560) | ~105 |
| DirectStateMaps (2^28×2 + 2^26 + 2^25 + 2^20) | 609 |
| StationaryMaps ×2 | 127 |
| Match hash (×2) + rcm + buffer + ind3 | 160 |
| APMs + smA + scm + sentence buffers + misc | ~50 |
| **fxcm v26 total** | **≈ 6,610 ≈ 6.5 GiB** (fx2: ≈4.1 GiB → **+2.4 GiB**) |

Whole program: 6.5 GiB fxcm + 1.71 GiB PPM-in-RAM + ~0.6 GiB cmix indirect hashes +
0.1 shared_map + ~0.93 history + cmix match/LSTM small ≈ **9.9–10.1 GB** — exactly kaitz's
reported 10,058,856 kB, i.e. **over** a 10^9-byte GB reading. Pre-identified trims, in order
of cheapness: dcsm/dcsm0 28→27 bits (−256 MiB, retune), mxA2[3] M 0x10000→0x8000 (−35 MiB),
cmcr2 family (−128 MiB; kaitz's own "disable after 77%" comment suggests it's marginal late),
one of the cmC2[4]/[5] doublings (−256 MiB each, costs measured gain). Budget target 9.7 GB
per RESEARCH-CANDIDATES open question 4. PPM change itself: predictor.cpp:56 (14000→1750) +
`mmap_to_disk=false` (ppmd.cpp:33) — verify order-25 retention at the smaller arena on proxy.

### 3.3 blpos magic constants (gate behavior at fixed offsets)

| Constant | v26 site | fx2 site | Meaning |
|---|---|---|---|
| 448131719 | fxcm.cpp:4301, 4320 | fxcmv1.cpp:3837, 3848 | freeze `deccode` updates (main text ends) |
| 451531986 | fxcm.cpp:3041 | fxcmv1.cpp:3119 | disable VerbWords1 matching ("77.06%") |
| 463139793 | — (removed) | fxcmv1.cpp:3884 | conj word-order skip cutoff — **gone in v26** |
| 6 | fxcm.cpp:4289 (`x.blpos>6`) | fxcmv1.cpp:3830 | partial-decode warmup |
| 14·256·1024 / 28·512·1024 | fxcm.cpp:5538-5540 | fxcmv1.cpp:4693-4695 | sscmrate / APM rate schedule |
| `lastPTOP&63==63` | fxcm.cpp:4468 | — | cmC[1] reset cadence (page-count, not blpos) |

All byte-position constants assume the 586,459,020-byte dictionary-coded stream **and the
article order they were tuned on**. Adopting the v26 article order (candidate #4) is the
order these were tuned against; re-tune (or at least re-validate) if we re-derive ordering
(candidate #10). The "disable after 77.00-89.53%" comment at fxcm.cpp:5259 is an additional
unimplemented gate kaitz identified — a free candidate experiment.

### 3.4 Misc port hazards

- `SentenceContext::Update` does `memcpy(&sentence[i], w, sizeof(WordsContext))`
  (fxcm.cpp:2057) — WordsContext must stay trivially copyable; don't add std:: containers.
- `PredictorFree` (fxcm.cpp:3750-3760) frees fewer objects than allocated (mxA[0..10],
  cmC4[0..7]…) — harmless leak in a run-once binary, but the integrated model never frees;
  ignore.
- Standalone `assert(deccode>=0 && deccode<0x20000)` (fxcm.cpp:4295 etc.) bounds mxA[8]'s
  M=0x20000 — preserved from fx2.
- v26 update loop covers `mxA[i<16]` then conditionally mxA[16], then mxA[17]
  (fxcm.cpp:5547-5549) — easy to misport into "i<18".

---

## 4. Predictor.cpp / cmix-side changes

1. **Export width & domain** (predictor.cpp:182-187, fxcmv1.cpp:93-106): `num_models`
   431 → ~560 (or ~487 if we replicate kaitz's trimmed export). Keep float-probability
   export (`AddPrediction(squash(p))` / `x*conversion_factor`); the standalone's stretched-
   short domain is an internal detail of its mxA2 bank. Every catalog step that changes
   counts (6,7,15-21,23,25) must bump the valarray size and cmix layer-0 width together —
   `GetNumModels()` picks it up automatically via `fxcm_model_.NumOutputs()`
   (predictor.cpp:23), but pretraining/back-compat snapshots do not.
2. **PPM to RAM**: `byte_model_.emplace(25, 14000, …)` → `(25, 1750, …)` (predictor.cpp:56)
   and `mmap_to_disk=false` (src/models/ppmd.cpp:33). Frees the disk-thrash failure mode and
   ~5-10 h wall; do early (it's independent of the fxcm port and creates the RAM headroom
   steps 15-25 spend).
3. **Mixer set 23→16** (fx3 README "16 mixers"): predictor.cpp:143-165 currently adds 23
   layer-0 mixers + 1 layer-1. kaitz cut to 16 — which 7 were dropped is not recoverable from
   the README; treat as a measured-pruning task after the model port (his timeline notes
   mixer-removal was only "so-so", so expect ~neutral size, positive speed).
4. **"6 predictions to cmix fp mixers"**: the six update-level APM-chain outputs
   (`pu, pv, pv', pt, pz, pr_final`, fxcm.cpp:5580-5596 / fxcmv1.cpp:4738-4754) are already
   exported in fx2; in fx3 these (plus the fxcm final bias) are the inputs kaitz fed to the
   cmix float mixers replacing the standalone's mxA2 bank. Concretely for our port of step
   24: add cmix-side mixers keyed on fxcm-exported contexts `c1, c2, stream5b&0x7fff,
   stream2b&0xffff` (new externs alongside `wrtcxt`, fxcmv1.cpp:45) via
   `manager_.AddMixer`-style contexts, or port mxA2/mmmO inside fxcmv1.cpp and export only
   the chain output — **the former matches kaitz's architecture (and his bug); the latter is
   integer-deterministic. Recommend the latter first, switch only if it underperforms.**
5. **WUS ~10% on cmix mixers** (fx3 README): cmix-side skip of mixer weight updates —
   independent knob in src/mixer/ (fx2 already has WUS infrastructure; retune to ~10% skip
   rate). Pair with step 4's fxcm-side elim change.
6. **Keep**: `wrtcxt`→`mx19cxt` export (re-add in parseByte, see §1.3); LSTM feedback inputs
   into fxcm (fxcmv1.cpp:4663/4674) and `lstmex` context; auxiliary average context
   (predictor.cpp:229-231) — fxcm_model_index arithmetic at predictor.cpp:187 assumes the
   fxcm block ends with its final prediction; v26's last AddPrediction is `pr_final` — the
   auxiliary hookup survives unchanged.
7. **Dictionary**: no cmix-side change needed; `.dict` extraction already happens
   (runner.cpp:356-452). Add `dictWLen` + cw\* capture inside fxcmv1's loaddict (step 10) and
   keep the `isDictLoaded` guard so the model survives the pre-dictionary phases of the
   self-extracting pipeline.
8. **New shared contexts (optional)**: `PStateH`, `mstate`, `isXML` are cheap, decoded-stream
   -synchronous values that could feed cmix mixer contexts the way `wrtcxt` does — candidate
   experiments after parity, not part of the baseline port.

---

## Appendix A — component census (v26 vs fx2)

| Component | fx2 | v26 | Note |
|---|---|---|---|
| ContextMap classes | 3 (7-way/3-way/14-way) | 2 (14-way CM3, 3-way CM4) | step 20 |
| CM instances (live) | 27 (cmC×6, cmC1×7, cmC2×18, −2 dead) | 48 (cmC×6, cmC44, cmcr×9, cmcr2×4, cmC2×21, cmC4×8, cmCR×3) | +21 |
| CM context slots | 81 | ~118 | |
| SmallStationaryCM | 7 | 3 | step 7 |
| StationaryMap | 0 | 2 | step 15 |
| RunContextMap | 1 | 1 | mask/recipe edit (step 13) |
| MatchModel2 | 1 (32 MiB) | 1 (64 MiB) | step 1 |
| SparseMatchModel | 1 | 0 | step 6 |
| DirectStateMap | 0 (commented) | 5 (19 ctx) | step 25 |
| XML model | 0 | 1 | step 19 |
| SentenceContext | 0 | 4×64 sentences | step 17 |
| WordsContext | 3 | 5 (+codewords) | steps 10/13 |
| Mixer1 | 12 (10+2) | 28 (18+6+4) | steps 23/24 |
| Mix (2-input) | 0 | 4 mmmO + 14 in dcsm | steps 24/25 |
| APM | 6 (4.1-16.5 MiB ea.) | 6 (A4/A5 halved) | step 5 |
| LSTM input | yes (cmix) | no | keep ours |
| predictions | 431 exported floats | 560 internal shorts | §1.2 |
| state tables | STA1/2/4/5/6/7 identical (Init args verified: fxcm.cpp:5806-5811 vs fxcmv1.cpp:4787-4792) | same | no change |
