# The four-stage pipeline, and why this project is laid out as it is

## Part 1 — What "four-stage" meant

Four separate statistical models, run in sequence, each consuming the previous
one's output.

| Stage | Where | Out |
|---|---|---|
| 1. Abundance | `FIS_MarkRecap_Detection.R` + `FISabundance_...R` | `Est`, `SE` per Stream × Section × Age × Year |
| 2. Population dynamics | JAGS null IPM | posterior draws of `R`, `BAdults`, `la0`, `b`, `sigmaR`, `Surv` |
| 3. Flow emulator | `WorkingFPCA_robust.R` + `01`–`12` | β(t), η |
| 4. Projection | `05_forward_sim.R`, rule curve | 30-year scenarios, K, MS |

The confusion came from stage 3, not from having four stages. Stage 3 tried to
do three things at once: construct a response from a posterior, estimate a
365-point curve from ~40 observations, and combine results across 20,000 draws.
Each needed its own machinery, and the machinery interlocked.

**This project keeps stages 1, 2 and 4 and replaces stage 3.**

## Part 2 — What replaced it

Stage 3 is now three short scripts with one job each:

- `01_build_response.R` — construct `log(R/S)` from the null posterior
- `03_fit_recruitment.R` — fit six coefficients per draw and combine
- `04_validate.R` — decide whether any of it generalises

The 365-point curve is gone, replaced by four pre-registered seasonal windows.
That single change removes the basis choice, the smoothing parameter, the FPC
truncation rule, and the estimator switch — four decisions no reviewer could
check, each of which moved the answer.

Rubin pooling is gone because there is a simpler exact alternative: draw once
from each per-draw sampling distribution and take quantiles. That is a Monte
Carlo integral of the thing you actually want, and it needs no assumption that
the per-draw estimate is unbiased.

**What stayed:** the circularity guard. Because the response comes from the IPM,
the null (flow-naive) fit is load-bearing. If flow covariates were in that
posterior, the analysis partly recovers its own assumption.

## Part 3 — Why a separate project

1. **You can compare.** The old pipeline keeps working, so both answers can sit side by side.
2. **Nothing breaks.** No edits to working code.
3. **Clean history.** A fresh git repository has no record of the old structure to confuse a later reader.

**Data is referenced, not copied.** One line in `config.R`:

```yaml
data_root: "../DroughtTrout/LL/Data"
```

Two copies of a data folder drift apart within a week — you fix something in one
and forget the other.

Put the project **beside** the current one:

```
~/projects/
├── DroughtTrout/          <- current work, untouched
│   └── LL/
│       ├── Data/
│       ├── imputed_output/
│       └── JAGS_PVA/ModelFits/
└── WH_BOR_Trout/          <- this project
```

## Part 4 — What happens to each existing script

| Old file | Fate |
|---|---|
| `FIS_MarkRecap_Detection.R`, `FISabundance_...R` | **Unchanged.** Upstream of everything, feeds the IPM. |
| JAGS null IPM | **Unchanged.** Still the source of the response and of Arm B's demography. |
| `impute_flows.R` | **Unchanged.** Still gap-fills daily discharge. |
| `build_flow_cache.R` | **Replaced** by `R/02_build_flow.R`, which saves the standardization constants. |
| `01_extract_flow_climatology.R` | **Deleted.** It existed only to reverse-engineer the constants the cache discarded. |
| `WorkingFPCA_robust.R` | **Replaced** by `R/01` + `R/03`. Keep the original for the side-by-side. |
| `03_score_flow_signal.R`, `04_ricker_flow_recruitment.R` | **Folded** into `R/05` and Arm B. |
| `05_forward_sim.R` | **Arm B, unchanged.** Now driven by `armB_eta.rds`. |
| `06_build_future_flow_fd.R` | **Replaced** by the scenario scoring in `R/05`. Scenarios need four seasonal means, not smoothed curves. |
| `07`–`09`, `12` | **Replaced** by `R/06_figures.R` and the two `.Rmd` files. |
| `10_penalized_beta.R` | **Deleted.** Duplicated functions already in the engine. |
| `11_curvature_check.R` | **Deleted for now.** Curvature is testable in the new framework by adding a squared term to one window; do that only if the linear model passes the gate first. |
| `RUN_norris_rulecurve_BoR.R` | **Unchanged.** Separate arm, separate question (summer *mean* flow → equilibrium K and MS). |

Nothing is deleted from the old project. It stays exactly as it is until the
comparison tells you which answer to trust.

## Part 5 — Setting it up

1. Create `WH_BOR_Trout/` beside `DroughtTrout/` and copy the files in.
2. Open `WH_BOR_Trout.Rproj` in RStudio.
3. `install.packages(c("tidyverse", "here", "yaml", "lubridate"))`
4. Edit `config.R` — `CFG$paths$data_root`, `posterior_dir`, `flow_dir`, `bor_flow`.
5. `source("R/00_config.R")` — every line must say OK.
6. `bash setup_github.sh WH_BOR_Trout` from the RStudio Terminal.

See `docs/FILE_MAP.md` for the complete manifest and `docs/GITHUB_SETUP.md` for
version control step by step.
