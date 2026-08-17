# WH_BOR_Trout

**Daily-scale streamflow effects on brown trout population processes in regulated
Montana rivers.**

Analysis supporting Bureau of Reclamation flow management and leased-water
conservation decisions. Companion to the mark–recapture abundance estimation and
the JAGS integrated population model, both in the `DroughtTrout` project.

---

## The three research questions

**RQ1 — Where in the year does adding water buy the most trout?**
FPCA-weighted hydrographs give a continuous 365-day curve β(t) for recruitment
and for adult survival, converted into benefit *per cfs released* and swept
through the population model for total production. Deliverable: an optimal
release window with an honest statement of how precisely it can be located.

**RQ2 — What do daily-scale results say about Montana brown trout ecology?**
Which vital rate is flow-limited and when; whether the limiting window is natural
disturbance or anthropogenic depletion; whether timing is cued locally; and
whether the structure recurs across independent populations.

**RQ3 — How do the answers change under forecast future flows?**
BoR scenarios scored on the same standardized axis as the training record, with
extrapolation flagged explicitly.

## Quick start

```r
source("check_setup.R")                             # verify the project loads
source("R/00_config.R")                             # every line must say OK
source("R/explain/explain_beta_and_resolution.R")   # ~1 min, no data needed
source("RUN_ALL.R")                                 # the analysis
source("render_site.R")                             # build the website
```
```bash
bash publish_site.sh                                # publish to GitHub Pages
```

Read `output/tables/gate.csv` before anything else, then
`output/tables/best_day_intervals.csv`.

## The one result to understand before reading any figure

β(t) is the effect of a one-standard-deviation *standardized log anomaly* on day
t. Managers do not release standard deviations — they release cfs. Adding ΔQ on
day t changes the response by

```
Δη(t) = β(t) · log(1 + ΔQ / Q̄(t)) / σ        ≈   β(t) · ΔQ / (σ · Q̄(t))
```

**Benefit per cfs is β(t) divided by that day's baseline discharge.** Ten cfs
added to a 150 cfs September baseflow is a 6.5% proportional change; the same ten
cfs on a 2,000 cfs June peak is 0.5%. Same water, thirteen-fold difference.

So the management curve is *not* β(t), and it can peak on entirely different days.
`docs/PROPOSAL_02_daily_estimand.md` works this through.

## How finely we are allowed to speak

A penalized curve with effective degrees of freedom `edf` over 365 days resolves
roughly `365 / edf` days. At edf ≈ 4 that is about 90 days — so "release on 12
August" is not a statement the data support, even when the fitted curve has its
maximum there.

Script 06 handles this by simulating β(t) from its full covariance and reporting
the **distribution of the best day**. "The optimal window is 5 Aug – 2 Sep with
80% probability" is defensible; a single date is not. When the interval spans most
of the year, the script says so and refuses to name a day.

That limit is itself a result: it bounds how precisely any flow prescription can
be specified from 43 years of observational data, and it motivates the
experimental releases that would resolve it.

## The pipeline

| Script | Does |
|---|---|
| `R/00_config.R` | Reads `config.R`, checks every input exists |
| `R/01_build_response.R` | Null IPM posterior → `log(R/S)` per draw |
| `R/02_build_flow.R` | Daily discharge → standardized curves; **saves** the constants |
| `R/03_fit_beta_recruitment.R` | β(t) for recruitment, per posterior draw |
| `R/04_fit_beta_survival.R` | β(t) for adult survival, per posterior draw |
| `R/05_validate.R` | **The gate.** Blocked CV + permutation null, both models |
| `R/06_daily_sensitivity.R` | **RQ1.** Benefit per cfs per day; release windows |
| `R/07_production_sensitivity.R` | **RQ1.** Day-block sweep through the IPM |
| `R/08_scenarios_bor.R` | **RQ3.** BoR futures |
| `R/09_figures.R` | Figures, `derived_stats.csv`, life-history alignment (**RQ2**) |

Each saves before the next begins, so they can be run one at a time.

## Choosing how β(t) is estimated

`config.R` → `CFG$fitting$estimator` takes `"penalized"` (smoothness prior) or
`"fpc"` (β(t) built from the leading modes of variation in the flow itself — the
old `fpc` option). With `compare_estimators = TRUE` both are fitted and scored on
identical folds.

`penalized` is the default **for the daily deliverable specifically**: FPC
eigenfunctions are global oscillations, so β(t) inherits ripples in months where
nothing happens, and its covariance has rank K, which makes best-day intervals
too narrow. Run `R/explain/explain_estimator_choice.R` to see both effects on
simulated data with a known answer.

**Report the agreement.** Where both estimators put the peak in the same place,
the result does not depend on which prior you chose — better evidence than either
one's confidence interval. Where they disagree, no daily recommendation is
defensible.

## Two models, two jobs

The functional β(t) is the **descriptive and management** layer — it answers RQ1
and RQ2, at whatever resolution the data support.

Four pre-registered seasonal windows are the **confirmatory** layer — 4 degrees of
freedom instead of ~9, so it has real power, and it is the gate. Both are fitted
on identical folds with identical permutation nulls.

If they disagree, the seasonal model wins on inference and β(t) is describing
structure *within* a window that the seasonal test established. Reporting β(t)
alone would be spending precision the record does not have; reporting only the
seasonal model would fail the daily-guidance goal. Both, with the roles stated, is
the honest answer.

## Requirements

```r
install.packages(c("tidyverse", "here", "lubridate", "mgcv", "rmarkdown"))
```

## Reading order for someone new

1. `docs/PROPOSAL_02_daily_estimand.md` — the estimand and the resolution limit
2. `R/explain/explain_beta_and_resolution.R` — run it; no data needed
3. `docs/notes/00_SCRIPT_MAP.md` — plain-language glossary
4. `docs/notes/FILE_MAP.md` — where everything lives

## Conventions

- `output/` and `_site/` are git-ignored; everything in them is regenerable.
- Quote numbers from `output/tables/derived_stats.csv`, never by hand.
- The website renders locally and publishes to `gh-pages`; GitHub cannot render it, because the `.Rmd` files read `output/`, which is not committed.
- Log decisions in `PROJECT_LOG.md`; write `docs/notes/daily/<date>.md` each session.
