# What every script does, in plain language

**Purpose of this document.** You said you don't fully know what several of these
scripts do. That is the blocker for everything else — you can't decide what to
simplify until you can see the shape of the thing. This is the map. No changes are
proposed here; that's a separate document.

Read Part 1 first (the pipeline), then Part 2 (the jargon) when a term stops you.

---

# Part 1 — The pipeline

There are really **three separate pipelines** here that share a folder. Keeping them
straight is most of the battle.

```
PIPELINE 1: How many fish are there?          (2 scripts, outside the IPM)
        │
        ▼   AllBrownTrout_..._PopulationEstimates_wDet_071625.csv
            Stream | Section | Age | Year | Est | SE | LCL | UCL   (fish per km)
        │
        ▼
PIPELINE 2: What are the population dynamics? (JAGS, outside this repo)
        │
        ▼   <SITE>_IndicatorVarSel_NullMod_Apr26_02.rds
            posterior draws of R, NAdults, la0, b, sigmaR, lSurv0, b6S, Surv, ...
        │
        ├──────────────────────────────────┐
        ▼                                  ▼
PIPELINE 3a: Does hydrograph SHAPE    PIPELINE 3b: Does summer MEAN FLOW
   affect recruitment?                    shift equilibrium K and MS?
   (the 16 numbered scripts)              (RUN_norris_rulecurve_BoR.R)
```

Pipelines 3a and 3b answer **different questions** and should never be merged.
3a is about *when* water arrives. 3b is about *how much* water arrives.

---

## Pipeline 1 — Abundance estimation (2 scripts)

These run in a different project and produce the CSV everything else consumes.

### `FISabundance_length_function_wDetection.R`
Defines one function, `calculateAbundance_ages()`. For one section-year-season:

1. Take the recapture run. For each fish, did it carry a mark? (`M.C` = 0/1)
2. Fit three logistic regressions of "was marked" on fish length: intercept-only,
   linear in length, quadratic in length.
3. Model-average them by AICc, keeping models within ΔAICc ≤ 4. The averaged
   prediction is **capture efficiency** `p̂` — the probability a fish present was
   caught.
4. For each age class: `N̂ = (number marked) / p̂`, with a delta-method standard
   error.

This is a Huggins-style closed-population estimator with length-dependent
detection. **The important output for you is that it returns an SE, not just a
point estimate.** That SE is currently thrown away downstream. More on that in the
proposal.

### `FIS_MarkRecap_Detection.R`
Loops the above over every Stream × Section × Year × Season, converts to fish per
km using section length, and writes the CSV. Also picks one season per section
(whichever has more sampling) so you don't mix spring and fall.

---

## Pipeline 2 — The JAGS population model

Not in this repo, but it is the hinge. It takes the abundance CSV and fits an
age-structured model with:

- **Ricker recruitment:** `log R_t = la0 + log(B_{t-3}) − b·B_{t-3} + noise`
  where `B` is adult biomass in grams. `la0` = productivity, `b` = density dependence.
- **Density-dependent survival:** `logit(s_t) = lSurv0 + b6S·(N_all,t−1/100) + noise`
- Three age classes: N2 (recruits), N3, N4+ (plus group).

Two versions exist. The **null** model has no flow covariate — that is the one the
emulator uses. A **flow-informed** version exists for other purposes.

> **Why the null version?** If abundance were estimated using flow, then
> regressing abundance on flow would partly recover the assumption you fed in, not
> a finding. That's what "circularity guard" means everywhere in the code.

---

## Pipeline 3a — The hydrograph-shape analysis (16 scripts)

Run in this order. `RUN_norris.R` is the driver that calls them.

