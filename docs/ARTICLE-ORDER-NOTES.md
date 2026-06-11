# ARTICLE-ORDER-NOTES — kaitz's 2025 article order vs our v7 file (2026-06-10)

Question: did Kaido Orav (kaitz) ship an updated enwik9 article-order file we can adopt for
free compression gains? Short answer: **not in his fx3-cmix repo (that file is byte-identical
to ours), but yes — a genuinely new order file ships inside the fxcm v26 release archive
(encode.su attachment, Apr 2025), recoverable via the Wayback Machine.** It is a drop-in
permutation of the same 172,277 article IDs, worth ~148 KB on standalone fxcm in his ladder.

---

## (a) kaitz-fx3 branch order file vs ours: IDENTICAL

```
git show kaitz-fx3:src/readalike_prepr/data/new_article_order   md5 68fa9a4f80fd438cf55768e3c1749c6d
src/readalike_prepr/data/new_article_order (ours, main)         md5 68fa9a4f80fd438cf55768e3c1749c6d
kaitz/fx2-cmix@main same path (fetched from GitHub raw)         md5 68fa9a4f80fd438cf55768e3c1749c6d
```

All three are the same 1,094,862-byte / 172,277-line file: Byron Knoll's **"article order v7"**
(commit `7c015b1`, 2024-07-12), the last commit ever to touch this path in the fx2/fx3 lineage.
Diff stats vs ours: 0 lines differ, identical prefix = entire file. There is nothing to take
from the `kaitz-fx3` branch here.

**Resolving the README contradiction.** kaitz's fx3 README says *"Article order: Moved all
articles with title 'Wikipedia:' after images"* — but no commit of his (b6184c8, 87325d8,
bdad49a, 213ebd6, e679749, 04c5806) touches `readalike_prepr/` or the order file, and no code
in fx3 implements such a move. The README documents an order change whose **data file he never
committed to fx3-cmix**. He published it ~11 months later inside the fxcm v26 archive (below);
the extracted file is dated 2025-04-06.

## (b) The new order artifact: fxcm v26 archive (encode.su attachment, Wayback-archived)

- Not in the `kaitz/fxcm` repo tree (only README.md, fxcm.cpp, english.dic, doc/, tools/,
  "for cmix/") and **not** in the GitHub release assets (v26 release ships only
  `fxcm_v25.exe` + `fxcm_v26.exe`).
- It ships in **`fxcm_v26.7z` (580 KB), attached to encode.su thread 4116 post #45
  (12 Sep 2025)**: *"Additionally, the archive includes a new article order, which was better
  in my tests."*
- encode.su is Cloudflare-blocked, but the attachment is archived. Working download:
  - `https://web.archive.org/web/20250912120058if_/https://encode.su/attachment.php?attachmentid=12634&d=1757675708`
  - (original: `https://encode.su/attachment.php?attachmentid=12634&d=1757675708`)
- Archive contents: `fxcm_v25.exe`, `fxcm_v26.exe`, `fxcm.cpp`, `english.dic`, `README.md`,
  **`new_article_order`** (1,267,139 bytes, CRLF line endings, file date 2025-04-06).
- Checksums (for reproducibility):
  - `fxcm_v26.7z` md5 `ce238f358707045b3768f37f46583313`
  - `new_article_order` as-shipped (CRLF) md5 `656dabffc2f6ccf0e49cc62c21ffd765`
  - after `tr -d '\r'` (LF, 1,094,862 bytes — same byte count as ours, since it is a permutation
    of the same lines): md5 `b5c1e1163aaede3a72d322508e9b5697`,
    sha256 `eecd462c29319bab185b48229c4d09ab52f16ca9c582e8e32eff9a7c2a7de39e`
- Local extracted copy (volatile): `/tmp/fxcm_v26/fxcm_v26/new_article_order`.

### Quantified diff: v26 order vs our v7 order (after CRLF normalization)

| Metric | Value |
|---|---|
| Lines | 172,277 in both; exact permutation (same value multiset, 0 added/removed) |
| Identical prefix | first **3,183** lines unchanged |
| Same-position lines | 3,183 (only the prefix) — naive "lines moved" = 169,094 (98.2%) |
| Preserved adjacencies | **171,784 of 172,276 (99.7%)** — the naive number is misleading |
| Structure | old order cut into **493 contiguous runs** and re-stitched |
| Minimum articles relocated (LIS) | **907 (0.53%)** |
| Where they went | mostly to the tail: 226 of 310 small runs land at new positions ≥170,000, i.e. **after the image block**; ~63 into the 30–40 k region |

This matches his README claim precisely: enwik9's `Wikipedia:`-namespace pages (≈900 articles)
pulled out of their semantic-cluster positions and appended after the `Image:` block (our
`src/article_order/manual-sort.ipynb` already moves `Image:`/disambig/geo/census pages to the
end — this extends that idea to the `Wikipedia:` namespace). Everything else keeps its
relative order, so the change is low-risk and easy to reason about.

## (c) Claimed/measured gain

From encode.su thread 4116 p2 post #44 (3 Jun 2025) — kaitz's standalone-fxcm progress ladder
(cross-checked against `docs/RESEARCH-CANDIDATES.md`, which already records this row):

```
586459020 -> 113792605   ("10 lines of source code" step, before order change)
586459321 -> 113644838   // new order        Δ = −147,767 bytes
```

