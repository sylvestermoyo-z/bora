#!/usr/bin/env bash
# =============================================================================
# BORA species_modules.sh — Species-specific typing
# Runs Kleborate, ECTyper, or SISTR based on species hints.
# Species identity is read from results/species/species_hints.tsv
# Module toggles are read from config/species_modules.cfg
# =============================================================================
set -euo pipefail

SAMPLEIDS="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"
load_config
load_species_cfg

if [ "${ENABLE_SPECIES_MODULES:-true}" != "true" ]; then
  log "Species modules disabled in config — skipping"
  exit 0
fi

log "=== SPECIES MODULES STEP STARTED ==="
mkdir -p results/species

while IFS= read -r sample; do
  asm=$(find_assembly "$sample")

  # Read species hint
  hint_file="results/species/species_hints.tsv"
  species_hint=""
  if [ -f "$hint_file" ]; then
    species_hint=$(awk -v s="$sample" -F'\t' '$1==s{print $2}' "$hint_file")
  fi

  hint_lower="${species_hint,,}"
  log "Species module: $sample (hint: ${species_hint:-unknown})"

  # --- Klebsiella → Kleborate ------------------------------------------------
  if [[ "$hint_lower" == klebsiella* || "$hint_lower" == "k_pneumoniae" || "$hint_lower" == "raoultella"* ]]; then
    if [ "${KLEBSIELLA_KLEBORATE:-true}" = "true" ] && command -v kleborate >/dev/null 2>&1; then
      log "  Running Kleborate: $sample"
      kleborate \
        --assembly "$asm" \
        --all \
        --outfile "results/species/${sample}.kleborate.tsv" \
        2>> "results/logs/${sample}.kleborate.log" || warn "Kleborate failed for $sample"
    else
      warn "  Kleborate not available or disabled — skipping"
    fi

  # --- Escherichia coli → ECTyper --------------------------------------------
  elif [[ "$hint_lower" == *"coli"* || "$hint_lower" == "e_coli" || "$hint_lower" == "escherichia"* ]]; then
    if [ "${ECOLI_ECTYPER:-true}" = "true" ] && command -v ectyper >/dev/null 2>&1; then
      log "  Running ECTyper: $sample"
      ectyper \
        --input "$asm" \
        --output "results/species/${sample}_ectyper" \
        --cores "${THREADS:-4}" \
        2>> "results/logs/${sample}.ectyper.log" || warn "ECTyper failed for $sample"
    else
      warn "  ECTyper not available or disabled — skipping"
    fi

  # --- Salmonella → SISTR ----------------------------------------------------
  elif [[ "$hint_lower" == salmonella* ]]; then
    if [ "${SALMONELLA_SISTR:-true}" = "true" ] && command -v sistr >/dev/null 2>&1; then
      log "  Running SISTR: $sample"
      sistr \
        --input-fasta "$asm" \
        --output-prediction "results/species/${sample}.sistr.tsv" \
        --threads "${THREADS:-4}" \
        2>> "results/logs/${sample}.sistr.log" || warn "SISTR failed for $sample"
    else
      warn "  SISTR not available or disabled — skipping"
    fi

  # --- Staphylococcus aureus → spaTyper --------------------------------------
  elif [[ "$hint_lower" == *"aureus"* || "$hint_lower" == "s_aureus" ]]; then
    if [ "${SAUREUS_SPATYPER:-false}" = "true" ] && command -v spaTyper >/dev/null 2>&1; then
      log "  Running spaTyper: $sample"
      spaTyper \
        --fasta "$asm" \
        --output "results/species/${sample}.spatyper.tsv" \
        2>> "results/logs/${sample}.spatyper.log" || warn "spaTyper failed for $sample"
    else
      log "  spaTyper disabled or not installed — skipping S. aureus module"
    fi

  # Pseudomonas aeruginosa
  # No standalone typer — MLST + AMRFinderPlus organism-aware is sufficient
    PSEUDOMONAS_ENABLED=true
  
  # --- No module for this species --------------------------------------------
  else
    log "  No species module configured for hint: '${species_hint:-unknown}' — skipping"
  fi

done < <(read_samples "$SAMPLEIDS")

log "=== SPECIES MODULES STEP COMPLETE — see results/species/ ==="
