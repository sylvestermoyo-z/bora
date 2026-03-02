#!/usr/bin/env bash
# =============================================================================
# BORA summarize.sh — Consolidated public-health-ready summary report
# Joins MLST, AMR counts, and assembly stats per sample.
# Missing values are reported as "-" rather than silently dropped.
# =============================================================================
set -euo pipefail

SAMPLEIDS="${1:-config/sampleids.txt}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"
load_config

log "=== SUMMARY STEP STARTED ==="
mkdir -p results/reports

OUTFILE="results/reports/bora_summary.tsv"

# --- Write header ------------------------------------------------------------
echo -e "sample\tspecies_hint\tMLST_scheme\tST\tAMR_gene_count\tAMR_drug_classes\tassembly_contigs\tassembly_N50\tassembly_length_bp\tnotes" > "$OUTFILE"

while IFS= read -r sample; do

  # --- Species hint ----------------------------------------------------------
  hint="-"
  if [ -f "results/species/species_hints.tsv" ]; then
    hint=$(awk -v s="$sample" -F'\t' '$1==s{print $2}' "results/species/species_hints.tsv")
    hint="${hint:--}"
  fi

  # --- MLST ------------------------------------------------------------------
  scheme="-"
  st="-"
  if [ -f "results/typing/mlst_results.tsv" ]; then
    mlst_line=$(awk -v s="$sample" -F'\t' '$1==s{print}' "results/typing/mlst_results.tsv")
    if [ -n "$mlst_line" ]; then
      scheme=$(echo "$mlst_line" | cut -f2)
      st=$(echo "$mlst_line" | cut -f3)
    fi
  fi

  # --- AMR -------------------------------------------------------------------
  amr_count="-"
  amr_classes="-"
  amr_file="results/amr/${sample}.amrfinder.tsv"
  if [ -f "$amr_file" ] && [ "$(wc -l < "$amr_file")" -gt 1 ]; then
    amr_count=$(tail -n +2 "$amr_file" | wc -l)
    # Extract unique drug classes (column 12 in AMRFinderPlus output: "Drug class")
    amr_classes=$(tail -n +2 "$amr_file" | cut -f12 | sort -u | grep -v '^$' | tr '\n' ',' | sed 's/,$//')
    amr_classes="${amr_classes:--}"
  fi

  # --- Assembly stats from QUAST --------------------------------------------
  contigs="-"
  n50="-"
  total_len="-"
  quast_tsv="results/assembly/quast_summary/report.tsv"
  if [ -f "$quast_tsv" ]; then
    # QUAST report.tsv has metrics as rows and assemblies as columns
    asm_path=$(find_assembly "$sample" 2>/dev/null || echo "")
    asm_name=$(basename "$asm_path" 2>/dev/null || echo "")
    if [ -n "$asm_name" ]; then
      contigs=$(grep "^# contigs " "$quast_tsv" | cut -f2 2>/dev/null || echo "-")
      n50=$(grep "^N50" "$quast_tsv" | cut -f2 2>/dev/null || echo "-")
      total_len=$(grep "^Total length" "$quast_tsv" | cut -f2 2>/dev/null || echo "-")
    fi
  fi

  # --- Notes -----------------------------------------------------------------
  notes="-"
  # Flag samples with no AMR genes found
  if [ "$amr_count" = "0" ]; then
    notes="No AMR genes detected"
  fi
  # Flag unknown ST
  if [ "$st" = "-" ] || [ "$st" = "?" ]; then
    notes="${notes}; Novel or unknown ST"
    notes="${notes# ; }"  # trim leading separator
  fi
  [ "$notes" = "-; Novel or unknown ST" ] && notes="Novel or unknown ST"

  echo -e "${sample}\t${hint}\t${scheme}\t${st}\t${amr_count}\t${amr_classes}\t${contigs}\t${n50}\t${total_len}\t${notes}" >> "$OUTFILE"

done < <(read_samples "$SAMPLEIDS")

log "=== SUMMARY COMPLETE ==="
log "Report written to: $OUTFILE"
log ""
log "--- Quick cohort stats ---"
total=$(read_samples "$SAMPLEIDS" | wc -l)
typed=$(awk -F'\t' 'NR>1 && $4 != "-" && $4 != "?"' "$OUTFILE" | wc -l)
log "Samples processed:  $total"
log "Samples typed (ST): $typed / $total"
log ""
