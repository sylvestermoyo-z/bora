#!/usr/bin/env bash
# =============================================================================
# BORA run_bora.sh — One-command pipeline orchestrator
# Usage: bash pipeline/run_bora.sh -i config/sampleids.txt [-t 8] [-c config/bora.cfg]
# =============================================================================
set -euo pipefail

# --- Usage -------------------------------------------------------------------
usage() {
  cat <<EOF

Usage: bash pipeline/run_bora.sh -i SAMPLEIDS [OPTIONS]

Required:
  -i  Path to sample IDs file (e.g. config/sampleids.txt)

Options:
  -t  Number of threads (default: 8)
  -c  Path to config file (default: config/bora.cfg)
  -s  Path to species hints file (TSV: sample<TAB>species_hint)
        If not provided, all samples run without organism context.
  -h  Show this help message

Example:
  bash pipeline/run_bora.sh -i config/sampleids.txt -t 8
  bash pipeline/run_bora.sh -i config/sampleids.txt -t 8 -s config/species_hints.tsv

EOF
  exit 1
}

# --- Parse arguments ---------------------------------------------------------
SAMPLEIDS=""
THREADS=8
BORA_CFG="config/bora.cfg"
SPECIES_HINTS=""

while getopts "i:t:c:s:h" opt; do
  case $opt in
    i) SAMPLEIDS="$OPTARG" ;;
    t) THREADS="$OPTARG" ;;
    c) BORA_CFG="$OPTARG" ;;
    s) SPECIES_HINTS="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

[ -z "$SAMPLEIDS" ] && usage
[ ! -f "$SAMPLEIDS" ] && { echo "[ERROR] Sample IDs file not found: $SAMPLEIDS"; exit 1; }
[ ! -f "$BORA_CFG" ] && { echo "[ERROR] Config file not found: $BORA_CFG"; exit 1; }

export BORA_CFG
export UMOJA_THREADS="$THREADS"   # backward compat alias

# --- Load config (for DATA_DIR etc.) -----------------------------------------
# shellcheck source=/dev/null
source "$BORA_CFG"
THREADS="${THREADS:-8}"
export THREADS

# --- Check conda environment -------------------------------------------------
if [ -z "${CONDA_DEFAULT_ENV:-}" ] || [ "$CONDA_DEFAULT_ENV" != "bora" ]; then
  echo ""
  echo "[WARN] You do not appear to have the 'bora' conda environment active."
  echo "       Run: conda activate bora"
  echo "       Then re-run this script."
  echo ""
  read -rp "Continue anyway? (y/N): " yn
  [[ "$yn" =~ ^[Yy]$ ]] || exit 1
fi

# --- Set up species hints ----------------------------------------------------
mkdir -p results/species
HINTS_FILE="results/species/species_hints.tsv"

if [ -n "$SPECIES_HINTS" ] && [ -f "$SPECIES_HINTS" ]; then
  cp "$SPECIES_HINTS" "$HINTS_FILE"
  echo "[INFO] Species hints loaded from $SPECIES_HINTS"
else
  # Create an empty hints file — samples will run without organism context
  echo -e "sample\tspecies_hint" > "$HINTS_FILE"
  echo "[INFO] No species hints file provided — AMR will run without --organism flag"
  echo "       To add hints: create a TSV file with columns: sample<TAB>species_hint"
  echo "       Valid hints: Klebsiella, E_coli, Acinetobacter, Staphylococcus_aureus, Salmonella"
fi

# --- Confirm samples and files exist -----------------------------------------
echo ""
echo "[BORA] Validating sample FASTQ files..."
ALL_OK=true
while IFS= read -r sample; do
  R1="${DATA_DIR:-data}/${sample}_R1.fastq.gz"
  R2="${DATA_DIR:-data}/${sample}_R2.fastq.gz"
  if [ ! -f "$R1" ] || [ ! -f "$R2" ]; then
    echo "[ERROR] Missing files for sample: $sample"
    echo "        Expected: $R1"
    echo "                  $R2"
    ALL_OK=false
  fi
done < <(grep -v '^\s*#' "$SAMPLEIDS" | grep -v '^\s*$')

if [ "$ALL_OK" = false ]; then
  echo ""
  echo "[ERROR] One or more FASTQ files are missing. Check DATA_DIR in config/bora.cfg"
  exit 1
fi
echo "[BORA] All FASTQ files found."

# --- Ensure result directories exist ----------------------------------------
mkdir -p results/{logs,qc,filtered,assembly,typing,amr,species,reports}

# --- Pipeline execution ------------------------------------------------------
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)"
START=$(date +%s)

echo ""
echo "============================================================"
echo "  BORA: Bacterial Omics for Resource-limited Analysis"
echo "  Samples: $(grep -v '^\s*#' "$SAMPLEIDS" | grep -v '^\s*$' | wc -l)"
echo "  Threads: $THREADS"
echo "  Config:  $BORA_CFG"
echo "  Started: $(date)"
echo "============================================================"
echo ""

run_step() {
  local name="$1"; shift
  echo ""
  echo "------------------------------------------------------------"
  echo "  STEP: $name"
  echo "------------------------------------------------------------"
  "$@"
}

run_step "Quality Control"       bash "${BIN}/qc.sh"              "$SAMPLEIDS"
run_step "Read Filtering"        bash "${BIN}/filtering.sh"        "$SAMPLEIDS"
run_step "Assembly"              bash "${BIN}/assembly.sh"         "$SAMPLEIDS"
run_step "Species Identification" bash "${BIN}/species_id.sh"      "$SAMPLEIDS"
run_step "MLST Typing"           bash "${BIN}/typing_core.sh"      "$SAMPLEIDS"
run_step "AMR Detection"         bash "${BIN}/amr_core.sh"         "$SAMPLEIDS"
run_step "Species Modules"       bash "${BIN}/species_modules.sh"  "$SAMPLEIDS"
run_step "Summary Report"        bash "${BIN}/summarize.sh"        "$SAMPLEIDS"

# --- Done --------------------------------------------------------------------
END=$(date +%s)
ELAPSED=$(( END - START ))
MINS=$(( ELAPSED / 60 ))
SECS=$(( ELAPSED % 60 ))

echo ""
echo "============================================================"
echo "  BORA PIPELINE COMPLETE"
echo "  Time elapsed: ${MINS}m ${SECS}s"
echo "  Summary:      results/reports/bora_summary.tsv"
echo "  QC report:    results/qc/multiqc_report.html"
echo "  Assembly QC:  results/assembly/quast_summary/report.tsv"
echo "============================================================"
echo ""