- **−147,767 bytes (~148 KB) on standalone fxcm** attributed to the "// new order" row.
  Caveats: ladder rows may bundle small unrelated changes, and the preprocessed input size
  changed by +301 bytes at the same row (586,459,020 → 586,459,321).
- Transfer to the full compressor: order gains come from the input stream itself, not from a
  model, so they should transfer near 1:1 (unlike model gains, which he says transfer ~50–60%).
  Precedent: Byron measured the 2024 v7 reorder at **+212,578 bytes in full cmix**
  (per RESEARCH-CANDIDATES.md candidate #4 note).
- Post #45 (v25/v26 release): "a new article order, which was better in my tests" — no separate
  number given there.
- `docs/RESEARCH-CANDIDATES.md` candidate #4 estimates **100,000–200,000 bytes** net for us;
  nothing found here contradicts that, and the ladder row supports the low end as a floor for
  the fxcm model alone.

## (e) Order-file format (how lines map to articles)

Consumed by `src/readalike_prepr/article_reorder.h` (`reorder()`), invoked during preprocessing;
the file is also cmix-compressed and embedded in the self-extracting archive
(`self_extract.h`: `.new_article_order.comp`), so it costs S1 bytes too.

- enwik9 contains `NUM_OF_ARTICLES = 243,425` `<page>` blocks. Pages whose `<text>` starts with
  a `#REDIRECT`/`{{softredirect` variant are redirects.
- The order file is one ASCII decimal per line (LF), 172,277 lines. Each value is a **0-based
  ordinal of a non-redirect article in original enwik9 page order** (values span 0..172,314;
  38 ordinals in that range are absent from the file).
- `reorder()` scans `.main` to build `remap[non-redirect ordinal] -> raw page index`, then emits
  pages in the listed order to `.main_reordered`. Any unused raw page index (all ~71k redirects
  + the 38 missing ordinals) is appended afterward in original order.
- Decompression does **not** need the listed order to restore the file: `sort()` re-sorts pages
  by their `<id>` field. First line `159650` = first article placed in the reordered stream.
- Practical note: the v26 file as-shipped is **CRLF**; our pipeline's file is LF. (`stoi` would
  tolerate a trailing `\r`, but the embedded compressed copy and any byte-level tooling won't —
  normalize with `tr -d '\r'` first. Normalized, it is exactly 1,094,862 bytes like ours.)

## (d) Recommendation: adopt the file as-is (zero runtime cost), regenerate later

**Adopt now.** It is a validated-compatible drop-in: same 172,277-value permutation domain, no
code changes, zero runtime/RAM cost, GPL-3 lineage we already build on. The author measured it
as strictly better; the change is small and interpretable (~907 pages moved after images).

Concrete next steps:

1. Fetch `fxcm_v26.7z` from the Wayback URL above; verify md5s; extract `new_article_order`;
   `tr -d '\r'` → LF; verify sha256 `eecd462c…de39e` and that it is a permutation of our file
   (`sort | cmp` against sorted current file).
2. Commit to an experiment branch (e.g. `exp/0xx-article-order-v26`) replacing
   `src/readalike_prepr/data/new_article_order`; note provenance (encode.su 4116 #45 attachment
   12634, file date 2025-04-06) in the commit message.
3. Run the standard full-enwik9 measured experiment (the reorder path only executes on real
   enwik9 — `NUM_OF_ARTICLES` is hardcoded — so proxies cannot evaluate this). Verify
   round-trip, then score **S = S1 + S2**: the order file is embedded cmix-compressed in the
   archive, and a different permutation compresses differently (cf. fx2 commit `c4766d1`
   "reduce compressor size by improving compression of article reorder file"), so S1 delta must
   be counted, not just S2 gain.
4. Accept per our ledger protocol if net S improves (expected +100–200 KB; reject threshold as
   usual against the noise floor).
5. Independently of adoption, keep RESEARCH-CANDIDATES.md #10 alive: regenerate the order with
   modern embeddings + TSP solver (starlit-style) over the v26 file as the new baseline, and
   fix the ~10k missed REDIRECTs kaitz mentioned — estimated further +50–150 KB, medium effort,
   fully offline (zero runtime cost). The v26 file is a manual tweak of the 2024 t-SNE order,
   not a re-embedding, so the headroom from modern embeddings remains untouched.

---

## Summary

1. kaitz's fx3-cmix repo ships **no** new order file — its `new_article_order` is md5-identical to ours (Byron's 2024 "v7").
2. His real updated order (file dated 2025-04-06) ships inside the **fxcm v26 encode.su attachment**, recoverable via Wayback (attachment 12634); it is absent from both the fxcm repo tree and the GitHub release assets.
3. It is an exact permutation of our file: first 3,183 lines identical, 99.7% of adjacencies preserved, minimum 907 articles (0.53%) relocated — mostly `Wikipedia:`-namespace pages moved after the image block, matching his fx3 README claim.
4. Measured gain at the "// new order" ladder row: **−147,767 bytes standalone fxcm**; order gains act on the input stream so should transfer near 1:1 (Byron's 2024 reorder gave +212,578 in full cmix); our ledger's +100–200 KB estimate stands.
5. Recommended: adopt as-is on an experiment branch (CRLF→LF normalize, verify checksums/permutation, full-enwik9 measured run counting both S2 gain and S1 archive delta), then pursue modern-embedding + TSP regeneration as the follow-up.
