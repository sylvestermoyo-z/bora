# BORA: Bacterial Omics for Resource-limited Analysis

> *Bora* (Swahili): *better, best* — built to deliver better genomic surveillance where it is needed most.

BORA is a modular, offline-capable pipeline for whole-genome sequencing (WGS) analysis of bacterial bloodstream infection (BSI) isolates. It is designed specifically for **resource-limited settings** — running on a standard laptop (8 threads, 16 GB RAM) via Linux or Windows Subsystem for Linux (WSL), with no internet connection required after initial setup.

BORA takes raw Illumina paired-end FASTQ reads and produces actionable outputs: assembly quality metrics, MLST sequence types, AMR gene profiles, species-specific typing, and a consolidated public-health-ready summary report.

---

## Why BORA?

- **Offline-first:** all databases are stored locally after one-time download
- **Resource-aware:** optimised defaults for modest hardware (8 threads, 16 GB RAM)
- **BSI-focused:** built around ESKAPE pathogens (*K. pneumoniae*, *E. coli*, *A. baumannii*, *S. aureus*)
- **WSL-compatible:** fully validated on Windows Subsystem for Linux 2
- **Public health outputs:** results framed for surveillance reports and policy briefs
- **Modular:** enable or disable species-specific add-ons as needed

---

## Quickstart (From Scratch)

### 1. Install Miniconda

```bash
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh
```

Follow the prompts. When asked "Do you wish the installer to initialize Miniconda3?", type **yes**. Then restart your terminal or run:

```bash
source ~/.bashrc
```

Verify conda is working:

```bash
conda --version
```

### 2. Clone BORA

```bash
git clone https://github.com/sylvestermoyo-z/bora.git
cd bora
```

### 3. Create the BORA Conda Environment

```bash
conda env create -f envs/environment.yml
conda activate bora
```

This installs all required tools in one step. It may take 10–20 minutes on first run.

### 4. Run One-Time Setup

```bash
bash pipeline/setup.sh
```

This checks that all tools are correctly installed and creates the results folder structure.

### 5. Download Local Databases (One-Time)

```bash
bash pipeline/update_dbs.sh
```

This downloads AMRFinderPlus and other required databases to the `db/` folder. Run once, then BORA works fully offline.

### 6. Prepare Your Sample List

Create `config/sampleids.txt` with one sample ID per line:

```
BSI_001
BSI_002
BSI_003
```

Place your paired FASTQ files in the `data/` folder following this naming convention:

```
data/BSI_001_R1.fastq.gz
data/BSI_001_R2.fastq.gz
data/BSI_002_R1.fastq.gz
data/BSI_002_R2.fastq.gz
```

> **Note:** FASTQ files can also be on an external drive or another location. Set the path in `config/bora.cfg` using the `DATA_DIR` variable.

### 7. Run the Pipeline

```bash
bash pipeline/run_bora.sh -i config/sampleids.txt -t 8
```

Results are written to `results/`. The final summary is at `results/reports/bora_summary.tsv`.

---

## Input & Output

### Input
- `config/sampleids.txt` — list of sample IDs, one per line
- Paired FASTQ files (`SAMPLEID_R1.fastq.gz` / `SAMPLEID_R2.fastq.gz`)

### Output

| Folder | Contents |
|---|---|
| `results/qc/` | FastQC reports + MultiQC summary |
| `results/filtered/` | Trimmed reads after quality filtering |
| `results/assembly/` | Assembled contigs + QUAST quality stats |
| `results/typing/` | MLST sequence types |
| `results/amr/` | AMR gene calls (AMRFinderPlus) |
| `results/species/` | Species-specific outputs (Kleborate, ECTyper, SISTR) |
| `results/reports/` | Consolidated TSV summary + per-sample logs |

---

## Core Tools

| Step | Tool | Notes |
|---|---|---|
| Quality control | FastQC, MultiQC | Read quality assessment |
| Trimming | Trim Galore! | Adapter removal + quality trimming |
| Assembly | Shovill (SPAdes) | De novo assembly, optimised for bacteria |
| Assembly QC | QUAST | Contig stats: N50, total length, count |
| MLST typing | mlst (Torsten Seemann) | PubMLST schemes, local DB |
| AMR detection | AMRFinderPlus (NCBI) | Organism-aware AMR gene + mutation calling |
| Species modules | Kleborate, ECTyper, SISTR | Enabled per species_hint |

---

## Configuration

Edit `config/bora.cfg` to set threads, memory, data directory, and toggle optional modules:

