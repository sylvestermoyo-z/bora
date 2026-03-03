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
# Returns empty string if no match (organism flag omitted — acquired genes
# are still detected, only chromosomal mutation calling is skipped).
#
# Supported AMRFinderPlus organisms (as of v3.12):
#   Acinetobacter_baumannii, Burkholderia_cepacia, Burkholderia_pseudomallei,
#   Campylobacter, Clostridioides_difficile, Enterococcus_faecalis,
#   Enterococcus_faecium, Escherichia, Klebsiella, Neisseria,
#   Pseudomonas_aeruginosa, Salmonella, Staphylococcus_aureus,
#   Staphylococcus_pseudintermedius, Streptococcus_agalactiae,
#   Streptococcus_pneumoniae, Streptococcus_pyogenes, Vibrio_cholerae
map_amrfinder_organism() {
  local hint="${1,,}"  # lowercase

  case "$hint" in
    # ESKAPE pathogens
    klebsiella*|k_pneumoniae|kpneumoniae)
      echo "Klebsiella" ;;
    escherichia*|e_coli|ecoli)
      echo "Escherichia" ;;
    acinetobacter*|a_baumannii|abaumannii)
      echo "Acinetobacter_baumannii" ;;
    staphylococcus*aureus*|s_aureus|saureus)
      echo "Staphylococcus_aureus" ;;
    enterococcus*faecalis*|e_faecalis)
      echo "Enterococcus_faecalis" ;;
    enterococcus*faecium*|e_faecium)
      echo "Enterococcus_faecium" ;;
    # Pseudomonas — important BSI pathogen, chromosome-level resistance common
    pseudomonas*|p_aeruginosa|paeruginosa)
      echo "Pseudomonas_aeruginosa" ;;
    # Other Gram-negatives
    salmonella*)
      echo "Salmonella" ;;
    campylobacter*)
      echo "Campylobacter" ;;
    neisseria*)
      echo "Neisseria" ;;
    vibrio*cholerae*|v_cholerae)
      echo "Vibrio_cholerae" ;;
    burkholderia*cepacia*|b_cepacia)
      echo "Burkholderia_cepacia" ;;
    burkholderia*pseudomallei*|b_pseudomallei)
      echo "Burkholderia_pseudomallei" ;;
    # Gram-positives
    staphylococcus*pseudintermedius*)
      echo "Staphylococcus_pseudintermedius" ;;
    streptococcus*pneumoniae*|s_pneumoniae)
      echo "Streptococcus_pneumoniae" ;;
    streptococcus*pyogenes*|s_pyogenes)
      echo "Streptococcus_pyogenes" ;;
    streptococcus*agalactiae*|s_agalactiae)
      echo "Streptococcus_agalactiae" ;;
    clostridioides*difficile*|clostridium*difficile*|c_difficile)
      echo "Clostridioides_difficile" ;;
    # Organisms with no AMRFinderPlus mutation support
    # (acquired gene detection still works — organism flag just omitted)
    raoultella*)
      echo "Klebsiella" ;;  # phylogenetically within Klebsiella; best available
    citrobacter*|serratia*|enterobacter*|proteus*|morganella*|providencia*)
      echo "" ;;
    *)
      echo "" ;;
  esac
}

# --- MASH organism-to-BORA-hint mapper ---------------------------------------
# Converts a raw MASH top-hit organism string (from RefSeq labels) to a
# clean BORA species_hint that both amr_core.sh and species_modules.sh
# can understand. This is the bridge between species_id.sh and downstream.
map_organism_to_hint() {
  local raw="${1,,}"  # lowercase

  case "$raw" in
    *klebsiella*pneumoniae*|*klebsiella*variicola*|*klebsiella*quasipneumoniae*)
      echo "Klebsiella" ;;
    *raoultella*)
      echo "Klebsiella" ;;  # Raoultella → Klebsiella module (phylogenetic proximity)
    *escherichia*coli*|*shigella*)
      echo "E_coli" ;;       # Shigella is phylogenetically E. coli; ECTyper handles it
    *acinetobacter*baumannii*)
      echo "Acinetobacter" ;;
    *staphylococcus*aureus*)
      echo "Staphylococcus_aureus" ;;
    *pseudomonas*aeruginosa*)
      echo "Pseudomonas_aeruginosa" ;;
    *salmonella*)
      echo "Salmonella" ;;
    *enterococcus*faecalis*)
      echo "Enterococcus_faecalis" ;;
    *enterococcus*faecium*)
      echo "Enterococcus_faecium" ;;
    *streptococcus*pneumoniae*)
      echo "Streptococcus_pneumoniae" ;;
    *streptococcus*pyogenes*)
      echo "Streptococcus_pyogenes" ;;
    *streptococcus*agalactiae*)
      echo "Streptococcus_agalactiae" ;;
    *campylobacter*)
      echo "Campylobacter" ;;
    *neisseria*)
      echo "Neisseria" ;;
    *citrobacter*)
      echo "Citrobacter" ;;
    *serratia*)
      echo "Serratia" ;;
    *enterobacter*)
      echo "Enterobacter" ;;
    *proteus*)
      echo "Proteus" ;;
    *burkholderia*cepacia*)
      echo "Burkholderia_cepacia" ;;
    *burkholderia*pseudomallei*)
      echo "Burkholderia_pseudomallei" ;;
    *clostridioides*|*clostridium*difficile*)
      echo "Clostridioides_difficile" ;;
    *vibrio*cholerae*)
      echo "Vibrio_cholerae" ;;
    *)
      # Unknown or not yet mapped — return raw name truncated to first 2 words
      echo "$raw" | awk '{print $1"_"$2}' | tr -d '()[]' ;;
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
