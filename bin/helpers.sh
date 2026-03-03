#!/usr/bin/env bash
# =============================================================================
# BORA helpers.sh — shared utility functions
# Sourced by all other bin/ scripts. Do not run directly.
# =============================================================================

# --- Logging -----------------------------------------------------------------
log()  { echo "[$(date +'%F %T')] [INFO]  $*"; }
warn() { echo "[$(date +'%F %T')] [WARN]  $*" >&2; }
err()  { echo "[$(date +'%F %T')] [ERROR] $*" >&2; exit 1; }

# --- Load config -------------------------------------------------------------
load_config() {
  local cfg="${BORA_CFG:-config/bora.cfg}"
  if [ ! -f "$cfg" ]; then
    err "Config file not found: $cfg — run from the BORA root directory"
  fi
  # shellcheck source=/dev/null
  source "$cfg"
  log "Config loaded from $cfg"
}

load_species_cfg() {
  local scfg="${BORA_SPECIES_CFG:-config/species_modules.cfg}"
  if [ ! -f "$scfg" ]; then
    warn "Species config not found: $scfg — species modules will be skipped"
    return
  fi
  # shellcheck source=/dev/null
  source "$scfg"
}

# --- Assembly output resolver ------------------------------------------------
# Finds the assembled contigs regardless of assembler used.
# Returns the path or exits with error if not found.
find_assembly() {
  local sample="$1"
  local adir="results/assembly/${sample}"

  # Shovill outputs contigs.fa; SPAdes outputs contigs.fasta or scaffolds.fasta
  for fname in contigs.fa contigs.fasta scaffolds.fasta; do
    if [ -f "${adir}/${fname}" ]; then
      echo "${adir}/${fname}"
      return 0
    fi
  done

  err "No assembly found for sample '${sample}' in ${adir}. Check assembly logs."
}

# --- FASTQ file resolver -----------------------------------------------------
# Returns paths to R1 and R2 for a given sample ID.
# Exports R1 and R2 variables.
resolve_fastq() {
  local sample="$1"
  local datadir="${DATA_DIR:-data}"

  R1="${datadir}/${sample}_R1.fastq.gz"
  R2="${datadir}/${sample}_R2.fastq.gz"

  if [ ! -f "$R1" ]; then
    err "R1 not found for sample '${sample}': expected ${R1}"
  fi
  if [ ! -f "$R2" ]; then
    err "R2 not found for sample '${sample}': expected ${R2}"
  fi

  export R1 R2
}

# --- AMRFinderPlus organism mapper -------------------------------------------
# Maps common species names / hints to AMRFinderPlus --organism values.
# Returns empty string if no match (organism flag omitted = still works).
map_amrfinder_organism() {
  local hint="${1,,}"  # lowercase

  case "$hint" in
    klebsiella*|kpneumoniae|k_pneumoniae)
      echo "Klebsiella" ;;
    ecoli|e_coli|escherichia*)
      echo "Escherichia" ;;
    acinetobacter*|abaumannii|a_baumannii)
      echo "Acinetobacter_baumannii" ;;
    staphylococcus*|saureus|s_aureus)
      echo "Staphylococcus_aureus" ;;
    pseudomonas*|paeruginosa|p_aeruginosa)
      echo "Pseudomonas_aeruginosa" ;;
    salmonella*)
      echo "Salmonella" ;;
    citrobacter*)
      echo "" ;;   # No organism-specific mutations in AMRFinderPlus for Citrobacter
    raoultella*)
      echo "Klebsiella" ;;  # Raoultella is phylogenetically close; best approximation
    serratia*)
      echo "" ;;
    *)
      echo "" ;;
  esac
}

# --- Sample list reader ------------------------------------------------------
# Reads sampleids.txt, skipping blank lines and comment lines.
read_samples() {
  local samplefile="$1"
  if [ ! -f "$samplefile" ]; then
    err "Sample ID file not found: $samplefile"
  fi
  grep -v '^\s*#' "$samplefile" | grep -v '^\s*$'
}

# --- Tool check --------------------------------------------------------------
require_tool() {
  command -v "$1" >/dev/null 2>&1 || err "Required tool not found: $1 — run: conda activate bora"
}

# --- Result directory guard --------------------------------------------------
ensure_result_dirs() {
  for d in results/logs results/qc results/filtered results/assembly \
            results/typing results/amr results/species results/reports; do
    mkdir -p "$d"
  done
}
