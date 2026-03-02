#!/usr/bin/env bash
# =============================================================================
# BORA typing_core.sh — MLST sequence typing
# Uses mlst (Torsten Seemann) against local PubMLST schemes.
# =============================================================================
set -euo pipefail

SAMPLEIDS="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"
load_config

log "=== MLST TYPING STEP STARTED ==="
require_tool mlst

OUTFILE="results/typing/mlst_results.tsv"
mkdir -p results/typing

# Write header
echo -e "sample\tscheme\tST\tallele_1\tallele_2\tallele_3\tallele_4\tallele_5\tallele_6\tallele_7" > "$OUTFILE"

while IFS= read -r sample; do
  asm=$(find_assembly "$sample")
  log "MLST: $sample ($asm)"

  # mlst outputs tab-separated: FILE SCHEME ST ALLELE...
  result=$(mlst "$asm" 2>> "results/logs/${sample}.mlst.log" || true)

  if [ -z "$result" ]; then
    warn "No MLST result for $sample"
    echo -e "${sample}\t-\t-\t-\t-\t-\t-\t-\t-\t-" >> "$OUTFILE"
  else
    # Replace the file path with the sample ID in column 1
    echo "$result" | awk -v s="$sample" 'BEGIN{OFS="\t"} {$1=s; print}' >> "$OUTFILE"
  fi

done < <(read_samples "$SAMPLEIDS")

log "=== MLST TYPING COMPLETE — see $OUTFILE ==="
