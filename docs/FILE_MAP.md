# File map — every file, and which folder it goes in

Complete manifest. Anything not listed here is not part of the pipeline.

---

## Folder structure

```
WH_BOR_Trout/                    <- put this BESIDE DroughtTrout/, not inside it
├── R/                           the numbered pipeline, run in order
│   └── explain/                 teaching scripts — run these, they need no data
├── docs/                        project documentation
│   └── notes/                   reference material, reviews, decisions
│       └── daily/               one file per working session
├── manuscript/                  .Rmd sources for the website
├── .github/workflows/           GitHub Actions
└── output/                      created automatically, git-ignored
    ├── models/   tables/   figures/
```

---

## Project root — 9 files

| File | Purpose |
|---|---|
| `WH_BOR_Trout.Rproj` | RStudio project. Open this to start. |
| **`config_local.R`** | **YOUR settings — site registry, per-site flow lags, analysis choices.** Sourced last by `config.R`, so anything here wins. Never overwritten by an update. **Edit this.** |
| `config.R` | Analysis defaults and path templates. Gets replaced when the method develops, so do not put project-specific settings here. |
| `check_setup.R` | Verifies the project can run, before you run it. ~1 second, needs no data. |
| `RUN_ALL.R` | Runs scripts 01–09 in order. |
| `render_site.R` | Builds `_site/` from `manuscript/*.Rmd`. |
| `publish_site.sh` | Pushes `_site/` to the `gh-pages` branch. |
| `setup_github.sh` | One-time version-control setup. |
| `README.md` | What this is; the three research questions. |
| `PROJECT_LOG.md` | Running record of decisions. Append each session. |
| `.gitignore` | Excludes data, `output/`, `_site/`. |

---

## `R/` — 11 pipeline files

Run in order. Each saves before the next begins, so they can be run one at a time.

| File | Does | Writes |
|---|---|---|
| `00_config.R` | Sources `config.R`, derives shorthands, checks every input | — |
| `fn_fit_beta.R` | The custom fitting functions: `fit_beta_curve()` (penalized + fpc), `fit_seasonal()`, `simulate_beta()` | — |
| `01_build_response.R` | Null IPM posterior → `log(R/S)` per draw | `response.rds` |
| `02_build_flow.R` | Daily discharge → standardized curves + **saved** constants | `flow.rds` |
| `03_fit_beta_recruitment.R` | β(t) for recruitment, per posterior draw | `beta_recruitment.rds` |
| `04_fit_beta_survival.R` | β(t) for adult survival, per posterior draw | `beta_survival.rds` |
| `05_validate.R` | **The gate.** Blocked CV + permutation null, both estimators | `gate.rds` |
| `06_daily_sensitivity.R` | **RQ1.** Benefit per cfs per day; best-day intervals | `sensitivity.rds` |
| `06b_decision_window.R` | **RQ1.** The same, restricted to the allocation season | `decision_window.rds` |
| `07_production_sensitivity.R` | **RQ1.** Day-block sweep through the IPM | `production.rds` |
| `08_scenarios_bor.R` | **RQ3.** BoR futures on the training axis | `scenarios.rds` |
| `09_figures.R` | Presentation figures, `derived_stats.csv`, life-history alignment (**RQ2**) | figures + tables |
| `10_rulecurve.R` | **Separate arm.** Equilibrium K and MS under BoR *summer mean* flows. Reads the FLOW-INFORMED IPM and its own standardization. Not in `RUN_ALL.R` | `rulecurve.rds` |

**Optional diagnostic** — run only if you use `estimator = "fpc"`:

| File | Does |
|---|---|
| `diag_fpc_truncation.R` | Discarded-component test, K sweep, cross-site basis alignment. See `docs/notes/FPC_reviewer_critiques.md`. |

---

## `R/explain/` — 4 teaching scripts

**None needs data.** Run them to understand the method before trusting a result.

| File | Shows |
|---|---|
| `explain_beta_and_resolution.R` | **Start here.** What β(t) is, why the management curve differs from it, what resolution 43 years supports. |
| `explain_estimator_choice.R` | Penalized vs fpc on simulated data with a known answer. |
| `explain_methods_figures.R` | The general framework: FPCA, pooling, cross-validation, permutation nulls. |
| `explain_partial_pooling.R` | Hierarchical shrinkage across sites. |

---

## `manuscript/` — 6 files

