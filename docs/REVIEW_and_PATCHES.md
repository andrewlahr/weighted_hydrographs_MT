# Code review: Norris flow–recruitment pipeline

Reviewed 18 files, ~4,950 lines. Findings are ordered by **consequence**, not by file.
Each entry gives the exact location, why it matters, and the fix.

A note on method before the findings. You asked for all 18 scripts cleaned and
optimised in one pass. I have not done that, deliberately — it violates your own
attribution rule. A simultaneous rewrite of the fit engine, the projection, the
figures and the report makes it impossible to tell which change moved a number.
What follows instead is a bug ledger with surgical patches, three new modules that
are additive rather than destructive, and a staged order at the end.

---

## Tier 1 — findings that change published numbers

### T1.1 The β(t) credible band is labelled 95% but is an 80% band

`WorkingFPCA_robust.R`, `pool_rubin()`:

```r
tcrit  <- qt(0.9,  df)    # -> 80% interval, not 95%
tcrit2 <- qt(0.75, df)    # -> 50% interval
```

`lo`/`hi` are then plotted in `make_site_figures()` under the subtitle
`"Band = Rubin-pooled 95% ..."`, and `run_site()`'s comment on
`select_after_pool()` also says 95%. Every β(t) figure produced so far understates
the width of the interval by roughly 40%. This is the single most reviewer-visible
error in the codebase and it must be fixed before any figure leaves the building.

**Fix.** Stop hand-rolling critical values. `R/15_pooling_and_cv.R::propagate_draws()`
returns explicitly named quantiles (`q025`, `q100`, `q250`, `q500`, `q750`, `q900`,
`q975`) so the plotting layer cannot mislabel them.

### T1.2 `build_flow_cache.R` never writes the cache

Lines at the bottom of the driver:

```r
for (S in LL_Sections) {
  res <- build_site_flow_fd(S)
  # res <- tryCatch(build_site_flow_fd(SS), ...)
  # if (!is.null(res)) { save_site_flow(SS, res); built <- c(built, SS) }
}
cat(sprintf("\nDone. Cached %d sites", length(built)))
```

`save_site_flow()` is commented out. `built` never leaves `character(0)`, so the
script always reports "Cached 0 sites" and every fd it builds is discarded. The
loop variable is `S`; the commented code refers to `SS`. Whatever is in
`data/flow_fd/` is left over from an earlier run and has not been rebuilt since
this comment-out happened.

Two consequences. First, `RUN_norris.R` sources this file at line 4, so the entire
(broken) 25-site build runs on every pipeline invocation for no benefit — that is
most of your startup time. Second, your STEP 2 round-trip check passes trivially
whenever `build_site_flow_fd` is in scope, because `.reference_fd()` prefers the
live builder over the stored `.rds`; it is verifying the builder against itself,
not the builder against the cache the fit actually consumed.

**Fix.** Uncomment the save, rename the loop variable, wrap the driver in
`if (sys.nframe() == 0)` or move it to a `main_build_cache()` function so
`source()` has no side effects. Then re-run the cache and re-run STEP 2 with
`.reference_fd()` forced to the stored `.rds`.

### T1.3 `residual_sigmaR()` subtracts overfit variance, narrowing every projection interval

`04_ricker_flow_recruitment.R`:

```r
vflow <- apply(eta_centered_train_draws, 1, stats::var)
s2 <- sigmaR_null^2 - vflow
```

`Var(η̂)` is the variance of *fitted* values from a model with ~9 free parameters
on 43 annual points. It is inflated by exactly the amount the LOO gate says is
not real. You are removing apparent, not actual, explained variance from the
process SD, so `sigmaR_flow` is biased low and every projection ribbon is too
narrow. At `cv_R² ≈ 0` the honest subtraction is approximately zero, and yet the
code subtracts the full in-sample variance.

**Fix.** Shrink by out-of-sample skill:

```r
v_real <- max(0, cv_r2) * var_train_y      # variance the model actually explains
s2     <- sigmaR_null^2 - v_real
```

`R/15_pooling_and_cv.R::shrunk_explained_var()` implements this. It reduces to the
current behaviour when `cv_R² = 1` and to "no correction" when the gate fails,
which is the correct limiting behaviour in both directions.

### T1.4 The CV gate does not evaluate the model you fit

`cv_compare()` calls `fit_penalized_beta(ytr, Xtr, grid, k = k)` with `sp = NULL`,
so the smoothing parameter is re-estimated by REML inside every fold. The
production fit uses `sp_fixed`, estimated once on the posterior-mean response.
The gate and the fit are therefore different estimators, and the gate is the more
flexible of the two — it will generally look worse than the model you actually
ship, which happens to be conservative here, but it is not an answer to the
question you asked.

Second issue: LOO on a series with autocorrelated flow is optimistic. Your blocked
CV already collapsed the result; that collapse is the real number.

