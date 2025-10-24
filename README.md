# HEAD — HSAF Engines for Analyzing Datasets

**HEAD** (H SAF Engines and Analysis Data) is an algorithmic framework developed at **CIMA Research Foundation** to support decision‑makers in operational hydrological monitoring, flood forecasting, and risk assessment. It provides processing chains designed to exploit **satellite‑based hydrological data** from the **EUMETSAT H SAF (Hydrology Satellite Application Facility)**.

---

## Overview

HEAD has been used operationally since 2014 by Functional Centers (e.g., Valle d’Aosta and Marche) to support hydro‑meteorological warning systems and flood‑risk management for civil‑protection purposes.

The repository includes Python modules, analytical workflows, and supporting shell scripts, distributed under the **EUPL‑1.2** license.

---

## Data Sources (H SAF)

HEAD integrates **satellite‑derived hydrological datasets** provided by the  
**EUMETSAT Hydrology Satellite Application Facility (H SAF)** — <https://hsaf.meteoam.it/>.

H SAF data are freely available (with attribution to EUMETSAT) and cover the key hydrological variables used by HEAD:

| Variable           | Description                                       | H SAF Product Families               |
|--------------------|---------------------------------------------------|-------------------------------------|
| **Precipitation**   | Instantaneous, accumulated, and blended rainfall estimates from GEO/LEO sensors | H01–H19                             |
| **Soil Moisture (SM)** | Surface and root‑zone soil moisture from active/passive microwave sensors | H14–H27                             |
| **Snow**            | Snow cover extent, snow water equivalent (SWE), and melting/condition status | H10–H31                             |

HEAD workflows retrieve, preprocess, and analyse these datasets to support hydrological‑model inputs, validation, and event‑based assessments.

The **list of H SAF products** currently supported by HEAD (including filenames, retrieval workflows, and variable mapping) is defined in the [`apps/`](https://github.com/c‑hydro/head/tree/main/apps) directory of this repository.

> **Note:** Users must ensure that access credentials and download endpoints for H SAF data (FTP or EUMETSAT Data Centre) are properly configured before running ingestion pipelines.

---

## Repository Structure

- `apps/` – Application modules defining processing chains for H SAF products  
- `bin/` – Shell utilities (e.g., environment‑setup scripts)  
- `example/` – Sample configuration files and test data  
- `tools/` – General‑purpose utilities and helper functions  

---

## Prerequisites

HEAD is designed for **Linux (Debian/Ubuntu 64‑bit)** environments.

**Core dependencies**:  
- Python 3.x (via Conda/Miniconda)  
- Optional: QGIS ≥ 2.18, R ≥ 3.4.4 (for GIS/statistics components)  

**Recommended tools**:  
Jupyter Notebook, Panoply, CDO (Climate Data Operators), ncview.

---

## Installation

To set up the HEAD environment:

```bash
bash setup_head_system_conda_python_runner.sh
```

This script installs a Miniconda‑based environment and creates the `fp_env_python` Python environment under `$HOME/fp_libs_python/`.

Activate it with:

```bash
export PATH="$HOME/fp_libs_python/bin:$PATH"
source activate fp_env_python
```

> Adjust the paths/variables inside the script if your deployment layout differs from default.

---

## Usage

> **Note:** Usage examples are restricted to `.sh` scripts included in this repository.

### Environment Bootstrapper

```bash
bash setup_head_system_conda_python_runner.sh
```

This initializes the Python environment required to run the HEAD applications.

---

## Data Access & Download

H SAF data can be obtained through:

- **EUMETSAT Data Centre** (https://eoportal.eumetsat.int/)  
- **H SAF FTP Services** (via https://hsaf.meteoam.it/)  
- **Archived requests** for historical datasets via the H SAF portal  

Each product includes metadata (resolution, coverage, variable definitions) and validation reports under the “Quality Assessment” section of the H SAF portal.  
HEAD modules include ingestion utilities capable of automatically fetching and updating H SAF datasets once proper credentials and configuration files are set.

---

## Target Users

HEAD (as part of the Flood‑PROOFS modelling ecosystem) supports:

- **Data users** — analysing precomputed or near‑real‑time products  
- **Case‑study users** — evaluating selected hydrological events  
- **Applying users** — executing workflows with local or scenario data  
- **Contributors** — extending algorithms or integrating new datasets  

---

## Contributing

Contributions are welcome! Please:

1. Fork the repository  
2. Create a feature branch from `main`  
3. Add your changes (with tests where applicable)  
4. Open a pull request to `main` describing your change

For bugs or feature requests, open an issue in the repository.

---

## Authors

Developed and maintained by **CIMA Research Foundation**.  
See [`AUTHORS.rst`](AUTHORS.rst) for the full list of contributors.

---

## License

This project is distributed under the **European Union Public License v1.2 (EUPL‑1.2)**.  
See [`LICENSE.rst`](LICENSE.rst) for full terms and conditions.

---

## References

- [H SAF — Hydrology Satellite Application Facility](https://hsaf.meteoam.it/)  
- [EUMETSAT Data Centre](https://eoportal.eumetsat.int/)  
- [CIMA Research Foundation](https://www.cimafoundation.org/)  
- HEAD repository (GitHub) & its [`apps/`](https://github.com/c‑hydro/head/tree/main/apps) directory for supported product list  
