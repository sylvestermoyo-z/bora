#!/usr/bin/env bash
# =============================================================================
# BORA amr_core.sh — Organism-aware AMR gene detection
# Uses NCBI AMRFinderPlus with --organism flag where supported.
# The species_hint file is read from results/species/species_hints.tsv
# (written by run_bora.sh from sampleids.txt or user-provided hints).
# =============================================================================
set -euo pipefail

SAMPLEIDS="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"
load_config

log "=== AMR DETECTION STEP STARTED ==="
require_tool amrfinder

OUTFILE="results/amr/amrfinder_combined.tsv"
mkdir -p results/amr

# Write combined header (AMRFinderPlus header from first run)
HEADER_WRITTEN=false

while IFS= read -r sample; do
  asm=$(find_assembly "$sample")
  log "AMRFinderPlus: $sample ($asm)"

  # Read species hint if available
  hint_file="results/species/species_hints.tsv"
  species_hint=""
  if [ -f "$hint_file" ]; then
    species_hint=$(awk -v s="$sample" -F'\t' '$1==s{print $2}' "$hint_file")
  fi

  # Map hint to AMRFinderPlus organism flag
  organism=$(map_amrfinder_organism "$species_hint")

  # Build organism flag
  org_flag=""
  if [ -n "$organism" ]; then
    org_flag="--organism $organism"
    log "  Using organism context: $organism"
  else
    log "  No organism context available — running without --organism flag"
  fi

  # Run AMRFinderPlus
  tmp_out="results/amr/${sample}.amrfinder.tsv"

  # shellcheck disable=SC2086
  amrfinder \
    --nucleotide "$asm" \
    --threads "${THREADS:-4}" \
    --database "${AMRFINDER_DB:-db/amrfinderplus}" \
    --name "$sample" \
    $org_flag \
    --output "$tmp_out" \
    2>> "results/logs/${sample}.amr.log"

  # Append to combined file
  if [ "$HEADER_WRITTEN" = false ]; then
    cat "$tmp_out" > "$OUTFILE"
    HEADER_WRITTEN=true
  else
    # Skip header line (line 1) when appending
    tail -n +2 "$tmp_out" >> "$OUTFILE"
  fi

  # Count AMR genes found
  amr_count=$(tail -n +2 "$tmp_out" | wc -l)
  log "  AMR genes found: $amr_count"

done < <(read_samples "$SAMPLEIDS")

log "=== AMR DETECTION COMPLETE — see $OUTFILE ==="
