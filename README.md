# Uncovering the Burden Shifting of Data Center Cooling

**System-level water-energy-carbon optimization for urban infrastructure**

> Parth Brahmbhatt, Mohammad Hemmati, Javiera Vergara-Zambrano, Vassilis M. Charitopoulos, Styliani Avraamidou
>
> Preprint: [SSRN 6722099](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=6722099)

---

## Overview

This repository contains the Julia/JuMP optimization model from the paper. The model is a multi-scale Mixed-Integer Linear Program (MILP) for urban capacity expansion planning that integrates data center (DC) cooling strategies into the water-energy-carbon nexus.

**Key question:** Does choosing air-chiller cooling (zero on-site water) really reduce total resource burden, or does it shift the burden upstream to the regional electricity grid?

**Two DC cooling architectures studied:**
- **Case 1** — ASE + Evaporative Cooling: lower electricity use, higher direct water consumption
- **Case 6** — ASE + Air Chillers: higher electricity use, near-zero direct water consumption

**Key finding:** Optimizing exclusively for zero on-site water shifts the resource burden upstream — demanding substantially more low-carbon generation, energy storage, and total infrastructure investment.

---

## Requirements

- [Julia](https://julialang.org/) ≥ 1.9
- [Gurobi](https://www.gurobi.com/) optimizer with valid license
- Julia packages: `JuMP`, `Gurobi`, `XLSX`, `DataFrames`, `JLD2`, `FileIO`, `PyPlot`

Install packages:
```julia
using Pkg
Pkg.add(["JuMP", "XLSX", "DataFrames", "JLD2", "FileIO", "PyPlot"])
Pkg.add(PackageSpec(name="Gurobi", version="1.3"))
```

---

## Repository Structure

```
dc-water-energy-carbon-optimization/
├── src/                         # Shared model source (one copy, used by all cases)
│   ├── utils.jl                 # Data loading, ModelData/TechData structs
│   ├── variables.jl             # JuMP decision variable definitions
│   ├── constraints.jl           # All optimization constraints
│   ├── objective.jl             # Objective function (minimize total NPV cost)
│   ├── run_model.jl             # Model build + solve wrapper
│   ├── results.jl               # Results export (Excel + JLD2 + plots)
│   └── plot_from_excel.jl       # Post-hoc plotting from saved Excel results
│
├── cases/
│   ├── Baseline/                # Cases 1 & 6 without emission constraint
│   ├── Emission_Cost_Pareto_Case_1/   # Pareto sweep: cost vs GHG, evaporative cooling
│   ├── Emission_Cost_Pareto_Case_6/   # Pareto sweep: cost vs GHG, air chillers
│   ├── Emission_Cost_Pareto_No_DC/    # Pareto sweep: no data center (reference)
│   ├── DC_Size_Case_1/          # DC capacity sensitivity (100–500 MW), Case 1
│   └── DC_Size_Case_6/          # DC capacity sensitivity (100–500 MW), Case 6
│       Each case folder contains:
│           run_case.jl          ← entry point to run this case
│           Model_Data.xlsx      ← all model parameters for this case
│           plot.ipynb           ← results visualization notebook
│
├── data/
│   └── pue_wue/                 # Python simulation code for hourly PUE/WUE profiles
│       ├── simulation_funs_DC.py
│       ├── demo.ipynb
│       ├── PUE_WUE_monthly.ipynb
│       ├── Hourly_PUE_WUE_Results.xlsx
│       └── PUE_WUE_Madison_Results.xlsx
│
└── visualization/
    └── hourly_comparison_plots.ipynb  # Weekly seasonal profiles across cases
```

---

## How to Run

### 1. Single baseline run

```bash
cd cases/Baseline
julia run_case.jl
```

Set `DC_Cooling_Type` in `Model_Data.xlsx > Model_Data` sheet:
- `0` → Case 1 (evaporative cooling)
- `1` → Case 6 (air chillers)

### 2. Pareto sweep (emission-cost trade-off)

Each Pareto point is a separate model run with a different emission target (`E_target` in `Model_Data.xlsx`). Run for multiple target levels (e.g., 100%, 90%, 80%, 70%, 65%, 50% of baseline emissions):

```bash
cd cases/Emission_Cost_Pareto_Case_1
# Set E_target_pct in Model_Data.xlsx, then:
julia run_case.jl
```

Repeat for each target percentage to build the full Pareto front.

### 3. DC size sensitivity

Vary `DC_Cap` (MW) in `Model_Data.xlsx`, then:

```bash
cd cases/DC_Size_Case_1
julia run_case.jl
```

---

## Model Data

`Model_Data.xlsx` in each case folder contains all model parameters:

| Sheet | Contents |
|-------|----------|
| `Model_Data` | Global scalars (years, discount rate, DC parameters) |
| `Tech_Data` | Technology costs, lifetimes, water factors |
| `EoL_Data` | End-of-life options and costs |
| `Sets` | Technology and fuel set definitions |
| `Annual_costs` | Fuel and grid cost projections |
| `Annual_emi` | Grid emission and water intensity projections |
| `HL` | Hourly solar capacity factor profiles |
| `WP` | Hourly wind power profiles |
| `DC_Profile_MV` | Normalized hourly DC server load profile |
| `WUE_PUE_hourly` | Hourly PUE and WUE profiles for Cases 1 & 6 |

> **Note:** Hourly electricity, heating, and cooling demand profiles are not included in this repository. The demand data can be provided upon request or regenerated from publicly available weather and building energy data for the Madison, WI study area.

---

## PUE/WUE Simulation

The hourly Power Usage Effectiveness (PUE) and Water Usage Effectiveness (WUE) profiles in `WUE_PUE_hourly` were generated using the thermodynamic simulation code in `data/pue_wue/`. See `data/pue_wue/README.md` and `data/pue_wue/demo.ipynb` for details.

---

## Citation

If you use this code, please cite:

```
Brahmbhatt, P., Hemmati, M., Vergara-Zambrano, J., Charitopoulos, V.M., & Avraamidou, S. (2025).
Uncovering the burden shifting of data center cooling: System-level water-energy-carbon optimization
for urban infrastructure. SSRN Working Paper 6722099.
https://papers.ssrn.com/sol3/papers.cfm?abstract_id=6722099
```

---

## License

Code released under MIT License. See `LICENSE` for details.
