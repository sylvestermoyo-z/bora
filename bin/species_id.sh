#!/usr/bin/env bash
# =============================================================================
# BORA species_id.sh — Assembly-based species identification using MASH
#
# Runs MASH dist against the local RefSeq sketch database to identify the
# most likely species for each assembly. Results are written to:
#   results/species/species_id.tsv       (per-sample top MASH hits)
#   results/species/species_hints.tsv    (auto-generated hints for downstream)
#
# The auto-generated species_hints.tsv feeds directly into:
#   - amr_core.sh       (AMRFinderPlus --organism flag)
#   - species_modules.sh (Kleborate / ECTyper / SISTR / etc.)
#
# If the user provided a manual species hints file via -s in run_bora.sh,
# that file takes precedence. Auto-detection only fills in missing entries.
#
# MASH distance thresholds:
#   < 0.05  → high confidence species call
#   0.05–0.1 → moderate confidence (genus-level reliable, species uncertain)
#   > 0.1   → low confidence (flag for manual review)
# =============================================================================
set -euo pipefail

SAMPLEIDS="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"
load_config

log "=== SPECIES IDENTIFICATION STEP STARTED ==="
require_tool mash

MASH_DB="${MASH_REFSEQ_DB:-db/mash/refseq.genomes.k21s1000.msh}"

if [ ! -f "$MASH_DB" ]; then
  err "MASH RefSeq sketch not found at: ${MASH_DB}
       Run: bash pipeline/update_dbs.sh
       Or set MASH_REFSEQ_DB in config/bora.cfg to your sketch path."
fi

mkdir -p results/species

# Output files
SPECIES_ID_TSV="results/species/species_id.tsv"
AUTO_HINTS_TSV="results/species/species_hints_auto.tsv"

# Write headers
echo -e "sample\ttop_hit_organism\ttop_hit_strain\tmash_distance\tp_value\tmatching_hashes\tconfidence" \
  > "$SPECIES_ID_TSV"
echo -e "sample\tspecies_hint" > "$AUTO_HINTS_TSV"

while IFS= read -r sample; do
  asm=$(find_assembly "$sample")
  log "MASH species ID: $sample"

  # Run MASH dist — query assembly against RefSeq sketch
  mash_raw=$(mash dist \
    -p "${THREADS:-4}" \
    "$MASH_DB" \
    "$asm" \
    2>> "results/logs/${sample}.mash.log")

  if [ -z "$mash_raw" ]; then
    warn "  No MASH results for $sample — skipping species ID"
    echo -e "${sample}\tUnknown\t-\t-\t-\t-\tNO_RESULT" >> "$SPECIES_ID_TSV"
    echo -e "${sample}\t" >> "$AUTO_HINTS_TSV"
    continue
  fi

  # Sort by MASH distance (column 3), take top hit
  top_hit=$(echo "$mash_raw" | sort -gk3 | head -n1)

  # Parse MASH output columns:
  # 1: reference, 2: query, 3: distance, 4: p-value, 5: matching hashes
  ref_path=$(echo "$top_hit" | cut -f1)
  distance=$(echo "$top_hit" | cut -f3)
  pvalue=$(echo "$top_hit"   | cut -f4)
  hashes=$(echo "$top_hit"   | cut -f5)

  # Extract organism name from RefSeq path
  # RefSeq paths look like: .../GCF_000007545.1_ASM754v1/GCF_...genomic.fna.gz
  # The organism name is embedded in the sketch reference label
  organism_raw=$(echo "$ref_path" | grep -oP '\[.*?\]' | head -n1 | tr -d '[]' || \
                 basename "$ref_path" | sed 's/_GCF.*//' | tr '_' ' ')

  # If organism_raw is empty, fall back to basename parsing
  if [ -z "$organism_raw" ]; then
    organism_raw=$(basename "$ref_path" | cut -d'_' -f1-3 | tr '_' ' ')
  fi

  # Assess confidence based on MASH distance
  confidence="HIGH"
  if awk "BEGIN{exit !($distance >= 0.05 && $distance < 0.1)}"; then
    confidence="MODERATE"
  elif awk "BEGIN{exit !($distance >= 0.1)}"; then
    confidence="LOW"
  fi

  log "  Top hit: ${organism_raw} (distance=${distance}, confidence=${confidence})"

  # Write to species ID table
  echo -e "${sample}\t${organism_raw}\t${ref_path}\t${distance}\t${pvalue}\t${hashes}\t${confidence}" \
    >> "$SPECIES_ID_TSV"

  # Map organism name to BORA hint for downstream tools
  hint=$(map_organism_to_hint "$organism_raw")
  echo -e "${sample}\t${hint}" >> "$AUTO_HINTS_TSV"

  # Warn on low confidence
  if [ "$confidence" = "LOW" ]; then
    warn "  LOW confidence species call for $sample (distance=${distance})"
    warn "  Review manually: results/species/species_id.tsv"
  fi

done < <(read_samples "$SAMPLEIDS")

# --- Merge auto-hints with any manually provided hints -----------------------
# Manual hints (from -s flag) take precedence over auto-detected hints.
FINAL_HINTS="results/species/species_hints.tsv"

if [ -f "$FINAL_HINTS" ] && [ "$(wc -l < "$FINAL_HINTS")" -gt 1 ]; then
  log "Merging auto-detected hints with manually provided hints..."
  log "(Manual hints take precedence where both exist)"

  # Build merged file: for each sample, use manual hint if present, else auto
  python3 - <<'PYEOF'
import csv, sys

manual = {}
auto   = {}

# Read manual hints
try:
    with open("results/species/species_hints.tsv") as f:
        for row in csv.reader(f, delimiter='\t'):
            if row and not row[0].startswith('#') and row[0] != 'sample':
                if len(row) > 1 and row[1].strip():
                    manual[row[0]] = row[1]
except FileNotFoundError:
    pass

# Read auto hints
try:
    with open("results/species/species_hints_auto.tsv") as f:
        for row in csv.reader(f, delimiter='\t'):
            if row and not row[0].startswith('#') and row[0] != 'sample':
                if len(row) > 1 and row[1].strip():
                    auto[row[0]] = row[1]
except FileNotFoundError:
    pass

# Merge: manual overrides auto
all_samples = sorted(set(list(manual.keys()) + list(auto.keys())))
with open("results/species/species_hints.tsv", 'w') as out:
    out.write("sample\tspecies_hint\tsource\n")
    for s in all_samples:
        if s in manual:
            out.write(f"{s}\t{manual[s]}\tmanual\n")
        elif s in auto:
            out.write(f"{s}\t{auto[s]}\tauto_mash\n")
        else:
            out.write(f"{s}\t\tunknown\n")

print(f"[INFO] Merged hints written for {len(all_samples)} samples")
PYEOF

else
  # No manual hints — use auto hints as the working hints file
  cp "$AUTO_HINTS_TSV" "$FINAL_HINTS"
  log "Auto-detected species hints written to $FINAL_HINTS"
fi

log "=== SPECIES IDENTIFICATION COMPLETE ==="
log "  Full results:  $SPECIES_ID_TSV"
log "  Working hints: $FINAL_HINTS"
log ""
log "  Summary of species calls:"
awk -F'\t' 'NR>1 {print "  " $1 "\t→ " $2 "\t[" $7 "]"}' "$SPECIES_ID_TSV"
echo ""