**Fix.** `R/15_pooling_and_cv.R::blocked_cv_functional()` takes `sp_fixed`,
re-estimates it *within* each training block when you ask it to (so you can
measure the leak), and defaults to contiguous blocks of `block_len` years. Report
blocked CV as the headline and LOO only as a footnote.

### T1.5 `FLOW_LAG` is read from the global config in the projection but from the fit in the fit

`run_site()` sets `flow_lag <- post$lag`. `05_forward_sim.R` uses the *global*
`FLOW_LAG` from `00_config_norris.R`. These are computed by the same function today,
so they agree — until someone edits the config, or the
`_RecLagInclusionProbQuad.csv` changes, at which point the projection silently
applies a different lag than the one β(t) was estimated under. That is the same
class of silent failure as the `<<-` bug you already removed from FishCast.

**Fix.** In `forward_sim()`, take the lags from the fit object and assert:

```r
rec_lag  <- f$summary$rec_lag
flow_lag <- f$summary$flow_lag
stopifnot(identical(as.integer(rec_lag),  as.integer(REC_LAG)),
          identical(as.integer(flow_lag), as.integer(FLOW_LAG)))
```

Related and still outstanding: `03_score_flow_signal.R`'s header says
`flow_lag (=2)` and `05_forward_sim.R` calls the lagged column the "rearing-year
flow column". If the fit ran at 3, both comments are wrong and describe a
different biological mechanism than the one estimated. Fix the comments in the
same commit as the assertion, or the next reader inherits the confusion.

---

## Tier 2 — statistical structure

### T2.1 Rubin pooling is the wrong tool for posterior draws

Rubin's rules combine estimates across *multiple imputations of missing data*,
under the assumption that each within-imputation estimate is approximately
unbiased and that the imputations are draws from a proper posterior predictive.
Your `M` are posterior draws of the response, and your within-draw estimator is
deliberately biased toward smoothness. You have documented this caveat honestly
three times in comments. The cleaner move is to stop needing the caveat.

What you actually want is the posterior of β(t) given the data, marginalising over
abundance uncertainty. That is obtained by one draw from each within-draw sampling
distribution and then taking empirical quantiles:

```r
beta_star[m, ] <- beta_hat[m, ] + sqrt(var[m, ]) * rnorm(G)
# pooled interval = quantiles of beta_star
```

No `(1 + 1/M)` correction, no Barnard–Rubin degrees of freedom, no unbiasedness
assumption, no mislabelled critical values, and it is one line shorter.
`propagate_draws()` in `R/15_pooling_and_cv.R`. Both are returned side by side the
first time you run it so you can confirm the intervals agree to within Monte Carlo
error before you switch.

### T2.2 `select_after_pool()` runs a t-test where a probability belongs

```r
z <- qbar / sqrt(pmax(Tt, eps))
which(abs(z) > qt(0.975, M - 1))
```

With `within_var = NULL`, `W = 0` and `Tt = (1 + 1/M)B`, so this is the posterior
mean divided by the posterior SD — compared against a t quantile with 19,999
degrees of freedom, i.e. 1.96. It is a normal-approximation posterior probability
statement wearing a frequentist costume. Report the thing itself:

```r
p_dir <- pmax(colMeans(bfpc_m > 0), colMeans(bfpc_m < 0))
```

"FPC3 is positive in 91% of draws" is what you can defend and what a BoR audience
can read. `prob_direction()` in the new module.

### T2.3 Drop `S_z` from the inferential model entirely

You already flag it as non-independent, and it binds in ~0.1% of draws. But there
is a harder argument you have not written down: because `flow_lag == rec_lag == 3`
at Norris, the spawner series and the hydrograph reference the *same calendar
year*. `S_z` and the FPC scores are then two summaries of one year's conditions,
and any shared variance is arbitrarily apportioned between them. Keeping the term
buys nothing and costs a degree of freedom plus a constrained optimiser. Report it
once as a sensitivity and remove it from the main path — which the penalized arm
has already done.

### T2.4 A simpler estimator you should fit before defending the functional one

The functional model spends 3–9 effective df to estimate a curve you then
summarise as "positive here, negative there". At 43 annual points that is a poor
trade, and the FPC arm's advantage traced to interpolation bias when you blocked
the CV.