| # | Script | What it does | What breaks if you delete it |
|---|---|---|---|
| — | `00_config_norris.R` | Paths, site name, lags, sim settings. One place to change things. | Everything |
| — | `impute_flows.R` | Fills gaps in the daily USGS discharge record. Runs once, upstream. | No complete flow years |
| — | `build_flow_cache.R` | Turns daily flow into one smooth curve per year. Saves `<SITE>_flow_fd.rds`. **This is where "standardization" happens.** | No hydrographs |
| — | `WorkingFPCA_robust.R` | **The engine.** ~1,000 lines. Loads flow + posterior, builds `log(R/S)` per draw, fits β(t), pools, makes 5-panel figures. | The analysis |
| 01 | `01_extract_flow_climatology.R` | Recovers the exact numbers `build_flow_cache.R` used to standardize, so BoR future flows land on the same scale. Then *proves* it by rebuilding the curves and comparing. | Future flows on the wrong axis |
| 02 | `02_extract_jags_posteriors.R` | Pulls `la0`, `b`, `sigmaR`, `lSurv0`, `b6S`, weights, and the launch state out of the JAGS posterior — indexed so demography draw *i* is the same posterior sample as β draw *i*. | Projection can't run |
| 03 | `03_score_flow_signal.R` | Collapses a whole hydrograph into one number: `η = Σ β(t)·x(t)`. That's the "flow signal" for a year. | No way to score scenarios |
| 04 | `04_ricker_flow_recruitment.R` | Adds `η` into the Ricker. Also adjusts `sigmaR` so flow variance isn't counted twice. | Flow never enters the projection |
| 05 | `05_forward_sim.R` | Projects 30 years forward: survival → age transitions → recruitment, repeat. Uses shared random numbers so scenarios differ only by flow. | No projections |
| 06 | `06_build_future_flow_fd.R` | Same standardization treatment for BoR scenario flows. Gap-fills ≤3 days. | No scenarios |
| 07 | `07_plots_norris.R` | Four figures: flow-signal shift, recruitment multiplier, trajectories, scenario contrasts. | — |
| 08 | `08_diagnostics.R` | Are the scenarios outside the flow range you trained on? Is projected biomass outside the Ricker's fitted range? | You'd extrapolate blind |
| 09 | `09_make_figures.R` | Regenerates every figure and every number quoted in the methods write-up, into `derived_stats.csv`. | Prose and numbers drift apart |
| 10 | `10_penalized_beta.R` | **Duplicate.** Same functions as inside `WorkingFPCA_robust.R`. Reference copy with longer comments. | Nothing |
| 11 | `11_curvature_check.R` | Tests whether recruitment has a *peak* at intermediate flow rather than increasing monotonically. | You'd miss a dome |
| 12 | `12_results_report.R` | Builds `RESULTS.html` and `RESULTS.md` with a scenario dropdown. | — |

**Scripts 10 is redundant** with the engine. That's one you can delete outright.

---

## Pipeline 3b — The rule-curve analysis (1 script)

`RUN_norris_rulecurve_BoR.R`, 718 lines, 10 numbered STEPs. Different question:
if summer mean flow shifts, where does the population settle? It computes:

- **K** (carrying capacity) = where the replacement curve crosses the 1:1 line
- **MS** (maximum surplus) = the biggest gap between production and replacement

for each BoR scenario. Self-contained; doesn't use β(t) at all.

---

# Part 2 — The jargon, in plain English

These are the four terms you flagged. Figures illustrating each are produced by
`R/explain/explain_methods_figures.R` — run it, it needs no data.

---

## "FPCA" — functional principal components analysis

**Plain version:** PCA, but on curves instead of numbers.

Ordinary PCA takes a table of *numbers* and finds combinations that explain the
most variation. FPCA takes a set of *curves* — here, one hydrograph per year — and
finds the shapes that explain the most variation between years.

You get a mean curve, plus a few "modes":
- Mode 1 might be "high everywhere vs. low everywhere" (wet years vs dry years)
- Mode 2 might be "early peak vs late peak" (timing of snowmelt)

Each year then gets a **score** on each mode. 43 curves of 365 points each become
43 rows of maybe 5 numbers. That's the point: compression.

*See Figure 2 in the explain script.*

---

## "β(t)" and the integral — the thing the whole analysis estimates

This is the concept everything else serves, so it's worth ten minutes.

An ordinary regression has one slope per predictor:
`y = a + b₁x₁ + b₂x₂`

A **functional** regression has a slope for *every day of the year*:

```
log(R/S)  =  intercept  +  Σ  β(t) · x(t)     summed over t = day 1 … 365
                          t
```

`β(t)` is a curve. Where β is positive, high flow *that day* is associated with
better recruitment. Where β is negative, high flow that day is associated with
worse recruitment. The sum `η = Σ β(t)·x(t)` collapses a whole 365-day hydrograph
into a single number for that year.

**This is the number BoR cares about.** Every scenario comparison is ultimately
"what is η under scenario X vs historically?"

*See Figure 3 — it shows β(t), one year's hydrograph, their product, and the
shaded area that becomes η. If one figure makes this click, it's that one.*

---

## "penalized" vs "fpc" — two ways to estimate β(t)

You have 43 years of data and want to estimate a curve with 365 values. That's
impossible without a constraint. The two options are two different constraints.

**`estimator = "fpc"`**
1. Run FPCA on the hydrographs, keep the top ~8 modes.
2. Regress `log(R/S)` on those 8 scores by ordinary least squares.
3. Convert the 8 coefficients back into a β(t) curve.

Constraint: *β(t) must be a combination of the shapes flow actually varies in.*

**`estimator = "penalized"`**
1. Represent β(t) as a flexible spline.
2. Fit it, but add a penalty for wiggliness.

