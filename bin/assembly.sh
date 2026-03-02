#!/usr/bin/env bash
# =============================================================================
# BORA assembly.sh — De novo assembly + quality assessment
# Uses Shovill (SPAdes backend) for assembly, QUAST for QC metrics.
# =============================================================================
set -euo pipefail

SAMPLEIDS="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"
load_config

log "=== ASSEMBLY STEP STARTED ==="
require_tool shovill
require_tool quast.py

# Collect assembly paths for combined QUAST report
ASSEMBLIES=()

while IFS= read -r sample; do
  fdir="results/filtered/${sample}"
  adir="results/assembly/${sample}"
  mkdir -p "$adir"

  # Resolve trimmed reads — fall back to raw if filtering was skipped
  if [ -f "${fdir}/${sample}_trim_R1.fq" ]; then
    TRIM_R1="${fdir}/${sample}_trim_R1.fq"
    TRIM_R2="${fdir}/${sample}_trim_R2.fq"
  else
    warn "Trimmed reads not found for $sample — using raw reads"
    resolve_fastq "$sample"
    TRIM_R1="$R1"
    TRIM_R2="$R2"
  fi

  log "Assembling: $sample"
  shovill \
    --R1 "$TRIM_R1" \
    --R2 "$TRIM_R2" \
    --outdir "$adir" \
    --cpus "${THREADS:-4}" \
    --ram "${MEMORY_GB:-16}" \
    --minlen 500 \
    --force \
    2>> "results/logs/${sample}.assembly.log"

  # Confirm output exists
  asm=$(find_assembly "$sample")
  log "Assembly complete: $sample → $asm"
  ASSEMBLIES+=("$asm")

done < <(read_samples "$SAMPLEIDS")

# --- QUAST: combined assembly QC report --------------------------------------
log "QUAST: assessing assembly quality for all samples..."
quast.py \
  --output-dir results/assembly/quast_summary \
  --threads "${THREADS:-4}" \
  --min-contig 500 \
  --no-icarus \
  "${ASSEMBLIES[@]}" \
  2>> results/logs/quast.log

log "=== ASSEMBLY STEP COMPLETE — see results/assembly/quast_summary/report.tsv ==="
