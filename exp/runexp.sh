#!/bin/bash
# Run one experiment on the lab VM. Appends a row to /mnt/work/exp/ledger.tsv.
#
#   runexp.sh <exp-id> <git-ref> <dataset> [core] [extra-make-defines]
#
# Builds <git-ref> in a worktree with mmap_to_disk=false (RAM-only PPM: faster,
# output-identical — verified 2026-06-10), compresses <dataset> with the word
# dictionary loaded (same as the -e pipeline), records bytes/time/RSS.
# Plain non-PGO build: PGO only affects speed; byte-output equivalence between
# PGO and non-PGO builds is checked separately (see docs/EXPERIMENTS.md).
set -euo pipefail

ID="${1:?exp id}"; REF="${2:?git ref}"; DATA="${3:?dataset path}"
CORE="${4:-1}"
DEFS="${5:--DSEED=923 -DUPDATE_LIMIT=3000}"

ROOT="$HOME/fx3-cmix"
WT="/mnt/work/trees/$ID"
LEDGER="/mnt/work/exp/ledger.tsv"
mkdir -p /mnt/work/exp /mnt/work/trees

cd "$ROOT"
git fetch -q origin
[ -d "$WT" ] && git worktree remove --force "$WT" 2>/dev/null || true
git worktree add --force "$WT" "$REF" >/dev/null
cd "$WT"
SHA=$(git rev-parse --short HEAD)

sed -i 's/^bool mmap_to_disk = true;/bool mmap_to_disk = false;/' src/models/ppmd.cpp
make CFLAGS_DEFINES="$DEFS" cmix -j2 >/dev/null 2>build.log || { echo "BUILD FAIL $ID"; tail build.log; exit 1; }

/usr/bin/time -v taskset -c "$CORE" \
  ./cmix -c "$ROOT/dictionary/english.dic" "$DATA" "$WT/out.bin" \
  > "$WT/run.log" 2> "$WT/time.log" \
  || { echo "RUN FAIL $ID"; tail -5 "$WT/time.log"; exit 1; }

IN=$(wc -c < "$DATA")
OUT=$(wc -c < "$WT/out.bin")
WALL=$(grep "Elapsed (wall" "$WT/time.log" | awk '{print $NF}')
RSS=$(grep "Maximum resident" "$WT/time.log" | awk '{print $NF}')

[ -f "$LEDGER" ] || echo -e "id\tref\tsha\tdataset\tin_bytes\tout_bytes\twall\tmax_rss_kb\tdate\tdefines" > "$LEDGER"
echo -e "$ID\t$REF\t$SHA\t$(basename "$DATA")\t$IN\t$OUT\t$WALL\t$RSS\t$(date -u +%F)\t$DEFS" >> "$LEDGER"
tail -1 "$LEDGER"