Constraint: *β(t) must be smooth.*

**Why they disagree at your site.** FPCA keeps modes by how much **flow** varies in
them. But you're testing them against **recruitment**. Those are different criteria
— a mode with little flow variance could still be the one that matters for fish, and
truncation throws it away. Meanwhile the roughness penalty assumes the signal is
smooth, and if your signal lives in short sharp features it gets flattened. Your
notes record exactly this: penalized gave `edf ≈ 4` and a flat, uninformative curve.

Neither is "right." **They are two different assumptions about what β(t) looks
like**, and at n = 43 the assumption does most of the work.

*See Figures 4 and 5.*

---

## "sp" and "sp_mode" — how hard to smooth

`sp` is the **smoothing parameter**: the dial controlling how much the wiggliness
penalty bites.

- `sp` small → β(t) wiggly, chases noise
- `sp` large → β(t) nearly a straight line, misses real structure

`mgcv` picks it automatically by REML.

`sp_mode` controls *how often* it's picked:
- `"fixed"` — pick it once on the average response, reuse for all 20,000 draws. Fast, and the thing being estimated stays the same across draws.
- `"per_draw"` — re-pick it for every draw. Slower, and β(t) means a slightly different thing in each draw.

*See Figure 5 — same data, three values of `sp`.*

---

## "Rubin pooling"

**The problem it solves.** You don't have one `log(R/S)` series. You have 20,000 —
one per posterior draw of abundance. So you get 20,000 different β(t) curves. How
do you report one?

Two kinds of uncertainty are in play:
1. **Within-draw:** given *this* abundance series, how precisely is β(t) estimated?
2. **Between-draw:** how much does β(t) move as abundance uncertainty moves?

Rubin's rules combine them: `Total = Within + (1 + 1/M) × Between`.

**Why it's here:** it's borrowed from *multiple imputation* — the standard method
for missing data, where you fill gaps M times and combine. Your situation looks
similar (M versions of the data) so it was applied by analogy.

**Why the analogy is imperfect:** Rubin's formula assumes each individual estimate
is unbiased. A penalized spline is deliberately biased toward smoothness. Hence the
paragraphs of caveats in the code.

**The simpler equivalent:** take one random draw from each within-draw
distribution, pool all of them, take quantiles. Same answer, no assumption, one
line of code. That's what `propagate_draws()` does.

*See Figure 6.*

---

## "run_cv" — cross-validation, the honesty check

With ~9 free parameters and 43 data points, a model will fit the data well
*whether or not there's a real signal*. R² measured on the same data that trained
the model is not evidence.

Cross-validation: hold out some years, fit on the rest, predict the held-out ones,
measure error. **Negative cross-validated R² means the model predicts worse than
just using the average.**

**Leave-one-out (LOO)** holds out one year at a time. The catch: flow is
autocorrelated, so a held-out year looks a lot like its neighbours — which are
still in the training set. The model interpolates and looks better than it is.

**Blocked CV** holds out 5-year runs instead. Harder, and honest.

*See Figures 7 and 8.*

---

## "permutation null"

Even blocked cross-validated R² can be positive by luck. The permutation test asks:
if I break the link between flow and recruitment but keep everything else, how
often do I get a result this good anyway?

The naive version shuffles the response randomly — but that destroys
autocorrelation and makes the null too easy to beat. The right version **circularly
shifts** the response against flow: slide the recruitment series forward by k years
and wrap around. Both series keep their own structure; only their alignment breaks.

With 43 years there are only 42 shifts, so the smallest possible p-value is about
1/43 ≈ 0.023. That's a limit of the data, not the code.

*See Figure 8.*

---

# References

Written for people in your position, not for statisticians.

| Topic | Source |
|---|---|
| Functional data analysis, gentlest entry | Ramsay, Hooker & Graves (2009) *Functional Data Analysis with R and MATLAB*, Ch. 1–3 & 9 |
| GAMs and smoothing parameters | Wood (2017) *Generalized Additive Models: An Introduction with R*, 2nd ed., Ch. 4 & 5 |
| Scalar-on-function regression | Reiss et al. (2017) "Methods for scalar-on-function regression", *Int. Stat. Rev.* 85:228–249 |
| Blocked CV for ecological data | Roberts et al. (2017) "Cross-validation strategies for data with temporal, spatial, hierarchical, or phylogenetic structure", *Ecography* 40:913–929 |
| Measurement error in stock–recruit | Walters & Ludwig (1981) *Can. J. Fish. Aquat. Sci.* 38:704–710 |
| Hierarchical stock–recruit across stocks | Su, Peterman & Haeseker (2004) *Can. J. Fish. Aquat. Sci.* 61:2471–2486 |
