#!/usr/bin/env bash
# =============================================================================
# BORA setup.sh — One-time setup: folder scaffold + tool validation
# Run once after cloning the repo and activating the bora conda environment.
# =============================================================================
set -euo pipefail

echo ""
echo "============================================================"
echo "  BORA Setup"
echo "============================================================"

# --- Check conda environment -------------------------------------------------
if [ -z "${CONDA_DEFAULT_ENV:-}" ]; then
  echo "[WARN] No conda environment is active."
  echo "       Please run: conda activate bora"
  echo "       Then re-run this script."
  exit 1
fi

if [ "$CONDA_DEFAULT_ENV" != "bora" ]; then
  echo "[WARN] Active conda environment is '${CONDA_DEFAULT_ENV}', not 'bora'."
  echo "       Run: conda activate bora"
  read -rp "Continue anyway? (y/N): " yn
  [[ "$yn" =~ ^[Yy]$ ]] || exit 1
fi

# --- Create folder structure -------------------------------------------------
echo "[SETUP] Creating result directories..."
mkdir -p results/{logs,qc,filtered,assembly,typing,amr,species,reports}
mkdir -p db
mkdir -p data
echo "        ✓ Done"

# --- Check required tools ----------------------------------------------------
echo "[SETUP] Checking required tools..."

REQUIRED_TOOLS=(
  fastqc
  multiqc
  trim_galore
  shovill
  quast.py
  mlst
  amrfinder
)

MISSING=()
for tool in "${REQUIRED_TOOLS[@]}"; do
  if command -v "$tool" >/dev/null 2>&1; then
    version=$(${tool} --version 2>&1 | head -n1 || echo "version unknown")
    printf "        ✓ %-20s %s\n" "$tool" "$version"
  else
    printf "        ✗ %-20s NOT FOUND\n" "$tool"
    MISSING+=("$tool")
  fi
done

echo ""

# --- Check optional tools ----------------------------------------------------
echo "[SETUP] Checking optional tools..."
OPTIONAL_TOOLS=(kleborate ectyper sistr kraken2 bowtie2)
for tool in "${OPTIONAL_TOOLS[@]}"; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf "        ✓ %-20s (available)\n" "$tool"
  else
    printf "        - %-20s (not found — optional)\n" "$tool"
  fi
done

echo ""

# --- Report missing tools ----------------------------------------------------
if [ ${#MISSING[@]} -gt 0 ]; then
  echo "[ERROR] The following required tools are missing:"
  for t in "${MISSING[@]}"; do
    echo "          - $t"
  done
  echo ""
  echo "        Make sure you have created and activated the bora environment:"
  echo "          conda env create -f envs/environment.yml"
  echo "          conda activate bora"
  exit 1
fi

echo "[SETUP] All required tools found."
echo ""
echo "[SETUP] Next step: download databases"
echo "        bash pipeline/update_dbs.sh"
echo ""
echo "============================================================"
echo "  Setup complete!"
echo "============================================================"
echo ""