```bash
THREADS=8
MEMORY_GB=16
DATA_DIR="data"
ENABLE_KRAKEN2=false
ENABLE_SPECIES_MODULES=true
AMRFINDER_DB="db/amrfinderplus"
```

Edit `config/species_modules.cfg` to enable or disable species-specific tools:

```bash
KLEBSIELLA_KLEBORATE=true
ECOLI_ECTYPER=true
SALMONELLA_SISTR=true
SAUREUS_SPATYPER=false
```

---

## WSL-Specific Notes

BORA is fully tested on WSL2 (Ubuntu 22.04). 

### Finding your Windows FASTQ file path in WSL

Your Windows drives are automatically mounted under `/mnt/` in WSL:

| Windows location | WSL path |
|---|---|
| `C:\Users\Sylvester\Documents\fastq\` | `/mnt/c/Users/Sylvester/Documents/fastq` |
| `D:\sequencing_data\` | `/mnt/d/sequencing_data` |
| `E:\BSI_project\` (USB drive) | `/mnt/e/BSI_project` |

To find the exact WSL path for any folder:
```bash
# In WSL, navigate to the folder
cd /mnt/c/Users/
ls                          # find your Windows username
cd YourWindowsUsername
ls                          # navigate to your FASTQ folder
pwd                         # copy the path shown
```

Then set it in `config/bora.cfg`:
```bash
DATA_DIR="/mnt/c/Users/YourWindowsUsername/Documents/sequencing_data"
```

### Performance tip

Running BORA with `DATA_DIR` pointing to `/mnt/c/` or `/mnt/d/` works but is slower due to cross-filesystem I/O. For better speed with large batches, copy your FASTQ files into the WSL-side `bora/data/` folder first:

```bash
cp /mnt/d/my_fastq_files/*.fastq.gz ~/bora/data/
```

### WSL2 RAM allocation

WSL2 RAM is capped by default (often 50% of system RAM). To allocate more, create or edit `C:\Users\YourWindowsUsername\.wslconfig`:

```ini
[wsl2]
memory=14GB
processors=8
```

Then restart WSL: open PowerShell and run `wsl --shutdown`, then reopen WSL.

---

## Common Issues & Fixes

| Problem | Fix |
|---|---|
| `conda: command not found` | Run `source ~/.bashrc` then retry |
| Environment name `bora` already exists | Run `conda env remove -n bora` then recreate |
| `Missing file: data/SAMPLE_R1.fastq.gz` | Check FASTQ naming and `DATA_DIR` in config |
| AMRFinderPlus not finding DB | Run `bash pipeline/update_dbs.sh` |
| Low RAM / pipeline crashes | Reduce `THREADS` in `config/bora.cfg` to 4 |

---

## Repository Structure

```
bora/
├── README.md
├── LICENSE
├── CITATION.cff
├── config/
│   ├── bora.cfg                # Global settings (threads, memory, paths)
│   ├── species_modules.cfg     # Toggle species-specific add-ons
│   └── sampleids.txt           # Your sample list (you create this)
├── envs/
│   └── environment.yml         # Conda environment (all dependencies)
├── bin/
│   ├── helpers.sh              # Shared utility functions
│   ├── qc.sh                   # FastQC + MultiQC
│   ├── filtering.sh            # Trim Galore!
│   ├── assembly.sh             # Shovill + QUAST
│   ├── typing_core.sh          # MLST
│   ├── amr_core.sh             # AMRFinderPlus (organism-aware)
│   ├── species_modules.sh      # Kleborate / ECTyper / SISTR
│   └── summarize.sh            # Consolidated report
├── pipeline/
│   ├── run_bora.sh             # One-command orchestrator
│   ├── setup.sh                # One-time setup + tool checks
│   └── update_dbs.sh           # Download/update local databases
├── data/                       # Place FASTQ files here (gitignored)
├── db/                         # Local databases (gitignored)
├── results/                    # All outputs (gitignored)
└── tests/
    └── tiny_reads/             # Small test dataset for validation
```

---

## Citation

If BORA supports your research or a publication, please cite:

```
Moyo S (2025). BORA: Bacterial Omics for Resource-limited Analysis.
GitHub: https://github.com/sylvestermoyo-z/bora
```

A `CITATION.cff` file is included for GitHub's "Cite this repository" feature.

---

## License

BORA is released under the GNU General Public License v3.0. See [LICENSE](LICENSE) for details.

---

## Author

**Sylvester Moyo**
PhD Candidate | Bloodstream Infection & AMR Genomics | Africa
GitHub: [@sylvestermoyo-z](https://github.com/sylvestermoyo-z)
