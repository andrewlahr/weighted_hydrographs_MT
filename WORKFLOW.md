# Workflow

What to run, in what order, and what to check at each stop.

Two things worth knowing before you start.

**Restart R after replacing scripts.** `source()` does not clear previous
definitions, so an old function can linger in the session and produce errors that
point at the wrong place. *Session → Restart R* (Ctrl/Cmd+Shift+F10). Four of the
confusing failures so far have been this.

**The three checkers exist because the failures they catch are silent.** They take
about a second each and each caught a real bug that would otherwise have surfaced
as a broken published site or a plausible-looking wrong number.

---

## Every time

```r
# 1. verify the setup                      ~1 second
source("check_setup.R")

# 2. run the analysis                      minutes
source("RUN_ALL.R")

# 3. READ THE GATE before anything else
read.csv("output/tables/gate.csv")

# 4. build the website                     ~1 minute
source("render_site.R")

# 5. verify the site                       ~1 second
source("diagnose_site.R")
```

```bash
# 6. publish
bash publish_site.sh
```

---

## First run only

```bash
bash setup_github.sh WH_BOR_Trout
```

Then, once, in the browser: **Settings → Pages → Source: "Deploy from a branch" →
Branch `gh-pages` → folder `/ (root)` → Save.**

Delete `.github/workflows/deploy-site.yml` unless your institution requires
Actions-based deployment. It needs a *different* Pages source setting, and having
both active makes every workflow run fail while the site keeps working — a
confusing signal to leave lying around.

---

## What each step does, and what to look at

### 1. `check_setup.R`

Verifies packages, that `config.R` loads, that every path resolves, that the
params CSVs parse and yield years, and that no file on disk uses a **retired
symbol** (which is how a stale copy announces itself).

Three failures to take seriously:

| Message | Meaning |
|---|---|
| `STALE FILES DETECTED` | An old copy of a script. Replace it; do not try to make the retired symbol exist. |
| `flow lag configured for every active site` **FAIL** | A site is missing from `FLOW_LAG_BY_SITE`. It will silently default, shifting every flow window by a year. |
| `MISSING` on a path | Fix `CFG$paths` in `config.R`. |

### 2. `RUN_ALL.R`

Runs scripts 01–09. Each saves before the next begins, so you can run them one at
a time while debugging.

Watch the console for:

- **the implied year range** from script 01 — confirm it matches the IPM
- **the flow lag and which mechanism it implies** — spawning-year vs age-0 rearing-year
- **`biomass identity residual`** from script 07 — should be ~1e-16; anything larger means the age bookkeeping has drifted and the numbers are not usable

Not in `RUN_ALL.R`, run separately when relevant:

```r
source("R/10_rulecurve.R")           # equilibrium K and MS; needs the FishCast export
source("R/diag_fpc_truncation.R")    # only if estimator = "fpc"
```

### 3. Read the gate

```r
read.csv("output/tables/gate.csv")
```

**This is the most important output in the project.** Everything downstream is
numerically fine whether or not it passes; the gate is what says whether it means
anything.

Each site has three rows: `beta:penalized`, `beta:fpc`, `seasonal`. What to look
for:

- **`passes`** — blocked CV R² > 0 **and** permutation p ≤ 0.10
- **agreement between the two β arms** — if they disagree, the daily structure is coming from the estimator rather than the data, and no daily recommendation is defensible
- **the gap between `r2_loo` and `r2_blocked`** — that gap is the autocorrelation leak the blocked design removes. A large one means leave-one-out was flattering the model badly.

If nothing passes, the honest deliverable is the null result, and the pages will
say so themselves.

Then:

```r
read.csv("output/tables/best_day_intervals.csv")       # can you name a day?
read.csv("output/tables/decision_window_schedule.csv") # the operational answer
read.csv("output/tables/derived_stats.csv")            # every number the manuscript quotes
```

### 4. `render_site.R`

Cleans `_site/`, generates one wrapper page per active site, renders, and verifies
that every referenced image landed in `_site/`.

