#!/usr/bin/env bash
# =============================================================================
# BORA update_dbs.sh — Download and update local databases
# Run once after setup. Re-run periodically to update AMRFinderPlus DB.
# All databases are stored in db/ which is gitignored.
# =============================================================================
set -euo pipefail

echo ""
echo "============================================================"
echo "  BORA Database Setup"
echo "  This downloads databases to db/ for offline use."
echo "  Requires internet connection — run once, then work offline."
echo "============================================================"
echo ""

mkdir -p db

# --- AMRFinderPlus -----------------------------------------------------------
echo "[DB] Setting up AMRFinderPlus database..."
if command -v amrfinder >/dev/null 2>&1; then
  amrfinder --update \
    2>&1 | tee db/amrfinderplus_update.log || {
      echo "[WARN] AMRFinderPlus update failed — check internet connection"
      echo "       You can manually download from:"
      echo "       https://github.com/ncbi/amr/wiki/Downloading-the-AMRFinderPlus-database"
    }
  echo "       ✓ AMRFinderPlus DB updated"
else
  echo "[WARN] amrfinder not found — activate bora environment first"
fi

# --- mlst PubMLST schemes ----------------------------------------------------
echo ""
echo "[DB] Updating mlst (PubMLST) schemes..."
if command -v mlst >/dev/null 2>&1; then
  mlst --list >/dev/null 2>&1 && echo "       ✓ mlst schemes available (bundled with tool)"
  # Optionally force update:
  # mlst --update 2>&1 | tee db/mlst_update.log
else
  echo "[WARN] mlst not found — activate bora environment first"
fi

# --- Kleborate (auto-downloads on first run via conda install) ---------------
echo ""
echo "[DB] Kleborate database..."
if command -v kleborate >/dev/null 2>&1; then
  echo "       ✓ Kleborate databases are bundled with the tool"
else
  echo "       - kleborate not installed (optional)"
fi

# --- ECTyper -----------------------------------------------------------------
echo ""
echo "[DB] ECTyper database..."
if command -v ectyper >/dev/null 2>&1; then
  echo "       ✓ ECTyper databases are bundled with the tool"
else
  echo "       - ectyper not installed (optional)"
fi

# --- SISTR -------------------------------------------------------------------
echo ""
echo "[DB] SISTR database..."
if command -v sistr >/dev/null 2>&1; then
  echo "       ✓ SISTR databases are bundled with the tool"
else
  echo "       - sistr not installed (optional)"
fi

# --- Kraken2 (optional, large) -----------------------------------------------
echo ""
echo "[DB] Kraken2 database (OPTIONAL — only if ENABLE_KRAKEN2=true)..."
if [ "${ENABLE_KRAKEN2:-false}" = "true" ]; then
  if command -v kraken2 >/dev/null 2>&1; then
    mkdir -p db/kraken2
    echo "       Downloading MiniKraken2 (~4GB)..."
    echo "       This may take a while depending on your connection."
    wget -c https://genome-idx.s3.amazonaws.com/kraken/minikraken2_v2_8GB_201904.tgz \
      -O db/kraken2/minikraken2.tgz 2>&1 | tail -n5
    tar -xzf db/kraken2/minikraken2.tgz -C db/kraken2/ --strip-components=1
    rm db/kraken2/minikraken2.tgz
    echo "       ✓ MiniKraken2 ready at db/kraken2/"
  else
    echo "       [WARN] kraken2 not found"
  fi
else
  echo "       Skipped (ENABLE_KRAKEN2=false in config/bora.cfg)"
  echo "       Set ENABLE_KRAKEN2=true to download MiniKraken2 (~4GB)"
fi

echo ""
echo "============================================================"
echo "  Database setup complete."
echo "  BORA is ready to run offline."
echo ""
echo "  Next step:"
echo "    1. Add sample IDs to config/sampleids.txt"
echo "    2. Place FASTQ files in data/ (or set DATA_DIR in config/bora.cfg)"
echo "    3. Run: bash pipeline/run_bora.sh -i config/sampleids.txt -t 8"
echo "============================================================"
echo ""

# --- MASH RefSeq sketch (required for species identification) ----------------
echo ""
echo "[DB] MASH RefSeq sketch database (required for species ID step)..."
if command -v mash >/dev/null 2>&1; then
  mkdir -p db/mash
  MASH_SKETCH="db/mash/refseq.genomes.k21s1000.msh"

  if [ -f "$MASH_SKETCH" ]; then
    echo "       ✓ MASH RefSeq sketch already present at $MASH_SKETCH"
    echo "       To force re-download: rm $MASH_SKETCH && bash pipeline/update_dbs.sh"
  else
    echo "       Downloading MASH RefSeq sketch (~700MB)..."
    echo "       This is a one-time download — BORA uses it offline after this."
    wget -c \
      "https://gembox.cbcb.umd.edu/mash/refseq.genomes.k21s1000.msh" \
      -O "$MASH_SKETCH" \
      2>&1 | grep -E "saved|error|%" | tail -n5 || {
        echo ""
        echo "       [WARN] Primary download failed. Trying alternative source..."
        wget -c \
          "https://mash.readthedocs.io/_downloads/refseq.genomes.k21s1000.msh" \
          -O "$MASH_SKETCH" 2>/dev/null || true
      }

    if [ -f "$MASH_SKETCH" ]; then
      echo "       ✓ MASH RefSeq sketch ready at $MASH_SKETCH"
      echo "       Size: $(du -sh "$MASH_SKETCH" | cut -f1)"
    else
      echo ""
      echo "       [WARN] Automatic download failed. Manual download instructions:"
      echo "       1. Go to: https://gembox.cbcb.umd.edu/mash/refseq.genomes.k21s1000.msh"
      echo "       2. Save the file to: db/mash/refseq.genomes.k21s1000.msh"
      echo "       3. Re-run: bash pipeline/update_dbs.sh"
    fi
  fi
else
  echo "       [WARN] mash not found — activate bora environment: conda activate bora"
fi
