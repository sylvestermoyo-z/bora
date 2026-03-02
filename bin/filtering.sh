#!/usr/bin/env bash
# =============================================================================
# BORA filtering.sh — Adapter trimming and quality filtering
# Uses Trim Galore! (wrapper around Cutadapt + FastQC).
# =============================================================================
set -euo pipefail

SAMPLEIDS="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"
load_config

log "=== FILTERING STEP STARTED ==="
require_tool trim_galore

while IFS= read -r sample; do
  resolve_fastq "$sample"
  outdir="results/filtered/${sample}"
  mkdir -p "$outdir"

  log "Trimming: $sample"
  trim_galore \
    --paired \
    --cores "${THREADS:-4}" \
    --quality 20 \
    --length 50 \
    --dont_gzip \
    --output_dir "$outdir" \
    "$R1" "$R2" \
    2>> "results/logs/${sample}.trim.log"

  # Standardise trimmed output filenames for downstream steps
  # Trim Galore names outputs as SAMPLE_R1_val_1.fq and SAMPLE_R2_val_2.fq
  # We create symlinks with predictable names
  r1_base=$(basename "$R1" .fastq.gz)
  r2_base=$(basename "$R2" .fastq.gz)

  ln -sf "${r1_base}_val_1.fq" "${outdir}/${sample}_trim_R1.fq" 2>/dev/null || true
  ln -sf "${r2_base}_val_2.fq" "${outdir}/${sample}_trim_R2.fq" 2>/dev/null || true

  log "Trimming complete: $sample → $outdir"
done < <(read_samples "$SAMPLEIDS")

log "=== FILTERING STEP COMPLETE ==="
