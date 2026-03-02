#!/usr/bin/env bash
# =============================================================================
# BORA qc.sh — Read quality control
# Runs FastQC on all samples, then MultiQC for a combined summary.
# =============================================================================
set -euo pipefail

SAMPLEIDS="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"
load_config

log "=== QC STEP STARTED ==="
require_tool fastqc
require_tool multiqc
mkdir -p results/qc

while IFS= read -r sample; do
  resolve_fastq "$sample"
  log "FastQC: $sample"
  fastqc \
    --threads "${THREADS:-4}" \
    --outdir results/qc \
    --quiet \
    "$R1" "$R2" \
    2>> "results/logs/${sample}.qc.log"
done < <(read_samples "$SAMPLEIDS")

log "MultiQC: aggregating reports..."
multiqc \
  --outdir results/qc \
  --filename multiqc_report \
  --quiet \
  results/qc \
  2>> results/logs/multiqc.log

log "=== QC STEP COMPLETE — see results/qc/multiqc_report.html ==="