| File | Purpose |
|---|---|
| `_site.yml` | Website navigation and theme. |
| `_common.R` | Shared setup. Sources `config.R`; every number read from `output/`. |
| `index.Rmd` | Landing page: the three questions and the answers. |
| `methods.Rmd` | Methods, PNAS structure. |
| `_site_template.Rmd` | **RQ1 + RQ3** — the per-site results body. Leading `_` keeps it from rendering as a page; each generated `site_<name>.Rmd` includes it as a child with `SITE_FOCUS` set. **Edit results content here.** |
| `site_<name>.Rmd`, `results.Rmd` | **Generated** by `render_site.R`, one wrapper per active site plus the hub. Git-ignored build products — never edit them. |
| `results_among_sites.Rmd` | **RQ2.** Population-ecology synthesis across sites. |

---

## `docs/` — 10 files

| File | Purpose |
|---|---|
| `WORKFLOW.md` | **Start here.** What to run, in what order, what to check. |
| `PROPOSAL_02_daily_estimand.md` | **Read before the code.** Why β(t) is not the curve a water manager needs. |
| `GITHUB_PAGES.md` | Publishing the website, step by step. |
| `notes/FILE_MAP.md` | This file. |
| `notes/00_SCRIPT_MAP.md` | Plain-language glossary: FPCA, β(t), sp, cross-validation, permutation nulls. |
| `notes/PROJECT_STRUCTURE.md` | Why the layout is what it is; what happened to each old script. |
| `notes/FPC_reviewer_critiques.md` | Eight anticipated reviewer objections to an FPC-only analysis. |
| `notes/GITHUB_SETUP.md` | Git for a beginner. |
| `notes/REVIEW_and_PATCHES.md` | Defect ledger from the original pipeline. |
| `notes/PROPOSAL_01_direct_measurement_error.md` | Record of the option not taken (mark–recapture instead of IPM). |
| `notes/daily/2026-07-29.md` | Session summaries + continuation prompts. |

---

## `.github/workflows/` — 1 file

`deploy-site.yml` — serves the `gh-pages` branch. **It does not render**: the
`.Rmd` files read `output/`, which is git-ignored and never reaches GitHub.
Rendering is local by necessity, not preference.

---

## Object flow between scripts

```
config.R ──► 00_config.R ──► every script
                 │
     ┌───────────┴────────────┐
     ▼                        ▼
01_build_response      02_build_flow
  response.rds            flow.rds
     │                        │
     └───────────┬────────────┘
        ┌────────┴────────┐
        ▼                 ▼
03_fit_beta_        04_fit_beta_
  recruitment          survival
beta_recruitment.rds  beta_survival.rds
        │                 │
        └────────┬────────┘
                 ▼
           05_validate  ──► gate.rds     ◄── THE GATE
                 │
     ┌───────────┼───────────┬──────────────┐
     ▼           ▼           ▼              ▼
06_daily     06b_decision  07_production  08_scenarios
sensitivity  window        sensitivity    bor
     └───────────┴───────────┴──────────────┘
                 ▼
           09_figures ──► derived_stats.csv, figures/
                 ▼
           render_site.R ──► _site/ ──► publish_site.sh ──► gh-pages
```

---

## First run

```r
# 1. edit config.R -- CFG$paths, and params_path() if a site's CSV differs
source("check_setup.R")     # ~1 second; fix anything it flags
source("R/explain/explain_beta_and_resolution.R")   # understand the estimand
source("RUN_ALL.R")
```

Then read `output/tables/gate.csv`.

**After editing `config.R` or `R/00_config.R`, restart R** (*Session → Restart R*)
before re-sourcing. `source()` does not clear previous definitions, so a stale
copy can linger and produce confusing "could not find function" errors.

---

## Four things to verify before quoting a number

1. **The posterior is the NULL (flow-naive) fit.** No script can check this.
2. **Years are read, not assumed.** `check_setup.R` reports the range per site. A site falling back to `first_year` warns loudly — do not ignore it.
3. **The flow lag per site.** `flow_year(recruit_year, site) = recruit_year − flow_lag(site)`, where `flow_lag()` in `config.R` carries the IPM's own indicator-variable selection (Norris 3, BigHole.Melrose 2). A wrong lag shifts the entire hydrograph by a year and is invisible in the output — script 01 prints the calendar year used per site so it can be checked by eye.
4. **The life-history timeline in `R/09_figures.R`** — must come from the literature and be fixed *before* looking at β(t).

---

## Adding a site

Add the name to `CFG$sites$active` in `config.R`. If its files follow the usual
convention, nothing else is needed. If not, add a `switch()` branch to
`params_path()` or an `if()` to `params_filter()` — both are in `config.R`, and
both are plain R.