Fit four pre-registered seasonal means of the standardized anomaly on a
**water-year** axis — fall spawning, overwinter incubation, spring runoff, summer
base flow — and regress `log(R/S)` on those four scalars. Four parameters, no
basis choice, no truncation, no smoothing parameter, and β(t) becomes a step
function any BoR reader can act on ("a one-SD reduction in summer base flow costs
X% of recruitment"). Run it through the same blocked CV and the same permutation
null, head to head against the functional fit.

If the functional model cannot beat four seasonal means out of sample, publish the
seasonal means. That is not a retreat; it is the correct model given `n = 43`.
`R/14_seasonal_baseline.R` implements it, including the water-year axis you flagged
as the biologically correct one.

### T2.5 Two transient definitions disagree

`07_plots_norris.R::ribbon_df()` drops `pyear <= burnin` with
`burnin = max(REC_LAG, FLOW_LAG) = 3`. `08_diagnostics.R::.stationary_cols()` uses
`burn_in + transient(7) + 1 = 11`. The figures therefore show years the diagnostics
consider non-stationary. With a plus group launched from a single year's state, the
age structure takes well over 3 years to relax; 11 is closer to right and 15 would
be safer. Put one constant in `00_config_norris.R` (`SIM$burn_in_years`) and have
both read it.

---

## Tier 3 — hygiene that prevents the next silent failure

| # | Location | Problem | Fix |
|---|---|---|---|
| 3.1 | `build_flow_cache.R` vs `WorkingFPCA_robust.R` | Two different `save_site_flow()` signatures: `(SS, obj, dir)` vs `(SS, flow_fd, years, dir)`. `RUN_norris.R` sources the second first, so the first wins. A call in the old style silently passes `years` as `dir`. | Rename to `save_site_flow_cache()` and `save_site_flow_fd()`. |
| 3.2 | `07`, `08`, `09`, `12` | `parse_block()` / `.parse_block()` / `.pb()` defined four times with identical regex. Sourcing order decides which non-dotted version survives. | One definition in a `r/utils_blocks.R`. |
| 3.3 | `WorkingFPCA_robust.R::save_site()` | Ignores its `which` argument (`match.arg` is commented out) and hardcodes `output/models/<SS>_site_results.RData`, duplicating `PATHS$fit_out`. | Drop the unused argument; write to `PATHS$fit_out`. |
| 3.4 | `RUN_norris.R` STEP 1b | `best_cv <- max(f$cv$cv_r2[1:2])` indexes the gate positionally. Reorder the table and the gate silently reads the wrong rows. | `max(f$cv$cv_r2[f$cv$estimator != "intercept only"])`. |
| 3.5 | `RUN_norris.R` STEP 6 | Re-derives `x_std` with `eval_flow_fd(readRDS(fp)$fd)` when the block already stores `$x_std` built the same way. Two paths to one quantity. | Use the stored `$x_std`. |
| 3.6 | `WorkingFPCA_robust.R::diagnose_response_shift()` | `inside <- with(df, old_df_present <- !is.na(logRS_old))` assigns into the `with()` environment and is never used. | Delete. |
| 3.7 | `08_diagnostics.R` | `%||%` defined at the bottom, used above; works only by lazy lookup, and shadows the `rlang`/`purrr` operator tidyverse attaches. | Delete and rely on the attached one, or rename `.or_na()`. |
| 3.8 | `WorkingFPCA_robust.R::run_site()` | `set.seed(seed)` with the file header stating "NO RNG in the fit path". The seed is inert. | Remove the seed or remove the claim. After adopting `propagate_draws()` there *is* RNG in the fit path, so keep the seed and update the header. |
| 3.9 | `06_build_future_flow_fd.R` | `.doy_cal()` uses `yday`, so in leap years every day after Feb 29 is matched to the *previous* day's climatology `ch`. The same shift exists in the training cache, so it largely cancels — but `ch(d)` for `d > 59` is a two-date mixture. | Harmless in magnitude, but state it in Methods rather than carrying it silently. Fix properly by indexing on month–day. |
| 3.10 | `01`, `02`, `03` headers | Filenames in the banner comments (`00c_`, `01_`, `02_`, `03_`) do not match the actual filenames (`02_`, `03_`, `04_`, `05_`). | Sync. Costs nothing, saves a reader ten minutes. |

---

## What I added rather than rewrote

| File | Purpose |
|---|---|
| `R/15_pooling_and_cv.R` | Correct posterior propagation, direction probabilities, blocked CV, circular-shift permutation null, CV-shrunk explained variance. Drop-in; `pool_rubin()` left intact for a side-by-side. |
| `R/14_seasonal_baseline.R` | The four-window water-year estimator of T2.4, with the same gates, plus a head-to-head table against the functional fit. |
| `R/13_survival_production.R` | The parallel survival + total-production layer (task 3). |
| `methods_PNAS.Rmd` | Materials and Methods, PNAS structure, no hardcoded numbers. |
| `RESULTS.Rmd` | `github_document` results report that branches on the gate. |

## Staged order

Run these one at a time and record the headline numbers after each. Do not bundle.

1. **T1.2** — fix and re-run the cache. Everything downstream is conditional on this.
2. **T1.1** — fix the band labels. Re-generate β(t) figures. Nothing else changes.
3. **T1.5** — lag assertions and comment repair. Confirms the fit and the projection agree.
4. **T1.4** — blocked CV as the headline gate. Record the number.
5. **T2.4** — seasonal baseline head-to-head. This decides which model you publish.
6. **T1.3** — `sigmaR` correction, using the gate number from step 4.
7. **T2.1 / T2.2** — swap pooling, confirm intervals agree, delete the Rubin caveats.
8. **Task 3** — survival layer, only after the recruitment gate has a settled answer.