It **stops** rather than renders if: a `manuscript/` file uses a retired symbol,
`_site.yml` excludes `figures`, or a stray document would be published as a page.

Preview locally: open `_site/index.html`.

### 5. `diagnose_site.R`

Walks the figure chain and names the first broken link. `index.html` having zero
figures is **correct** — it is a text overview. The figures live on the per-site
pages and `results_among_sites.html`.

### 6. `publish_site.sh`

Pushes `_site/` to `gh-pages` via a git worktree, so your working directory and
`main` are untouched. Refuses to publish if any referenced image is missing.

---

## Adding a site

1. Read the selected flow lag from that site's `_RecLagInclusionProbQuad.csv` and add it to `FLOW_LAG_BY_SITE` in `config.R`. **Do not skip this** — the default is invisible and wrong at any site whose lag is not 3.
2. Add the site name to `CFG$sites$active`.
3. If its files do not follow the usual convention, add a `switch()` branch to `params_path()` or an `if()` to `params_filter()`.
4. `source("check_setup.R")` — it will tell you if the lag or a path is missing.
5. Re-run from step 2 of the main workflow.

Only sites in `active` get a page, and the selector lists only those, so it never
offers a 404.

**Sites with BoR forecasts** are listed in `CFG$sites$bor`. A site not in that list
gets every result except the scenario sections, which are replaced by a labelled
note distinguishing *data not available* from *no effect found*.

---

## Do a two-site run before all 23

Put two sites in `CFG$sites$active` and run the whole workflow.

The pipeline has been exercised almost entirely on Madison.Norris, and three bugs
have already been found that are **invisible at one site**: a `geom_hline` with
vector parameters that breaks under faceting, a cross-site β(d) comparison that
ignored per-site flow lags, and a results page reading a field that does not
exist. A two-site run flushes out that class cheaply.

If it throws errors, collect them and work through them in one pass rather than
one at a time.

---

## Moving to another machine (including Claude Code)

**Code goes via GitHub, not the drive.** `bash setup_github.sh` then `git clone`
on the other machine. That gives you version history and removes the whole class
of stale-file problems that come from copying files one at a time.

**Data goes on the drive.** `output/` and every `.rds`/`.csv` are git-ignored on
purpose, so the JAGS posteriors, imputed flows and params CSVs have to travel
separately.

**The directory layout is load-bearing.** `config.R` uses relative paths:

```
~/anywhere/
├── LL/                      <- posteriors, imputed flows, Data/
├── Jefferson/               <- Jefferson.Waterloo params CSVs
└── WH_BOR_Trout/            <- this project
```

`data_root = "../LL/Data"` resolves from the project root, so `LL/` must be a
**sibling** of `WH_BOR_Trout/`, not a parent or a cousin. If you lay it out
differently, edit `CFG$paths` — that is the only file that needs changing.

Then, on the new machine:

```r
source("check_setup.R")   # tells you exactly which path is wrong, if any
```

`CLAUDE.md` at the project root carries the house rules, the project facts that
are easy to get wrong, and the failure modes this project has already hit. Claude
Code reads it automatically at the start of every session.

---

## When something breaks

| Symptom | First thing to try |
|---|---|
| `could not find function` | Stale file. *Restart R*, then `source("check_setup.R")`. |
| `object 'X' not found` for something retired | Same. |
| Figures missing from the published site | `source("diagnose_site.R")` — it names the broken link. |
| A table is all `NA` | Usually a field-name mismatch after a rename. `dplyr` returns empty rather than erroring. |
| Site renders but a section says NOT AVAILABLE | That stage has not been run for this site. Intended behaviour. |
| Everything passes but the live site is stale | Re-run `publish_site.sh`, then hard-refresh the browser. |

---

## What to keep as you go

`PROJECT_LOG.md` — decisions, findings, and what is still open. Append rather than
overwrite; it is the record of *why*, which the code cannot carry.

`docs/notes/daily/<date>.md` — a session summary ending in a continuation prompt,
so a new chat can pick up without re-deriving context.
