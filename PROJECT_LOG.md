# Project log — Weighted Hydrographs / FPCA analysis

Running record of decisions, changes, and open questions. **Newest entries at the
top.** Every session appends here; nothing is deleted, only superseded.

**How to use this:** at the start of a new chat, paste the "Continuation prompt"
from the most recent daily summary in `docs/daily/`. That plus this log is enough
context to pick up mid-stream.

**Conventions**
- `[DECISION]` a choice was made and is now binding until explicitly revisited
- `[OPEN]` a question posed but not answered
- `[CHANGE]` code or documents changed
- `[FINDING]` something discovered about the data or the existing code

---

## 2026-08-05 — Session 17: flow-mode figure added to script 03

### `[CHANGE]` Figures 3e and 3f — the modes β(d) is built from
Requested from a reference figure. β(d) alone does not show *what shape of flow
variation* the model responds to; these do.

**Two design choices that make it readable, both non-obvious:**

1. **Sign orientation.** `prcomp` eigenvector signs are arbitrary — flip φₖ,
   negate bₖ, and β(d) is unchanged. Each mode is therefore flipped so its
   regression coefficient is **positive**, making every panel read the same way:
   blue = more water than average on those days goes with better recruitment.
   Without this the colours mean opposite things in different panels and the
   figure is actively misleading rather than merely unclear.

2. **Two variances reported per mode.** "Flow var." is what *selected* the mode;
   "recruit var." is what makes it *interesting*. They answer different questions
   and a mode can score high on one and low on the other. Panels are ordered by
   recruit variance, not flow variance, because ordering by the latter buries
   exactly the case worth seeing.

**Figure 3f** shows which years load high on each mode — turning an abstract shape
into "1997 and 2011 looked like this", which is how a reader sanity-checks the
modes against remembered hydrology.

### `[CHANGE]` `fpc_modes.csv` and a report section
One row per retained component with `p_direction` and `consistent_sign`, so the
supported modes can be quoted without eyeballing panels. Rendered in
`results_by_site.Rmd` §1.1, with prose that fires when the top recruit-variance
mode is **not** FPC1 — the central objection to selecting on predictor variance,
made visible rather than hypothetical.

### `[CHANGE]` Per-draw component coefficients captured in script 03
The eigenfunctions do not change across posterior draws (FPCA runs on the
hydrographs, which are data), so only the coefficients move. `fpc_coef` [M × K] is
now stored, which is what allows the direction probabilities.

### `[FINDING]` Stale label in the gate table
`results_by_site.Rmd` had `ifelse(form == "beta", ...)`, which stopped matching
when Session 6 relabelled the arms `beta:penalized` / `beta:fpc`. Every functional
row would have been labelled "4 windows". Fixed to prefix-match and show which
estimator.

### `[OPEN]` In-sample recruit variance is optimistic and labelled as such
Components were chosen on flow variance and then tested against recruitment, so
the percentages in Figure 3e are post-selection. Stated in the subtitle, the table
caption, and the console output. The blocked CV in script 05 remains the number
that decides anything.

---

## 2026-07-29 — Session 40: config.R replacement wiped the site registry

The published site showed one site in the selector. `render_site.R` generates one
page per `CFG$sites$active`, and the shipped `config.R` lists only
`Madison.Norris`.

### `[FINDING]` My design, not a copying mistake
`config.R` mixed two kinds of content:

- **analysis defaults** — windows, fitting parameters, estimator machinery, which change as the method develops and which I therefore ship repeatedly
- **the project registry** — active sites, per-site flow lags, stock node, estimator choice, which are irreplaceable and specific to this project

Every replacement of `config.R` silently wiped the second kind. Six configured
sites and six per-site flow lags (Norris 3, Cascade 2, Craig 3, Melrose 2,
FishAndGame 2, Hildreth 2), plus `stock_node`, `estimator` and the fpc rule,
reverted to placeholders. **The only visible symptom was a short dropdown.**

Everything else kept working, which is what made it dangerous: a single-site run
of a six-site configuration produces perfectly valid output for one site.

### `[CHANGE]` `config_local.R`, sourced last
Holds the site registry, the flow lags, and the analysis choices, pre-filled from
Andrew's own `check_setup.R` output. `config.R` sources it at the end, so
anything there wins and `config.R` can be replaced freely.

Committed, not git-ignored: the site registry and the flow lags are part of the
analysis and belong in the repository.

### `[CHANGE]` Two guards
- `config.R` warns when `config_local.R` is absent, naming the single placeholder site it is falling back to.
- `check_setup.R` reports whether the file is present and how many sites are active, and flags a single active site as worth confirming.

### `[NOTE]` The general lesson
Any file I ship repeatedly must not contain state only the user has. This was
avoidable — `config.R` was described from the first session as "the only file
that differs between machines", which should have made it the one file never
shipped again.

---

## 2026-07-29 — Session 39: 800 MB of model output in git history

`publish_site.sh` was rejected by GitHub: `beta_recruitment.rds` 368 MB,
`beta_survival.rds` 354 MB, `response.rds` 78 MB — over the 100 MB hard limit.

### `[FINDING]` The files are in HISTORY, not in the site
`gh-pages` HEAD was `d7a70b4 asdfa 233` — a hand-made commit, not one of
`publish_site.sh`'s (`Rendered site: <date>`). So the branch was created from
`main` and inherited its ancestry, including a commit made before `.gitignore`
was in place.

**`.gitignore` does not untrack an already-committed file.** The current tree held
only HTML; the push failed on the ancestry. Deleting the files changes nothing.

### `[CHANGE]` `publish_site.sh` builds gh-pages as a single ORPHAN commit
Each publish creates a parentless commit containing exactly `_site/` and
force-pushes it. Verified in a scratch repository that reproduced the inheritance:
old branch carries the blob, orphan build has 1 commit, 0 large blobs, 3 files.

Rationale: the site is build output, its history has no value, and the record is
the source on `main` which regenerates it. A branch with no ancestry cannot grow
and cannot inherit. This is what static-site deploy tooling does.

Also added a size guard that refuses to push if anything in `_site/` exceeds
45 MB, naming the file — cheaper than a rejected push.

### `[OPEN]` `main` still needs its history rebuilt
The orphan fix makes the *site* publish; it does not clean `main`, so
`git push origin main` will still be rejected. `docs/GITHUB_PAGES.md` now
documents both routes: orphan-squash (no tooling, right for a young repo) and
`git filter-repo` (preserves history).

### `[NOTE]` Why the earlier symptom was so confusing
Sessions 28–38 chased a page that would not update through four distinct causes —
a stale `_site.yml`, an uncleaned `_site/`, a leftover worktree, and finally this.
Each was real and each masked the next. The size rejection was the root cause of
"the page is still not updating": **no push had ever succeeded.**

---

## 2026-07-29 — Session 38: publish_site.sh left a worktree behind on failure

A network drop mid-push put `publish_site.sh` into a state where every subsequent
run failed with `fatal: a branch named 'gh-pages' already exists`.

### `[FINDING]` A four-step cascade, with the real error suppressed
1. The push failed on `Could not resolve host`. `set -e` aborted the script, so the `git worktree remove` at the end never ran.
2. `.gh-pages-worktree` remained, with `gh-pages` checked out.
3. Next run: `git worktree add "$TMP" "$BRANCH"` failed — git refuses to check one branch out in two worktrees — but `2>/dev/null` swallowed the message, which said exactly what was wrong: *'gh-pages' is already used by worktree at ...*
4. It fell through to `git worktree add -b`, which cannot be right when the branch already exists, producing the misleading error.

Reproduced in a scratch repository and confirmed the fix.

### `[CHANGE]` `publish_site.sh` rewritten
- **`trap cleanup EXIT`** — the worktree is removed on every exit path, including failure. This is the root fix.
- **Clears a leftover worktree at the start**, so an older interrupted run cannot poison a new one.
- **Reachability checked before any destructive work.** An offline run now stops with nothing changed, rather than committing and then failing at the push.
- **Three explicit branch cases** (local / remote-only / nowhere) instead of a chain with the error suppressed.
- **Detects and reports unpushed commits** from an interrupted run, and pushes them.
- **Pushes even when the diff is empty.** The old version skipped the push when there was nothing new to commit — which would have stranded the interrupted run's commit indefinitely. That bug would have surfaced only as a site that silently stopped updating.
- **Push failure now says the commit is safe locally** and that re-running will send it.

### `[NOTE]` Recovery for the current state
The interrupted run's commit succeeded locally; only the push failed. The new
script picks it up automatically. By hand it would be:
`git worktree remove .gh-pages-worktree --force && git worktree prune && git push origin gh-pages`

---

## 2026-07-29 — Session 37: check_setup found six things; two were its own false alarms

The setup check now runs end to end across six sites. Findings:

### `[FINDING]` False alarm 1 — the scanner read its own retired-symbol list
`render_site.R` was reported as using 15 retired symbols. It *contains* them, as
the `RETIRED` vector the guard scans with. The three guard files
(`check_setup.R`, `render_site.R`, `diagnose_site.R`) are now excluded from the
scan, because a literal list of retired names is exactly what they should hold.

### `[FINDING]` False alarm 2 — "NOT CONFIGURED" for every site
Andrew's `config.R` defines `flow_lag()` as a `switch()` with all six sites and
correct values (Norris 3, Cascade 2, Craig 3, Melrose 2, FishAndGame 2,
Hildreth 2). The check tested `exists("FLOW_LAG_BY_SITE")`, which is the *named
vector* form introduced in session 21, and reported everything unconfigured.

A check that cries wolf is worse than none. Both `00_config.R` and
`check_setup.R` now distinguish "inspectable and unset" from "not inspectable",
and say so rather than asserting a fault.

### `[FINDING]` Real — the teaching scripts were still on the water-year axis
`explain_beta_and_resolution.R` and `explain_estimator_choice.R` defined their own
`WY_B`/`WY_L`. Being standalone they never errored, but they would have taught the
method on an axis contradicting every result figure. Converted to calendar
`MON_B`/`MON_L`.

### `[FINDING]` Real — `R/10_rulecurve.R` was absent from the expected-files list
So it was simultaneously reported missing from the pipeline and flagged as an
unexpected file in `R/`. Added.

### `[FINDING]` Real — the rule-curve posterior was sought in one folder only
The export names `Madison.Norris_IndicatorVarSel_topModSummer.rds` but not its
folder; the code assumed `data_root`, and fits live in `posterior_dir`. Both
`check_setup.R` and `10_rulecurve.R` now try `posterior_dir` then `data_root` and
report which was used.

### `[OPEN]` `stock_node = "NAdults"` — a substantive choice, not a bug
Flagged loudly by the startup banner and worth a decision. `BAdults` is adult
biomass in grams and is what the IPM's own Ricker uses; `NAdults` is numbers. With
`NAdults` the response is estimated against one stock definition and projected
with another. It was set deliberately or inherited — either way it should be a
recorded decision rather than a default.

### `[NOTE]` Six sites, 36–47 years each, all inputs resolving
Madison.Norris 47, Missouri.Cascade 39, Missouri.Craig 44, BigHole.Melrose 36,
Beaverhead.FishAndGame 47, Beaverhead.Hildreth 47. This is the first multi-site
run, which is exactly the configuration the single-site bugs of sessions 24 and 32
were hiding in.

---

## 2026-07-29 — Session 36: orphaned top-level `else`

`check_setup.R` failed to parse: `unexpected 'else'` at line 323.

### `[FINDING]` A syntax rule my bracket checks cannot see
At **top level**, R parses `if (cond) expr` as a complete statement, so an `else`
beginning the next line is orphaned and is a syntax error. Inside `{}` or inside
an unclosed `(`, the expression is incomplete and R keeps reading — which is why
the same shape parses fine elsewhere in the same files.

Braces and parentheses were balanced throughout, so every structural check I have
been running passed. This class of error is invisible to them.

### `[FINDING]` Two more, in `R/10_rulecurve.R`
Lines 318 and 487, both from the missing-quadratic-terms work in session 25. They
had never been caught because **that arm has not been run yet** — the file has
been edited three times and executed zero times.

Wrote a proper detector (line beginning `else`, at brace depth 0 **and** paren
depth 0, whose previous code line does not end in `}`) and swept every `.R` and
`.Rmd` in the project. Those three were the only occurrences; all now braced.

### `[CHANGE]` `check_setup.R` now parses itself
It validated every other script and never its own file, nor `render_site.R` or
`diagnose_site.R`. A syntax error in any of the three surfaced only as a bare
`source()` failure with no context. All three are now in the parse loop.

### `[NOTE]` Two lessons
1. **Balanced brackets is not "parses".** My verification has been checking
   bracket balance and calling it a syntax check. It is not one, and this is the
   second time that gap has shipped a defect (the first being the vectorised
   `geom_hline`, which was also structurally balanced).
2. **Unrun code accumulates errors silently.** `10_rulecurve.R` has been edited
   three times and never executed. Worth running it once against Madison.Norris,
   even just to reach the first `stop()`, before more edits pile up.

---

## 2026-07-29 — Session 35: check_setup load-order defect

`check_setup.R` failed with `could not find function "path_of"`.

### `[FINDING]` Two checks were placed above the config they depend on
The flow-lag check (session 21) and the rule-curve check (session 26) were both
inserted into the **syntax** section, which runs before `R/00_config.R` is
sourced. Neither `path_of()`, `SITES`, nor `CFG` existed yet.

The flow-lag check hid the problem: it is wrapped in
`if (exists("FLOW_LAG_BY_SITE"))`, which was FALSE that early, so it silently
skipped and looked fine. The rule-curve check reached `path_of()` and errored —
which is the better behaviour, and the reason the defect was found at all.

Both moved below the config-load section, with a comment marking the boundary:
anything touching config must sit below that line.

### `[CHANGE]` Swept the whole file for the same class of error
Checked every config-provided symbol against the position of the `source()` call.
Nothing else is referenced too early.

### `[NOTE]` The pattern
`check_setup.R` has grown by accretion — a block added per session, each inserted
wherever seemed convenient. That works until a block has a dependency the
position cannot satisfy. The file now has an explicit ordering contract; new
checks that touch config go below the marked line.

---

## 2026-07-29 — Session 34: the stray-page guard flagged its own template

`render_site.R` refused to render, listing `_site_template.Rmd` as a stray page.

### `[FINDING]` The guard contradicted its own error message
The message it prints says *"render_site() renders every .Rmd/.md that does not
start with `_`"* — and the guard then failed to apply that test:

```r
found  <- basename(list.files(..., "[.](Rmd|md)$"))
strays <- setdiff(found[!grepl("^site_.*[.]Rmd$", found)], PAGES)
```

`_site_template.Rmd` is not in `PAGES` and does not match the `site_*` pattern,
so it was flagged — despite the underscore prefix being the very mechanism that
keeps it out of the site, and the mechanism the message describes.

Introduced last session when the template was created. The same omission was in
`diagnose_site.R`; both now drop `^_` files before testing.

Verified against three cases: a correct install (clean), Andrew's current state
(flags only `results_by_site.Rmd`), and a genuine stray document (flags it).

### `[CHANGE]` The guard now names the specific fix
`results_by_site.Rmd` is not ambiguous — it was replaced by `_site_template.Rmd`
last session and should be deleted. Offering three generic options for a file
whose fate is known is unhelpful, so that case is now called out by name with the
exact command. Genuinely ambiguous strays still get the three options.

### `[NOTE]` Andrew's second flag is correct
`results_by_site.Rmd` still exists locally and must be removed:
`rm manuscript/results_by_site.Rmd`. After that the guard should pass.

---

## 2026-07-29 — Session 34: per-site pages actually per-site

Andrew: every site page shows faceted all-site figures and unfiltered tables.
Diagnosis was right in substance — the pages were not site-specific — though the
mechanism was not quite the one proposed.

### `[FINDING]` `save_fig()` was already correct; `FIG()` was hiding the gaps
`save_fig()` in `00_config.R` filters the plot's data to one site, drops a site
facet, and writes `<name>__<Site>.png`. Every script already calls it.

The bug was in `FIG(name, site)`: **when the per-site file was absent it silently
returned the all-sites figure.** One missing file and the page showed faceted
results for 23 sites, looking entirely plausible. Same class as every other
failure in this project — a silent fallback producing wrong-but-credible output.

`FIG()` now shows an explicit gap on a per-site page and never substitutes. A
visible hole is recoverable; a wrong figure that looks right is not.

### `[FINDING]` All TEN tables on the site page were unfiltered
Independent of the figures, and arguably worse: `gate-table`, `fpc-mode-table`,
`stage-table`, `iv-table`, `relw-table`, `dw-cost-table`, `dw-sched-table`,
`prod-table`, `sc-table`, `rc-table` all rendered every site's rows on every
site's page. Now every one filters on `SITE_FOCUS`, and the redundant `Site`
column is dropped where it appeared.

### `[FINDING]` 16 site-specific figures were produced but never shown
Scripts 01, 02, 04, 05, 06, 07 and 08 produce figures the site page never
referenced — including **the entire validation section** (`05_f5a/b/c`), the
response-construction diagnostics (`01_f1a/b/c`) and the hydrograph
standardization (`02_f2a-d`). All now on the page, in two new sections:

- **§0 What went into the model** — the response and its posterior uncertainty, the stock–recruit relationship, the hydrograph and the seasonal predictor correlations
- **§1.0 Does it survive validation?** — the three-way R² comparison, out-of-sample prediction, and the permutation null

The site page went from 22 figures to 38. §0 in particular matters: if posterior
uncertainty dominates real between-year variation at a site, the ceiling on the
whole analysis is low, and that should be visible before any coefficient is read.

### `[CHANGE]` Three additions so this cannot recur silently
1. `save_fig()` **re-titles** a filtered plot with the site name — otherwise a per-site figure carries a title written for the all-sites version.
2. `save_fig()` records `.FIG_INDEX`; `fig_report()` runs at the end of `RUN_ALL.R` and lists which figures split per site and which could not (no `site` column in the plot data).
3. `check_setup.R` cross-references every `FIG(name, SITE_FOCUS)` in the template against the files on disk and reports gaps **before** rendering.

### `[NOTE]` Why the diagnosis pointed at filenames
Because from the outside that is exactly what it looks like. The per-site files
either were not written on that machine — a stale `00_config.R` predating the
per-site logic is the likeliest explanation, this being the fifth such incident
— or were written and masked by the fallback. Either way `fig_report()` and the
`check_setup.R` check now make the answer visible rather than inferable.

---

## 2026-07-29 — Session 33: one results page per site, with a selector

Andrew asked for a way to choose which site's results to view, keeping the
among-site synthesis.

### `[DECISION]` One page per site, not tabsets
Tabsets on a single page were the obvious option and are wrong at this scale: 14
sites x ~22 figures is roughly 300 images loading at once, and the existing
figures are **faceted across sites**, so with 14 panels each becomes unreadable.

Per-site pages give a real URL to send a collaborator, load only what is being
looked at, and leave room for per-site figures later.

### `[CHANGE]` `results_by_site.Rmd` -> `_site_template.Rmd`
The leading underscore stops `render_site()` rendering it directly. It now reads
`SITE_FOCUS` and filters every table through a three-line `only()` helper that is
a no-op on tables without a `site` column, so it is safe to apply uniformly.

`render_site.R` generates one three-line wrapper per active site plus a
`results.Rmd` hub, deleting last run's wrappers first so a removed site cannot
linger as a page. Both are git-ignored build products; the content lives in the
template.

### `[CHANGE]` A plain `<select>` on every site page
Navigates on change. No JavaScript library, no build step, works on static
hosting. Carries links to the hub and to the among-site synthesis, so moving
between sites needs no back-tracking.

### `[CHANGE]` `FIG()` gains an optional `site` argument
Prefers `figures/<name>__<site>.png` when it exists and falls back to the faceted
all-site figure otherwise. All 22 calls in the template now pass `SITE_FOCUS`.

This is a migration path rather than a half-measure: the selector works today
against the existing faceted figures, and the plotting scripts can emit per-site
PNGs one at a time without any page changing. **Worth doing before 14 sites** —
faceted panels at that count are unreadable, which is the same problem that
motivated per-site pages.

### `[CHANGE]` Cross-references
`_site.yml` navbar Results -> `results.html`; `index.Rmd`, `results_among_sites.Rmd`,
`README.md`, `FILE_MAP.md`, `GITHUB_PAGES.md`, `PROPOSAL_02` all updated. The
stray-page guards in `render_site.R` and `diagnose_site.R` now accept generated
`site_*.Rmd` while still catching genuine strays.

### `[OPEN]` Per-site figures in the plotting scripts
Scripts 03, 04, 06, 06b, 07, 08, 09, 10 write faceted figures. Adding a per-site
loop that saves `<fig>__<site>.png` is mechanical, and `FIG()` will pick them up
with no page edits.

---

## 2026-07-29 — Session 33: per-site pages, site selector, BoR gating

Andrew: a site selector on the results tab; all 23 populations get the non-BoR
results, only the 8 with forecast flows get scenario sections; keep the all-site
and among-site views.

### `[DECISION]` One page per site, generated from one template
For static GitHub Pages the alternative — every site on one page with JavaScript
show/hide — would load ~500 images at once and give facets too small to read.
Instead `render_site.R` writes a three-line `site_<SITE>.Rmd` wrapper per active
site, each setting `SITE_FOCUS` and knitting `_site_template.Rmd` as a child.

Because `render_site()` picks the wrappers up natively they inherit the navbar
and theme automatically, which a standalone `rmarkdown::render()` would not.
`_site_template.Rmd` begins with an underscore, so it is never rendered on its
own. The wrappers are generated, therefore git-ignored — editing one by hand
would be silently overwritten on the next render.

Site names contain dots (`Madison.Norris`), so filenames use a sanitised form;
the selector and the hub both apply the same `safe()` transform.

### `[DECISION]` A missing input gets a labelled placeholder, never an empty panel
`CFG$sites$bor` lists the 8 populations with forecast hydrographs. Sections 4
(scenarios) and 4b (rule curve) are gated on `eval = HAS_BOR`; a site without
them gets a bordered note stating that this is a **data-availability limit, not a
modelling result**.

That distinction matters more than it looks. An empty scenario panel reads as
"the analysis found nothing" — a claim about trout. The placeholder says "the
input does not exist here" — a claim about data. Confusing the two would be a
real misreading for a BoR audience, and the 15 sites without forecasts are the
majority.

### `[CHANGE]` Availability is visible before you click
- the dropdown appends `(no BoR)` to sites without forecasts
- the hub table gains a `BoR forecasts` column
- both derive from `CFG$sites$bor`, so there is one source of truth

### `[FINDING]` I nearly built a second, conflicting mechanism
An interrupted turn had already written the generation block, hub and template
using `SITE_FOCUS` / `_site_template.Rmd`. I began adding a parallel
`THIS_SITE` / `_site_body.Rmd` implementation before checking. Removed mine and
kept the existing one, which was more complete — its hub carries per-site gate
status rather than being a bare menu.

Same for the selector: I added `SITE_PICKER()` to `_common.R` when the template
already had one. Removed it. Two copies of a widget is how they drift.

### `[NOTE]` Three sites, three roles
`results.html` (hub, gate status per site) · `site_<SITE>.html` (one site in
full) · `results_among_sites.html` (cross-site synthesis, RQ2). The old
`results_by_site.Rmd` is superseded by the hub plus the per-site pages.

### `[OPEN]` Add the other 15 sites to `CFG$sites$active`
Only sites in `active` get a page; the selector deliberately lists only those, so
it never offers a 404. Run the two-site dry run first — the `geom_hline` failure
in session 32 shows single-site assumptions are the likeliest remaining defects.

---

## 2026-07-29 — Session 32: faceted geom_hline with vector parameters

`03_fit_beta_recruitment.R` Figure 3b failed with
`Aesthetics must be either length 1 or the same as the data (15)`.

### `[FINDING]` A bug that only appears once there is more than one site
```r
geom_hline(yintercept = c(.1, .5, .9), linetype = c(3, 2, 3), colour = c(...3...))
```
`geom_hline` builds its own data from `yintercept` — three rows — and then
**replicates that data across facet panels**. With five sites the layer holds
15 rows, and the length-3 parameter vectors no longer match. The "15" in the
error message is 3 × 5.

At one site the layer is 3 rows and the code works, which is why it survived every
Norris run. It would have broken the moment the framework scaled to the 14 sites
it was built for — the exact situation it is heading into.

Fixed with two calls, each using **scalar** `linetype` and `colour`, which recycle
to any number of rows:
```r
geom_hline(yintercept = 0.5,        linetype = 2, colour = PAL[["mute"]]) +
geom_hline(yintercept = c(0.1, 0.9), linetype = 3, colour = PAL[["mute"]]) +
```
The three colours were identical anyway, so the vector bought nothing.

### `[CHANGE]` Swept the project for the same pattern
Checked every `geom_*` call for a vector parameter outside `aes()`, and every
`annotate()` with vector arguments. **This was the only occurrence.**

### `[NOTE]` The class of bug worth watching for
Anything that works at one site and breaks at many. The pipeline has been
exercised almost entirely on Madison.Norris, so single-site assumptions are the
most likely remaining defects. Others already found and fixed in this class: the
cross-site β(d) comparison ignoring per-site flow lags (session 24) and
`results_among_sites.Rmd` reading `BR$sites` (same session). Worth a deliberate
multi-site dry run — two sites in `CFG$sites$active` — before committing to all 14.

---

## 2026-07-29 — Session 31: figures fixed; I had the `exclude:` semantics wrong

The figure chain is now clean end to end: 41 PNGs written, copied, and copied into
`_site/`; all 23 references resolve. Only the orphaned `GITHUB_PAGES.html`
remained.

### `[FINDING]` My session-27 claim about `exclude:` was wrong
I said adding `*.md` to `exclude:` in `_site.yml` would stop stray documents being
published as pages. It does not. In rmarkdown:

- **`exclude:`** controls which files are **copied as site resources**
- **rendering** covers every `.Rmd`/`.md` that does not begin with an underscore

So `manuscript/GITHUB_PAGES.md` was re-rendered on every build regardless of the
exclude list. `_site/` had been cleaned correctly by the new `render_site.R` — the
page simply came back.

The documented ways to keep a file out of the render are: delete it, move it, or
prefix the filename with `_`.

This also means my session-28 fix was right for the wrong reason. Removing
`figures` from `exclude:` fixed the images because `exclude` genuinely does govern
resource copying — that part was correct. The `*.md` entry was always inert.

### `[CHANGE]` `render_site.R` — stray pages are now a hard stop
A note copied into `manuscript/` gets published, appears in no navbar, and is
reachable by anyone who guesses the URL. Internal documentation on a public site
is embarrassing rather than merely broken, so this stops rather than warns, and
names all three fixes (delete / move / underscore-prefix).

### `[CHANGE]` `diagnose_site.R` 4b distinguishes the two causes
An orphaned page is either stale output *or* a live stray source. The fixes
differ, so the check now looks in `manuscript/` and says which it is.

### `[CHANGE]` `manuscript/_site.yml` comment corrected
It asserted that `exclude:` keeps stray documents out of the site. Replaced with
the accurate mechanism.

### `[NOTE]` What Andrew needs to do
Delete `manuscript/GITHUB_PAGES.md` — it belongs in `docs/`, where a copy already
is. Then re-render. Everything else is clean.

---

## 2026-07-29 — Session 30: render_site now cleans and guards

Andrew ran `diagnose_site.R`; it reported step 3 failing — `_site/figures/` empty,
22 of 23 references broken. Two conclusions from that output.

### `[FINDING]` The `_site.yml` fix from session 28 had not reached the machine
The repository copy no longer excludes `figures`. The local one still did. The
diagnostic named the cause on the line, which is what it was for.

### `[FINDING]` `render_site()` never deletes stale output
`GITHUB_PAGES.html` was still in `_site/` and still being listed — a page rendered
before `*.md` was excluded in session 27. `render_site()` writes over what it
produces and leaves everything else, so a renamed page, or a document that used to
be rendered and no longer is, stays published indefinitely.

Nobody would find this by inspection; it only shows as a URL that still resolves
long after its source is gone.

### `[CHANGE]` `render_site.R`
1. **Refuses to render when `_site.yml` excludes `figures`.** Text scan, no yaml
   dependency, verified against both the broken and current configurations. The
   failure is now a stop with an explanation, not a silently broken publish.
2. **Cleans `_site/` before rendering.** Rebuilding from empty is the only way to
   guarantee the published site matches the source.

### `[CHANGE]` `diagnose_site.R`
- **4b** — flags any page in `_site/` with no corresponding `.Rmd`
- **6** — checks `_site.yml` for the `figures` exclusion directly, rather than only inferring it from step 3

### `[NOTE]` Why the local preview never showed this
Pages opened from `manuscript/` resolve `figures/x.png` against
`manuscript/figures/`, which exists and is full. The same HTML in `_site/`
resolves against `_site/figures/`, which was empty. A correct-looking preview and
a broken publish, from one exclude line.

---

## 2026-07-29 — Session 29: `index.html` has no figures by design; three real bugs behind the report

Andrew reported no figures after publishing, and supplied `index.html`.

### `[FINDING]` The reported symptom was not a bug
`index.html` is a text overview and has never carried figures. They live on
`results_by_site.html` and `results_among_sites.html`. Added
`diagnose_site.R`, which prints a figure count per page so this is settled in a
second rather than by inspection.

### `[FINDING]` The pasted HTML did expose three real bugs
Visible as `****[PENDING]****` and `Gate passed: NA` in the rendered page.

**1. The session-6 estimator rename was never propagated past `GATE_OK()`.**
`gate.csv` labels functional arms `beta:penalized` / `beta:fpc` — never plain
`beta`. Three places still matched exactly:

| Location | Consequence |
|---|---|
| `06_daily_sensitivity.R:223` | join returned zero rows -> `passes` all NA -> every table showed "Gate passed: NA" |
| `08_scenarios_bor.R:135` | scenario gate flag always NA |
| `index.Rmd:37-38` | headline R² and p rendered as `[PENDING]` |

None errored. `filter()` on no matches returns an empty frame, and `left_join()`
fills NA — the pipeline ran to completion and published a page asserting nothing.

`05_validate.R`'s three `form == "beta"` hits are a **local loop variable**, not
the column, and are correct.

**2. Double-bolded placeholder.** `V()` already returns `**[PENDING]**`, and the
`sprintf` wrapped it in `**` again, producing four literal asterisks.

**3. `index.Rmd` never linked the among-sites page** — it was in the navbar but
not in the body list, and the by-site description still claimed to contain the
among-site comparison.

### `[CHANGE]` `diagnose_site.R`
Walks all five links of the chain (PNGs written -> copied to `manuscript/figures/`
-> copied into `_site/figures/` -> referenced by pages -> `.nojekyll`) and names
the first break, with the `exclude: figures` trap called out at step 3.

### `[NOTE]` The pattern, third time
A rename propagated to the obvious consumer and not to the rest. Sessions 18, 19
and now 29 are the same failure: `dplyr` verbs turn a stale name into empty
output rather than an error, so the pipeline completes and publishes something
that looks finished. A grep for the old literal across `R/` and `manuscript/` is
the check; it is now written into the standing rule in session 19 and should have
been run then.

---

## 2026-07-29 — Session 28: I broke the published figures, and the fix that prevents it

Andrew: no figures on the published site. My fault, introduced in session 27.

### `[FINDING]` `exclude:` governs COPYING, not just page rendering
Session 27 added `figures` to the `exclude:` list in `manuscript/_site.yml` to
stop stray documents being published as pages. But `exclude` controls what
`render_site()` copies into `output_dir` at all — not merely what it renders. So
`manuscript/figures/` never reached `_site/figures/`, and every
`<img src="figures/x.png">` 404'd.

**The local preview still looked correct**, because pages opened from
`manuscript/` resolve images against `manuscript/figures/`, which does exist. The
break only appears once published, and it appears to a reader rather than to the
author. That is a worse failure than a build error.

Also removed `_common.R` from the exclude list — `render_site()` already skips
files beginning with `_`, so the entry was noise.

### `[CHANGE]` Three guards, because a comment is not a guard
1. **`_site.yml`** carries a prominent *DO NOT ADD `figures`* note explaining the copying-vs-rendering distinction, at the exact place someone would re-add it.
2. **`render_site.R`** scans the rendered HTML for every local `src="...png"` and reports any that is absent from `_site/`, naming the likely cause.
3. **`publish_site.sh`** makes it a hard stop: it counts missing images and refuses to push. A report is easy to scroll past; a refusal is not.

### `[CHANGE]` `docs/GITHUB_PAGES.md`
The troubleshooting row for missing figures now lists this cause first, ahead of
the `.nojekyll` cause, because it is the more likely one and the harder to spot.

### `[NOTE]` The pattern worth noticing
Sessions 27 and 28 are the same shape: a change that is correct in isolation
(exclude stray documents) with a consequence in a different subsystem (resource
copying). Both were caught by a user running the thing rather than by my review.
The verification added here — check the *output*, not the *intent* — is the kind
that would have caught it, and is now in the two places that matter.

---

## 2026-07-29 — Session 27: render_site guard; stray-page exclusion

`render_site.R` failed on Andrew's machine with
`could not find function "wday_date"` inside a `dplyr::transmute()` traceback.

### `[FINDING]` A stale `index.Rmd` — the fourth such incident
The repository copy of `index.Rmd` line 55 reads `doy_date(lo_doy)`; the local
copy still had `wday_date(lo_wday)`, retired in the calendar migration. Both the
function and the column names were pre-migration.

The failure mode is the worst kind: knitr got 86% through the page, then raised
an error naming `dplyr` and `rlang` with no mention of the file. Nothing in the
14-frame backtrace says "index.Rmd is out of date."

### `[CHANGE]` `render_site.R` now checks before it renders
`check_setup.R` already had a stale-file scan, but `render_site.R` is the command
people actually reach for, so the check belongs in both. It now scans
`manuscript/` for retired symbols and stops with the file and line named, before
spending minutes rendering. Verified clean on the current repository and
confirmed it would have caught this case at line 55.

The two `RETIRED` lists — `check_setup.R` and `render_site.R` — guard different
moments and must both be extended when a symbol is retired. Noted in both files.

### `[FINDING]` `render_site()` publishes every `.Rmd` AND `.md` in the folder
The log shows it rendering `manuscript/GITHUB_PAGES.md` as a site page. That file
belongs in `docs/` and is not in the repository copy of `manuscript/`, so a stray
copy had been placed there — and `render_site()` silently turned project
documentation into a published page.

`_site.yml` now carries an `exclude:` list (`*.md`, `*.csv`, `*.rds`, `README*`,
`_common.R`, `figures`), so only the four intended pages are ever published.
`render_site.R` additionally prints a NOTE naming any non-page document it finds
in `manuscript/`.

### `[NOTE]` Four stale-file incidents now
`site_years`, `WY_LABELS` in `06`, `WY_LABELS` in `07`, and now `index.Rmd`. The
guards exist at three points — `check_setup.R` (session scan + disk scan) and
`render_site.R` (pre-render) — but they only help if run. Standing advice remains:
`source("check_setup.R")` after every file sync.

---

## 2026-07-29 — Session 26: deployment chain audited

All eight deployment files checked against the current project. Three real
defects, one of which would have produced a confusing recurring failure.

### `[FINDING]` `.gitignore` did not ignore the worktree `publish_site.sh` creates
`publish_site.sh` uses `TMP=".gh-pages-worktree"`; `.gitignore` had
`.gh-pages-wt/`. If a publish failed partway — a network drop, a rejected push —
the leftover worktree would sit in the repository as untracked and could be
committed on the next `git add -A`, dragging a second checkout of the whole site
onto `main`. Fixed.

### `[FINDING]` The two deployment routes conflict, and nothing said so
`publish_site.sh` needs **Settings → Pages → Source = "Deploy from a branch"
(gh-pages)**. `.github/workflows/deploy-site.yml` needs **Source = "GitHub
Actions"**. Pages has one source setting, so both cannot be active.

Following `GITHUB_PAGES.md` step 4 sets the branch source; leaving the workflow in
place then makes every workflow run fail at `deploy-pages` **while the site keeps
working**, published by the script. A failing Action beside a working site is
about as misleading a signal as this project could emit.

Now documented as a two-row table in `GITHUB_PAGES.md` and at the head of the
workflow, both saying: pick one, and most people should delete the workflow.

### `[FINDING]` Two dead `.gitignore` exceptions
`!RESULTS.html` and `!data/flow_fd/*_climatology.rds` both referenced the previous
pipeline. The standardization constants now live inside `output/models/flow.rds`
and are regenerated by `R/02_build_flow.R`, so the exception protected nothing.
`!figures/results/*.png` likewise belonged to the old RESULTS.md workflow.

### `[CHANGE]` `render_site.R` prerequisite list was four artefacts behind
Checked only `beta_recruitment`, `beta_survival`, `gate`, `sensitivity`. Added
`decision_window`, `production`, `scenarios`, `response`, so a partial render is
reported rather than silently producing NOT AVAILABLE panels. `rulecurve.rds` is
reported separately, because that arm is optional and its absence is a choice
rather than an incomplete run.

### `[CHANGE]` Verified end to end
- 46 files would be committed; `.gitignore` and `.github/workflows/` both included
- all 26 artefacts `_common.R` reads are produced by some script — no dangling reads
- all four `.Rmd` files are in the navbar
- `_site` and the worktree directory are both ignored, and `render_site.R` and `publish_site.sh` agree on the directory name
- no `config.yml` references anywhere in the chain
- removed an unused empty `docs/figures/`

### `[NOTE]` The empty `output/` subdirectories are correct
Git does not track empty directories, and `R/00_config.R` recreates
`output/{models,tables,figures}` on load. A fresh clone therefore works without
them being committed.

---

## 2026-07-29 — Session 25: optional quadratic flow terms; β(d) curves added to the report

### `[FINDING]` The rule curve assumed every site fitted b12r and b12S
Andrew reported it failing where the IPM's model selection found no quadratic
effect. Those terms are a **selection result**, not a fixed feature of the model,
and their absence carries information.

`R/10_rulecurve.R` now treats all four flow terms (`b1r`, `b12r`, `b1S`, `b12S`)
as optional, defaults any absent one to zero, and reports which were selected:

- **b12 absent** → the flow response is *linear* in z for that process. No interior optimum, and extrapolation is **safer** than with a quadratic, because a line cannot turn over.
- **b1 and b12 both absent** → that process has *no* flow response. Any change in K comes entirely from the other pathway. Warned loudly, because "no effect" and "bug" look identical in the output.
- **all four absent** → hard stop. Either this is the null fit rather than the flow-informed one, or the IPM selected no flow effect anywhere.

Only `la0`, `b`, `sigmaR`, `lSurv0`, `b6S` are now required.

### `[CHANGE]` Downstream reporting respects absent terms
- The extrapolation message names only the quadratics that exist, and when none do it says the response is linear and cannot turn over.
- The vertex table gains `quadratic_fitted` and a `note` column, so "linear in z (no quadratic selected)" no longer prints as an indistinguishable `NA`.
- `terms_present` is saved in `rulecurve.rds` and echoed in the footer — a model-selection result belongs in the report.

### `[FINDING]` β(d) curves were never on the results page
`03_f3a` (recruitment) and `04_f4a` (survival) were produced by the scripts and
referenced nowhere. The page showed summaries of β(d) throughout §3 and §4
without ever showing the curve they summarise.

New **§1.1 The fitted curves**, ahead of the modes section (now §1.2), with both
curves, the probability panel, and generated prose reporting the peak day, the
trough day, and the fraction of days whose interval excludes zero. If that
fraction falls below 5% the section says outright that the shape is coming from
the smoothness prior rather than the data.

### `[NOTE]` The FPC figures were already correct
`03_f3e` / `03_f3f` are `NULL` unless `estimator = "fpc"`, and §1.2 already
explains that the penalized spline has no components. Andrew is running the
penalized default, so the message was right — the gap was the missing β(d), not
the modes.

### `[CHANGE]` Verified
Every `FIG()` call on the page resolves to a figure a script writes; all four Rmd
fence counts even.

---

## 2026-07-29 — Session 25: rule curve now handles sites without quadratic flow terms

Andrew: some sites' IPMs have no `b12r` and/or `b12S`, because model selection
found no quadratic effect of flow. The ported script stopped on those sites.

### `[FINDING]` The original script had the same asymmetry
`RUN_norris_rulecurve_BoR.R` supplied a zero fallback for a missing `b12S` but not
for `b12r`, so it worked at Norris and would have failed anywhere recruitment was
fitted without curvature. The port inherited that.

### `[DECISION]` A missing coefficient is zero, and that is not a patch
"Not selected" **means** the coefficient is zero, so substituting zero is the
correct model rather than a workaround. What matters is that the substitution
changes how the result must be read, so every one is logged and recorded:

| Absent | Consequence |
|---|---|
| `b12r` or `b12S` | That process is **linear in z** — no interior optimum, and extrapolation is *safer* than with a quadratic because a line cannot turn over |
| `b1r` **and** `b12r` | Recruitment has **no flow response**; any ΔK comes entirely from survival |
| `b1S` **and** `b12S` | Survival has no flow response; any ΔK comes entirely from recruitment |

The last two warn loudly. "No effect" and "bug" produce identical output — a flat
K across scenarios — and only a warning distinguishes them.

### `[CHANGE]` `R/10_rulecurve.R`
- `terms_present` records which flow terms the IPM actually selected, before any substitution
- the hard missing-node check now tests only the **core** nodes; flow terms are optional
- the vertex table reports `linear in z (no quadratic selected)` rather than a bare `NA`, so "linear response" and "missing value" do not read the same
- the extrapolation warning and the Figure 10b caption both branch: with no quadratic, extrapolation is described as still-extrapolation but incapable of turning over
- `terms_present` is saved to `rulecurve.rds` and echoed in the run footer

### `[CHANGE]` `manuscript/results_by_site.Rmd` §4b
Reports the selected flow terms per site — that is model-selection information and
belongs in the results — and states explicitly that unselected terms are zero
rather than a gap in the fit. The extrapolation caveat branches on whether a
quadratic exists. If either process is flow-null, a blockquote says so before any
K number is read.

### `[NOTE]` Verified across all four selection outcomes
Full-quadratic, linear-recruitment, linear-both, and recruitment-flow-null all
route correctly.

---

## 2026-07-29 — Session 24: methods.Rmd brought up to date

Andrew asked whether `methods.Rmd` had been updated. It had not — §4b was added to
`results_by_site.Rmd` for the rule curve while Methods was left describing an
analysis two arms short.

### `[FINDING]` Two whole analyses were absent from Methods
- **The allocation-season constraint** (script 06b). Methods described the unconstrained volume optimisation only. Added: the constrained optimisation is a different calculation, not a restricted plot — argmax over a subset, interval recomputed within the subset rather than truncated, and only windows lying wholly inside the season admitted. The **cost of the constraint** is now defined as a reported quantity, with the point that a low value is a statement about institutional timing rather than water volume.
- **The rule-curve arm** (script 10). Added with the closed-form replacement curve written out, K by descending intersection with the 1:1 line, MS by parabolic refinement, and both differences from the rest of the analysis stated explicitly: it uses the **flow-informed** IPM, and its covariate is the standardized annual summer mean verified against the IPM's own covariate to 1e-10.

### `[FINDING]` Another find/replace corruption in the SI
`S7` listed **"calendar-year versus calendar domain"** — a sensitivity analysis
comparing something against itself. Left over from the axis migration, same class
as the four found in session 16. Now reads "the calendar-year domain against a
water-year domain, which bears on whether an incubation signal spanning the year
boundary is being split" — which is the sensitivity that actually matters given the
known cost of the calendar axis.

### `[CHANGE]` SI additions
`S6b` allocation-season constraint; `S6c` rule-curve verification (covariate
reproduction, geometry-vs-posterior agreement under both weighting conventions,
fraction of draws where the replacement curve fails to cross, vertex locations).
`S7` extended with clamped versus unclamped scenario z.

### `[CHANGE]` A VERIFY note placed in the rule-curve section
The stable-age weighting has two conventions in the source implementation and the
analysis selects between them by which reproduces the posterior's biomass series.
Methods now instructs the author to state which was used and the agreement
obtained, rather than leaving it implicit.

### `[NOTE]` Verified after editing
Every inline R reference resolves from `_common.R` (`V`, `Vi`, `DW`, `doy_date`,
`RCV`, `SE`); fences balanced; brackets balanced.

### `[OPEN]` Methods still carries three `[VERIFY]`-class items
The mark–recapture design paragraph, the gage-to-reach distance, and now the
stable-age weighting convention. All need author input before submission.

---

## 2026-07-29 — Session 24: manuscript audit — `results_among_sites.Rmd` was broken

Andrew asked whether the three `.Rmd` files had been kept current. `methods.Rmd`
and `results_by_site.Rmd` had been updated alongside each migration.
**`results_among_sites.Rmd` had not been touched since it was written**, and was
broken in four ways.

### `[FINDING]` The page would have rendered entirely "NOT AVAILABLE"
It referenced `BR$sites` (16 times) and `BS$sites` (6 times). Script 03 saves
`list(fits = fits, ...)`, so those are `NULL` and every section's guard clause
fired. The RQ2 page would have shown nothing even with a complete analysis —
and, because each section degrades gracefully by design, it would have looked
like missing inputs rather than a bug.

### `[FINDING]` It read three fields that have never existed
`b$beta_mean`, `b$beta_lo`, `b$beta_hi`. The fit objects carry `beta_draws` and
`Vbeta`; the summarised curves live in `beta_recruitment.csv` /
`beta_survival.csv`, which scripts 03 and 04 already write with exactly the
needed columns. Rebuilt on those CSVs — one definition, no chance of the page and
the script drifting.

### `[FINDING]` The cross-site comparison was scientifically invalid after session 15
This is the one that matters. §1 compares β(d) shape across sites and reads
agreement as evidence of a shared mechanism. That inference requires the curves to
describe **the same biological year** — and since per-site flow lags were
introduced, they need not. Madison.Norris is lag 3 (spawning year);
BigHole.Melrose is lag 2 (age-0 rearing year). Day 200 is the summer *before*
spawning at one site and a fish's *first* summer at the other.

Pooling them and calling agreement corroboration would have been wrong, and the
figure gave no hint of it. Fixed:

- a lag table and an explicit warning when more than one lag is in use
- both §1 figures now **facet by lag group**, and the across-site mean is computed within a group
- the agreement run-length text reports per group

### `[FINDING]` §4 referenced columns script 06 has never written
`delta_logRS` and `Q_baseline`. The actual columns are `Qbar_cfs`, `effect`,
`sens_per_delta`. Rebuilt; the 1/Q prediction test now runs on real data.

### `[CHANGE]` `manuscript/_common.R`
Exposes `BETAR` / `BETAS` (the per-day curve tables) and two helpers, `lag_of()`
and `lag_group_of()`, so the comparability grouping has one definition rather than
being re-derived per chunk.

### `[NOTE]` Why this went unnoticed
Every section of these pages is written to degrade gracefully — a missing input
renders "NOT AVAILABLE" rather than erroring. That is right for a report meant to
be built mid-analysis, but it means a **structural** bug presents identically to a
**missing input**. The audit that caught it compared field-by-field against what
the scripts actually save; that check should be run on the `.Rmd` files whenever a
saved object changes, not only on the R scripts.

---

## 2026-07-29 — Session 23: rule-curve arm ported as `R/10_rulecurve.R`

`RUN_norris_rulecurve_BoR.R` (718 lines) ported into the project. The K/MS
mathematics is unchanged; paths, sites and outputs now come from `config.R`, so
adding a site is a config edit rather than a copy of the script.

### `[FINDING]` Two things had to be preserved, not unified
Both would have been natural "tidying" and both would have silently destroyed the
analysis.

1. **It reads the FLOW-INFORMED IPM, not the null fit.** It needs `b1r`, `b12r`,
   `b1S`, `b12S` — the IPM's own fitted flow coefficients. The null posterior used
   by scripts 01–09 has no such terms, so pointing this arm at it would zero the
   flow response. No circularity concern: this arm does not *estimate* a flow
   effect, it propagates one the IPM already fitted to its equilibrium consequence.

2. **It uses its own standardization.** β(t) integrates daily anomaly curves
   scaled per day-of-year; the rule curve needs the z of the *annual summer mean*
   on exactly the scale the IPM was fitted with. GATE 1 verifies it reproduces the
   IPM's own covariate to 1e-10 and stops otherwise. Forcing it onto the script-02
   constants would put `la0`, `b` and `b1r` off-scale and every K would be wrong
   while looking entirely plausible.

The summer window (day 196–273, 15 Jul – 30 Sep) was already calendar
day-of-year, so the axis migration required no change here.

### `[CHANGE]` What was kept, dropped, and improved
**Kept:** the closed-form engine, K by linear interpolation of the descending 1:1
crossing, MS by parabolic refinement, per-draw S_MSY, deterministic draw thinning
(common random numbers across scenarios), the standardization contract, the
geometry-vs-posterior scale check, extrapolation diagnostics and the quadratic
vertex report.

**Dropped:** STEP 7, which reproduced FishCast's cached CSV. A regression test
against a legacy artefact, not part of the analysis.

**Improved:** the ssb_mode comparison used `<<-` to flip a global setting and flip
it back — the silent-global-mutation pattern this project has already been bitten
by, and it leaves `RC` corrupted if the line between errors. Rewritten as a local
function.

### `[CHANGE]` Integration
- `CFG$rulecurve` block plus `rulecurve_export_path()`, `rulecurve_bor_path()`, `rulecurve_observed_path()`
- **Not** added to `RUN_ALL.R`'s chain — it is a separate question with separate inputs. `RUN_ALL.R` points at it explicitly at the end.
- `check_setup.R` validates the export and the flow-informed posterior when the export is present, and skips silently when it is not
- `results_by_site.Rmd` §4b, with caveats that branch on extrapolation fraction, undefined-K fraction, and whether a quadratic vertex sits inside the training range

### `[NOTE]` K and script 07 are not comparable
K is an equilibrium under a *sustained* shift in summer mean flow. Script 07's
production sensitivity is a short-run response to a day-block perturbation.
Different question, different units, different time horizon. Stated in the script
footer and in §4b so the two are not read as competing estimates of one quantity.

### `[OPEN]` `ssb_mode` should be set by the GATE 2 number
`config.R` ships `"fishcast"` as inherited. GATE 2 reports the geometry-to-posterior
ratio for both modes; whichever is closer to 1.00 is correct, and the script warns
if the configured one is further. Set it from that number on first run.

---

## 2026-07-29 — Session 22: derived_stats type error, and a life-history timeline on the wrong axis

### `[FINDING]` `bind_rows()` type error in `09_figures.R`
`Can't combine ..1$value <double> and ..37$value <character>`. My session-14
addition put `estimator` and `fpc_rule` (labels) into a table that was otherwise
all numeric.

Fixed by storing `value` as **character for every stat**. This costs nothing:
`read.csv()` returns a mixed column as character regardless, so the in-memory type
now matches the on-disk type. `V()` and `Vi()` in `manuscript/_common.R` coerce
back with `as.numeric()`, and — importantly — return a genuinely non-numeric value
**as is** rather than as `NA`. Without that, `estimator = "penalized"` would have
rendered as `[PENDING]` and read as a missing result.

### `[FINDING]` The life-history timeline was never migrated to the calendar axis
Found while fixing the above. The `LIFE` table in `09_figures.R` was still on the
water-year index, so on the calendar axis every stage was **three months out of
place**:

| stage | was drawn at | should be |
|---|---|---|
| spawning | 1 Jan – 2 Mar | 1 Oct – 30 Nov |
| incubation | 1 Feb – 1 Jul | 1 Dec – 31 Mar |
| emergence | 1 Jun – 1 Aug | 1 May – 30 Jun |
| first summer | 1 Sep – 31 Dec | 1 Jul – 30 Sep |

**This is the RQ2 evidence base.** The entire life-history alignment argument
would have compared β(t) against windows wrong by a quarter of a year, and any
apparent alignment would have been an artefact. Recoded on calendar DOY.

### `[CHANGE]` Wrapping stages entered as two segments
Incubation (Dec–Mar) crosses the calendar boundary and is now two rows sharing one
stage label. `stage_tab` pools days by stage **name** before averaging, so
December and Jan–Mar do not appear as two separate "incubation" results.

That split is the calendar axis showing its cost honestly: the two halves of
incubation sit in different lag years and cannot both be resolved by a single
β(t). Documented in the `LIFE` block, along with the point that **which stages are
in frame at all depends on the site's flow lag** — β(t) covers one calendar year,
and at a lag equal to the recruit lag that year holds autumn spawning, while at a
shorter lag it holds emergence and first summer.

### `[OPEN]` `LIFE` is still placeholder data
Values must come from the literature or local MFWP observation, be cited, and be
fixed **before** looking at β(t). Setting them afterwards guarantees agreement and
demonstrates nothing. This was already flagged in session 5 and remains the
largest outstanding item for RQ2.

---

## 2026-07-29 — Session 21: unconfigured sites now warn; full replace list

Andrew hit `WY_LABELS` again, this time in `07_production_sensitivity.R`. The
repository copy uses `MON_L` / `MON_B` on all four lines — a third stale local
file. Rather than chase these one error at a time, produced the full list: **22
files use post-migration symbols**, which is effectively the whole project.
Replace everything in one pass.

### `[FINDING]` Andrew is running `Missouri.Craig`, which is not configured
Visible in the run log. Two silent defaults were in play:

- `flow_lag("Missouri.Craig")` fell through `switch()` to `3L` with no warning
- the site is not in `CFG$sites$all` either

The lag genuinely varies (Norris 3, BigHole.Melrose 2), so a wrong default shifts
every flow window by a year and still produces entirely plausible coefficients.
This is the highest-consequence silent failure remaining in the design, and it was
found by reading a progress log rather than by any check.

### `[CHANGE]` `flow_lag()` rewritten as a named vector with a loud fallback
`switch()` replaced by `FLOW_LAG_BY_SITE`, a named integer vector. Two gains:
every configured site is visible at once, and **membership can be tested** — which
is what allows an unconfigured site to warn rather than silently default.

```
flow_lag(): 'Missouri.Craig' is not configured, defaulting to 3.
  Read the selected lag from that site's _RecLagInclusionProbQuad.csv
  and add it to FLOW_LAG_BY_SITE in config.R. Until then, results for
  this site assume the spawning-year hypothesis and may be wrong.
```

### `[CHANGE]` Surfaced in two more places
- `00_config.R` startup prints `*** NOT CONFIGURED — default assumed ***` beside any such site.
- `check_setup.R` treats an unconfigured **active** site as a FAIL, not a note.

### `[NOTE]` The production budget is closing correctly
From the run log: `biomass identity residual = 1.61e-16`. The
`B[t] = B[t-1] + I + G - M` accounting holds to machine precision at
Missouri.Craig, so the age bookkeeping in `07` is sound.

### `[OPEN]` Sites still needing a confirmed flow lag
`Missouri.Craig`, `Ruby.Vigilante`, `Beaverhead.FishAndGame`, and any other site
being run. `Jefferson.Waterloo` is a placeholder at 3. Each needs its value from
`_RecLagInclusionProbQuad.csv`.

---

## 2026-07-29 — Session 20: stale-file detection added

Andrew hit `WY_LABELS` in `06_daily_sensitivity.R`. The repository copy of that
file uses `MON_L` / `MON_B` throughout and has no `WY_LABELS` — so this was a
**stale local copy**, the second such incident (the first was `site_years` in
session 13).

### `[FINDING]` My sweeps were unreliable
Several shell `grep` calls in sessions 16–19 returned empty for symbols that
demonstrably existed in the files. Re-running the same searches through Python,
reading files directly, gave correct results. Any "clean sweep" claim made on
shell grep alone in those sessions should be treated as unverified.

### `[FINDING]` `check_setup.R` was itself stale
It verified the existence of `wday_date`, `wday_month`, `WY_START`, `WY_B`, `WY_L`
— all retired in the calendar migration. It would have reported **false failures**
on a correct installation, which is worse than not checking: it teaches you to
ignore the tool. Updated to `doy_date`, `doy_month`, `MON_B`, `MON_L`, plus
`flow_lag`, `flow_year` and `CONFIG_VERSION`.

### `[CHANGE]` `check_setup.R` now scans the DISK, not just the session
The existing checks test what is *loaded*. The new scan tests what is *on disk*:
it greps every pipeline file for retired symbols and reports **file and line**.

```
[FAIL] STALE FILES DETECTED   3 use(s) of retired symbols
      R/06_daily_sensitivity.R:247  uses retired `WY_LABELS`
      ...
      These files are older copies. Replace them from the repository;
      do not try to make the retired symbol exist.
```

Verified to report zero hits against the current repository, so any hit on a
working machine is a genuine stale file. `RETIRED` covers three migrations:
water-year → calendar axis, `config.yml` → `config.R`, and the survival field
renames. **Extend `RETIRED` whenever a symbol is retired** — that is what keeps
this useful.

### `[NOTE]` Why this matters more than a version stamp
`CONFIG_VERSION` only helps if you think to check it, and it says nothing about
which *other* files are behind. The disk scan names the file and the line without
being asked, and it runs in the same second as the rest of `check_setup.R`.

Recommended: run `source("check_setup.R")` after every file sync, before
`RUN_ALL.R`.

---

## 2026-07-29 — Session 19: the rename fallout, third and final instance

Same root cause as session 18 — the `lag` -> `surv_lag` rename — surfacing a third
time, in `04_fit_beta_survival.R`:

```r
sapply(fits, `[[`, "lag")   # -> list of NULLs
sprintf("%s=%d", names(fits), <list>)   # -> "unsupported type"
```

### `[FINDING]` `sapply` converts a missing field into a misleading error
When extraction yields NULL for every element, `sapply` cannot simplify and
returns a **list**. `sprintf`'s `%d` then reports "unsupported type" — an error
about formatting, with no mention of the field that is actually missing.

Replaced with `vapply(fits, function(f) as.integer(f$surv_lag), integer(1))`,
which fails at the extraction with the field named. The equivalent line in
`03_fit_beta_recruitment.R` (`sapply(fits, "[[", "edf")`) was hardened the same
way even though `edf` is present, because the fragility is in the pattern.

### `[FINDING]` My session-18 audit had a hole, which is why this recurred
It checked `BR$fits[[...]]$field` and `BS$fits[[...]]$field` patterns — access
from *other* scripts. It did not check `f$field` inside `lapply(fits, ...)` within
the **same** script, which is where all three of these bugs lived.

Audit extended and re-run:

| Object | In-script accesses | Result |
|---|---|---|
| recruitment | Vbeta, Y, beta_draws, edf, fpc_coef, fpc_eigenfun, fpc_scores, fpc_var_individual, seasonal_coef, site, years | all present |
| survival | Vbeta, beta_draws, lag_sweep, site, surv_lag | all present |

### `[CHANGE]` `diag_fpc_truncation.R` guard
`do.call(rbind, lapply(BR$fits, "[[", "Curves"))` would yield NULL if `Curves`
were renamed, and fail later inside `prcomp` on a NULL matrix. Now checks first
and names the problem.

### `[NOTE]` Standing rule after any field rename
1. `options(warnPartialMatchDollar = TRUE)` is on — heed the warnings.
2. Prefer `vapply` with an explicit template over `sapply` for field extraction.
3. Run the saved-vs-read audit on **both** access patterns: cross-script
   (`OBJ$fits[[...]]$x`) and in-script (`f$x` inside `lapply(fits, ...)`).
4. Grep the old name across `R/` and `manuscript/` before declaring done.

Three sessions were spent on one rename because steps 2 and 3 were missing.

---

## 2026-07-29 — Session 18: field-rename fallout; partial-match warnings enabled

Andrew hit `'list' object cannot be coerced to type 'double'` in script 04. Root
cause was my session-17 rename, and R's `$` semantics turned one rename into three
defects — two of them silent.

### `[FINDING]` R's `$` partial matching turned a missing field into a confusing error
```r
mutate(site = f$site, chosen = lag == f$surv_lag)   # was f$lag
```
After `lag` was removed from the save block, `f$lag` did **not** error. `$` does
partial matching on lists, so it resolved to `f$lag_sweep` — a list — and the
failure surfaced as a coercion error inside `mutate()`, far from the cause.

### `[FINDING]` The same rename silently zeroed a count
```r
data.frame(lag = z$lag, n_years = length(z$surv_years), ...)   # was z$years
```
`z$years` had no partial match, so it returned `NULL`, and `length(NULL)` is `0`.
**No error at all** — the lag-sweep table would simply have reported zero years
for every lag.

### `[FINDING]` Three pre-existing name mismatches in the recruitment path
Predating session 17, from when the fpc diagnostics were added. `09_figures.R`
read `BR$fits[[s]]$var_explained`, `$K_capped`, `$K_unstable`; script 03 saves
them prefixed as `fpc_var_explained`, `fpc_K_capped`, `fpc_K_unstable`.

`isTRUE(NULL)` is `FALSE`, so **the capped and unstable flags would have reported
0 forever** — diagnostics added specifically to catch a silent problem, themselves
failing silently. Now corrected.

### `[CHANGE]` `options(warnPartialMatchDollar = TRUE, warnPartialMatchArgs = TRUE)`
Added to `R/00_config.R`. Turns partial matches into visible warnings. Would have
caught the `f$lag` case at first execution instead of as a coercion error two
functions downstream.

### `[CHANGE]` Saved-vs-read field audit run on both fit objects
| Object | Read | Result |
|---|---|---|
| `beta_recruitment.rds` | Curves, K_capped, K_unstable, edf, flow_lag, n_fpc, n_years, var_explained | 3 mismatches, fixed |
| `beta_survival.rds` | edf, mean_survival, surv_lag | consistent |

Also checked for prefix hazards (a read name that is a prefix of a saved name, the
condition that enables partial matching): none remain in either object.

`05_validate.R` reads `f$beta` and `f$model`, which neither saved object contains —
verified as a scope distinction, not a bug: inside `cv_one()`, `f` is the local
return of `fit_beta_curve()`, which does provide both.

### `[NOTE]` Lesson for future renames
A rename in R is not safe by inspection. `$` either partial-matches to a different
field or returns `NULL`, and neither raises an error at the rename site. The
routine after any rename: enable the partial-match warnings, run the saved-vs-read
audit, and grep for the old name across `R/` and `manuscript/`.

---

## 2026-07-29 — Session 17: 04_fit_beta_survival.R repaired

Andrew asked whether script 04 had actually been fixed in the calendar migration.
It had not been fully checked — my earlier sweep looked for stale *symbols*
(`WY_*`, `wday`, `water_year`) and 04 contained none, so it passed a check that
could not see the actual defects.

### `[FINDING]` A duplicate argument name silently discarded the flow-year provenance
```r
lag_fits[[...]] <- list(lag = Lg, ref = ref, E = Ek, Curves = Ck,
                        years = surv_years[ok],
                        years = FS$years[idx[ok]])   # <- shadowed
```
R builds a length-2 list with two elements both named `years`; `$years` returns
only the first. The hydrograph years were therefore lost, and the save block then
assigned the response years to *both* `surv_years` and `years`.

No error, no warning. The survival arm would have run and produced plausible
curves with no record of which calendar years' hydrographs went into them — the
exact provenance gap the recruitment arm's `flow_year` was made explicit to close.

Now `surv_years` (response) and `flow_years` (predictor), named distinctly.

### `[FINDING]` Two names for one value
`lag = B$lag` already existed at the top of the save block; adding `surv_lag`
created a redundancy. Removed the bare `lag`; `surv_lag` is the single name,
chosen to distinguish it from the recruitment flow lag in `config.R`. They are
separate hypotheses — recruitment responds at a spawning lag, survival responds in
or near the year it is measured — and one shared name invites conflating them.
`09_figures.R` updated to match.

### `[CHANGE]` Water-year phrasing in the lag-sweep comment
"matched to the calendar year ENDING in year t" was leftover water-year language
("the water year ending in year t"). On a calendar axis the mapping is direct:
survival year t matches calendar year t − Lg.

### `[CHANGE]` Field audit added to the routine
Compared every field script 04 saves against every field read downstream.
Read: `edf`, `mean_survival`, `surv_lag` — all present. Worth repeating after any
rename; a saved-vs-read mismatch is silent in R.

### `[OPEN]` The same audit should be run for `beta_recruitment.rds`
Only the survival object was checked this session.

---

## 2026-07-29 — Session 16: calendar axis replaces the water year

### `[DECISION]` The analysis runs on calendar day of year (1 = 1 Jan)
Andrew's call, on interpretability: the ecology audience is not the water-management
audience, and an October-start axis needs explaining to everyone in the first
group — a cost paid on every figure, in every talk, for the life of the project.

I had argued for the water year twice and was over-weighting it. On
re-examination the switch is a net win, for two reasons beyond readability:

**The lag mapping stopped being ambiguous.** The IPM selects its flow lag on a
calendar basis. The water-year version had to *translate* that with a conditional
offset (a calendar year straddles two water years, and which applied depended on
whether the mechanism sat in Oct–Dec or Jan–Sep). Now:
`flow_year(recruit_year, site) = recruit_year - flow_lag(site)`. Nothing to get
wrong, and it is exactly what the IPM chose.

**The allocation season stopped wrapping.** May–October is days 121–304 on a
calendar axis: contiguous. On the water-year axis May was day 213 and October day
31, which is why `06b` carried an ordered index plus a separate plotting position.
That machinery is deleted.

### `[FINDING]` The cost is smaller than I previously claimed
For `flow_lag = recruit_lag` sites the hydrograph year contains pre-spawn summer,
**spawning (Oct–Nov), and early incubation (Dec)**. Only incubation from January
onward falls outside. For `flow_lag = recruit_lag − 1` sites (BigHole.Melrose) the
rearing year is fully contained and the calendar axis is arguably a better fit
than the water year was. Documented with the mitigation options in
`docs/notes/CALENDAR_AXIS.md`.

### `[CHANGE]` Seasonal windows redefined as calendar quarters
`spawn/incubate/runoff/baseflow` on the water-year index →
`winter (1–90) / runoff (91–181) / summer (182–273) / autumn (274–365)`.
Each is contiguous, and each reads coherently under both lag interpretations —
`autumn` is spawning for lag-3 sites and first autumn for lag-2 sites.

### `[CHANGE]` Swept 18 files, ~95 references
`wday`→`doy`, `water_year`→`year`, `WY_B`/`WY_L`→`MON_B`/`MON_L`,
`wday_date`→`doy_date`, `flow_water_year`→`flow_year`; `WY_START` and
`biology$water_year_start_doy` removed entirely. The day-index remapping and year
reassignment in `02_build_flow.R` and `08_scenarios_bor.R` are gone — `doy` and
`year` now come straight from the date.

`01_build_response.R` prints the calendar year mapping per site and warns when the
flow lag differs from the recruit lag, or when it equals it (the incubation
caveat).

### `[FINDING]` Caught during the sweep
A dangling `mutate(` in `08_scenarios_bor.R` left by removing the water-year
construction — bracket-balance check found it before it could surface as a parse
error at run time.

### `[OPEN]` Figures and prose in `manuscript/` reference month names
The axis constants and helpers are updated, but any hand-written prose describing
"the water year" in the Rmd narrative should be re-read once the site renders.

---

## 2026-07-29 — Session 16: calendar-year axis throughout

### `[DECISION]` Water year retired. Everything is on calendar day-of-year (1 = 1 Jan).
Andrew asked for this on audience grounds — water-year axes confuse anyone who is
not a water professional. **The substantive argument is stronger than the
presentational one, and it goes against my earlier reasoning.**

The IPM's indicator-variable selection chooses a *calendar* year. Quantifying how
well the water-year construction matched that choice:

| flow_lag | IPM selected | water year used | months FROM the selected year |
|---|---|---|---|
| 3 (Norris) | calendar 1997 | 1998 (Oct 97 – Sep 98) | **3 of 12** |
| 2 (BigHole) | calendar 1998 | 1998 (Oct 97 – Sep 98) | 9 of 12 |

At Norris the analysis was drawing three quarters of its hydrograph from a year
the model selection did not choose. My Session 5 argument for the water year —
"it keeps the biological window intact" — prioritised a mechanism I assumed over
the year the IPM actually identified. Calendar year is 12/12 by construction.

### `[CHANGE]` What the calendar axis removed
- `flow_water_year()`'s conditional `+1 / +0` offset → `flow_year() = recruit_year - flow_lag(site)`. No conversion, nothing to get wrong.
- The decision window's boundary wrapping in `06b`. May–October is contiguous on a calendar axis (day 121–304), so the ordered `dec_idx` plus separate plotting position are gone.
- Day-index remapping and year reassignment in `02` and `08`.

### `[CHANGE]` Seasonal windows are now calendar quarters
`winter` (1–90), `runoff` (91–181), `summer` (182–273), `autumn` (274–365). Each
is contiguous and needs no explanation. They read differently by lag, and both
readings are coherent — at `flow_lag = 3`, `autumn` is spawning; at `flow_lag = 2`,
`winter` is late incubation and `summer` is first-summer rearing.

### `[FINDING]` `manuscript/_common.R` still held the water-year axis — every figure would have been mislabelled
The worst find of the session. `_common.R` retained
`MON_L <- c("Oct","Nov",...)` and a `doy_date()` anchored on 1 October, while the
data had already moved to calendar. **Every axis and every date in the manuscript
would have been three months off**, and consistently so — nothing would have
looked broken. Day 1 would read "Oct" when it was January.

Fixed, and both `MON_B` / `MON_L` definitions now verified identical between
`00_config.R` and `_common.R`. `diag_fpc_truncation.R` had the same stale anchor
and now calls `doy_date()` rather than formatting its own.

### `[FINDING]` Find-replace damage in `config.R` comments
An automated pass had produced sentences like "a calendar year straddles two
calendar years" and "May wrap the 1 October calendar-year boundary". Repaired,
and the water-year rationale rewritten as the historical note it now is.

### `[CHANGE]` Verified clean
No `spawn_water_year`, `flow_water_year`, `water_year`, `wday` or `WY_START`
remains in any script, manuscript file or config. The only surviving mentions are
comments explaining what the calendar axis replaced.

---

## 2026-07-29 — Session 16: calendar-year axis; repaired a corrupted find/replace

### `[DECISION]` Analysis moved to calendar day-of-year (1 = 1 January)
Andrew's call, on interpretability: results go to water managers, irrigators and
lease-holders who work in calendar years, and an axis anchored to 1 October needs
explaining to everyone outside hydrology.

My original objection is weaker than when I raised it, because the **site-specific
flow lag now carries the mechanism selection**. On a calendar axis the mapping is
also simpler and matches the original pipeline:

```r
flow_year(recruit_year, site) = recruit_year - flow_lag(site)
```

No conditional offset. The water-year version needed one because a calendar year
straddles two water years and which applied depended on the lag.

### `[FINDING]` The real cost, stated rather than buried
Incubation runs December (spawning year) through March (rearing year). On a
calendar axis those fall in **different lag years**, so a mechanism operating
continuously across the turn of the year is split and will read weakly in both.
Recorded in `docs/notes/CALENDAR_AXIS.md`, in the `02_build_flow.R` header, in
Methods, and as a limitation in `results_by_site.Rmd`.

### `[CHANGE]` Seasonal windows redefined as non-wrapping calendar quarters
`spawn/incubate/runoff/baseflow` → `winter` (1–90), `runoff` (91–181),
`summer` (182–273), `autumn` (274–365). The old `incubate` window wrapped the
calendar boundary and could not be expressed as a range. Biological meaning now
depends on the flow lag and is documented rather than baked into the names.

### `[FINDING]` The partial migration had left the pipeline BROKEN
Found and repaired:

1. **`02_build_flow.R` was a syntax error** — a dangling `q <- q %>%` with only comments after it, then a new assignment. Would not have parsed.
2. **`methods.Rmd` said "calendar-year axis (1 October – 30 September)"** — a naive find/replace had swapped the noun and left the dates. Wrong on its face.
3. **`methods.Rmd` said "a calendar year spans 1 October to 30 September"** — same corruption, plus it carried a coincidence argument that was specific to water years and is meaningless on a calendar axis.
4. **`results_by_site.Rmd` claimed the window "wraps the 1 October calendar-year boundary"** — on a calendar axis, May–October is days 121–304, contiguous, and cannot wrap.
5. **`02_build_flow.R` header said "CALENDAR-YEAR AXIS (Oct 1 - Sep 30)"** — same swap.
6. **`results_by_site.Rmd` asserted "the recruitment flow lag equals the recruit lag"** — false at BigHole.Melrose (2 ≠ 3). Now a chunk that reads the actual lag and branches between a spawn-year and a rearing-year framing.

Items 2–6 are the characteristic failure of find/replace on prose: the text stays
fluent and becomes false. Worth remembering for future axis or naming changes.

### `[CHANGE]` `06b_decision_window.R` simplified
May–October is now days 121–304, a plain contiguous range. The wrap-handling and
position-axis machinery is gone, replaced by a `stop()` if `start > end`.

### `[CHANGE]` Verified after migration
No unresolved config symbols; all 10 `RUN_ALL.R` steps present; brackets balanced
across every R file; all four Rmd fence counts even; no stale `WY_*`, `wday_*` or
`flow_water_year` references. The five surviving "water year" mentions are
historical comments explaining what changed.

### `[OPEN]` Cosmetic: `results_among_sites.Rmd` local variable `baseflow_at_best`
Computes from `DAILY`, not from `CFG$windows`, so it is functionally correct but
the name now echoes a retired window. Rename when convenient.

---

## 2026-07-29 — Session 15: per-site flow lag restored (my error)

### `[FINDING]` I wrongly dissolved `FLOW_LAG` in Session 5
Andrew corrected this. There are **two different lags** and I collapsed them:

| Lag | Source | Varies? |
|---|---|---|
| `recruit_lag` = 3 | biology: spawned fall t−3, counted age-2 at t | no, all sites |
| `flow_lag(site)` | **IPM indicator-variable selection** | **yes** — Norris 3, BigHole.Melrose 2 |

Session 5 argued the water-year axis made `FLOW_LAG` unnecessary. That argument
only holds if the flow lag always equals the recruit lag. It does not — it is a
model-selection result that encodes a different biological hypothesis per site:
`flow_lag == recruit_lag` is spawning-year conditions, `flow_lag < recruit_lag`
is age-0 rearing-year conditions.

### `[FINDING]` Lags 2 and 3 coincide on the same water year — which is why Norris looked correct
Recruit year 2000, recruit lag 3:

| flow_lag | mechanism | calendar yr | active months | water year |
|---|---|---|---|---|
| 3 | spawning | 1997 | Oct–Nov | **1998** |
| 2 | age-0 rearing | 1998 | Mar–Sep | **1998** |
| 1 | age-1 | 1999 | Mar–Sep | **1999** |

Water year 1998 spans Oct 1997 – Sep 1998, so it contains *both* mechanisms. The
old hardcoded `recruit_year - REC_LAG + 1` therefore returned the right answer at
Norris (3) **and** at BigHole.Melrose (2) — by coincidence of those two values,
not by design. A site selecting lag 1 or 4 would have been silently wrong, and
nothing in the code recorded which lag any site used.

### `[CHANGE]` `config.R` — `flow_lag()` and `flow_water_year()`
`flow_lag()` is an explicit `switch()` per site (Norris 3, BigHole.Melrose 2,
others to be confirmed from each `_RecLagInclusionProbQuad.csv`).
`flow_water_year()` converts a calendar lag to the water-year axis with the
offset that depends on which months carry the mechanism:

```r
recruit_year - L + if (L >= rec_lag) 1L else 0L
```

Spawning is in Oct–Nov of the lag year, which falls in the *following* water year
(+1); rearing is in Mar–Sep, already inside that water year (0).

### `[CHANGE]` Downstream
- `01_build_response.R` — computes `flow_water_year`, saves it plus `flow_lag`, and **prints the actual calendar span covered** so a one-year error is visible rather than inferred. Warns when the flow lag differs from the recruit lag.
- `03_fit_beta_recruitment.R` — joins on `flow_water_year`; carries `flow_lag` into the fit object.
- `09_figures.R` — records `flow_lag_<site>` in `derived_stats.csv`.
- `00_config.R` — startup report prints each site's flow lag and which mechanism it implies.
- `methods.Rmd` — states that the hydrograph year is *not* assumed to be the spawning year, explains the coincidence at lags 2 and 3, and reads the per-site lag from `derived_stats.csv`.
- `spawn_water_year` fully retired; no stale references remain.

### `[OPEN]` Confirm the flow lag for the remaining 12 sites
`flow_lag()` currently has Norris = 3, BigHole.Melrose = 2, Jefferson.Waterloo = 3
(**placeholder**), default 3. Each needs its value from that site's
`_RecLagInclusionProbQuad.csv`. The startup report prints what is in use.

### `[OPEN]` Any site with flow lag outside {2, 3}
The mapping is implemented generally, but only lags 2 and 3 have been checked
against the biology by hand. A site selecting lag 1 or 4 should have its printed
calendar span verified before the results are used.

---

## 2026-07-29 — Session 14: check_setup.R run; three separate causes

Andrew ran `check_setup.R`. It reported failures in sections 5, 6 and 7. **Two of
the three causes were bugs in my checker, not in the pipeline.**

### `[FINDING]` 1. Wrong path prefix — the only real blocker
Project root is `/Users/ablahr/Documents/DroughtTrout/WH_BOR_Trout`, i.e. this
project sits **inside** DroughtTrout, not beside it as I had assumed. So
`"../DroughtTrout/LL/..."` resolved to `DroughtTrout/DroughtTrout/LL/...`.

The tell was that `params_path()` **worked** — it uses `"../LL/..."` because it was
transcribed from Andrew's original code — while every `CFG$paths` entry failed.
Years read fine (1980–2025, 46 years); posterior and flow did not.

Fixed: all five `CFG$paths` entries now use `"../LL/"`, matching `params_path()`.
The layout is documented in `config.R` with a note that the two must be changed
together.

### `[FINDING]` 2. Section 6 regex left a trailing quote — every FAIL was false
```r
srcd <- regmatches(x, gregexpr('source\\(here::here\\("R", "[^"]+"', x))[[1]]
srcd <- sub('.*"R", "', "", srcd)     # -> 'fn_fit_beta.R"'  <- trailing quote
```
`"fn_fit_beta.R\"" %in% "fn_fit_beta.R"` is FALSE, so **every script that
genuinely sourced the file was reported broken**. Scripts that passed did so only
because they call none of the shared functions.

A checker that cries wolf is worse than no checker — it trains you to ignore it.
Fixed with `regexec()` and a capture group. Verified: all 11 pipeline scripts pass.

Second bug in the same section: the file filter `"^[0-9]"` matched any file
starting with a digit, including a stray `.md` in `R/`. Now `"^[0-9].*\\.R$"`.

### `[FINDING]` 3. Stale files in `R/` from earlier sessions
Section 6 output revealed `03_fit_beta_recruitment (1).R`, `03_fit_recruitment.R`,
`04_validate.R`, `05_project_scenarios.R`, `06_figures.R`, and `00_SCRIPT_MAP.md`
— leftovers from the seasonal-only design and from a re-download.

Harmless to execution (`RUN_ALL.R` sources by name) but they are scanned by the
checks, which is where the `CFG$posterior$years_from` and `CFG$posterior$params`
failures in section 5 came from: **dead code, not live**.

### `[CHANGE]` Checker improvements
- **Section 5** now names the FILE each unresolved reference came from, and skips comment lines. A reference inside a comment is documentation, not a dependency.
- **Section 6** regex and file filter fixed.
- **Section 6b (new)** lists files in `R/` that are not part of the pipeline.
- **`.diagnose()` in `00_config.R`**: a missing path now walks up to the deepest existing folder and lists its contents. That distinguishes "wrong prefix" (nothing familiar) from "wrong filename" (folder full of near-misses) immediately — it is how this session's path bug was identified.

### `[CHANGE]` `docs/notes/CLEANUP_R_FOLDER.md`
Which files to keep, which to archive, and how to diff the `(1)` duplicate before
deleting it.

### `[OPEN]` Filenames still unverified
With the prefix corrected, confirm these two exist:
- `../LL/JAGS_PVA/ModelFits/Madison.Norris_IndicatorVarSel_NullMod_Apr26_02.rds`
- `../LL/imputed_output/Madison.Norris_imputed.csv`

If the folder now resolves but the file does not, `.diagnose()` will list what is
actually in it and the filename pattern in `config.R` can be adjusted.

---

## 2026-07-29 — Session 14: fpc component-selection rule; reporting-layer audit

### `[CHANGE]` `fpc_rule` added: "cumulative" | "individual" | "both"
`config.R` gains `fpc_rule` and `fpc_min_var` (default 5). The rule decides K:

| Rule | K |
|---|---|
| `cumulative` (default, unchanged) | first index where cumulative variance ≥ `fpc_target_var` |
| `individual` | count of components each ≥ `fpc_min_var` |
| `both` | the smaller of the two |

Threaded through `00_config.R` (`FPC_RULE`, `FPC_MIN`) to scripts 03, 04 and 05,
including inside CV folds so selection is re-done per fold and the folds score the
whole procedure.

### `[FINDING]` A 5% individual threshold makes the rank-K problem worse, not better
Counterintuitive and worth recording. `Vbeta = Φ Vb Φᵀ` has rank K, so cutting K
from ~10 to ~4 means script 06 simulates curves in a 4-dimensional space. **Best-day
intervals get narrower while becoming less trustworthy** — truncation uncertainty
is still absent, now over a smaller basis. Anyone reading tighter intervals as
better precision would be reading an artefact.

Also recorded: at Norris `edf = 10.00` exactly, i.e. K hit `fpc_max`. The cumulative
rule wanted more than 10 components, so the spectrum decays slowly and a 5% floor
would likely cut K to 3–5 — a large change, not a trim.

### `[CHANGE]` Two new guards in `.fit_beta_fpc()`
- `K_capped` — TRUE when `fpc_max` or *n* bound K instead of the variance rule. Without it, tuning `fpc_target_var` or `fpc_min_var` silently does nothing.
- `K_unstable` — TRUE when a component sits within 0.5 percentage points of the threshold. A hard threshold creates a discontinuity, so such a component flips in and out between CV folds and makes CV noisier than it appears.

Both surface as warnings in script 03 and columns in `derived_stats.csv`.

### `[FINDING]` `methods.Rmd` hardcoded the P-spline description
The worst gap found. Switching to `estimator = "fpc"` would have produced a
Methods section describing a model that was never fitted — and it would read as
correct to anyone who did not open `config.R`. The estimator paragraph now
branches, reports K and the rule actually used from `derived_stats.csv`, and for
the fpc arm states the unsupervised-selection caveat and the rank-K covariance
limitation explicitly.

### `[FINDING]` `derived_stats.csv` recorded no estimator settings
It is meant to be the single source of truth for quoted numbers, but nothing in it
said which estimator or rule produced them. Now records `estimator`, `fpc_rule`,
`fpc_target_var`, `fpc_min_var`, `fpc_max`, `compare_estimators`, plus per-site
`fpc_K_*`, `fpc_var_explained_*`, `fpc_K_capped_*`, `fpc_K_unstable_*`.

### `[FINDING]` `%||%` missing from `manuscript/_common.R`
`_common.R` sources `config.R` but not `R/00_config.R`, by design — the pages must
render from the config plus saved output without re-running startup checks. But
that left `%||%` undefined, and the new branching Methods chunk needs it. Added
locally.

### `[FINDING]` Andrew's `RUN_ALL.R` query — both tables DO exist
`gate.csv` is written at `05_validate.R:327`, `best_day_intervals.csv` at
`06_daily_sensitivity.R:342`. The messages were accurate. Added two more pointers:
`decision_window_schedule.csv` (the operational deliverable) and
`derived_stats.csv`.

### `[OPEN]` Decide the rule empirically, not by argument
`R/diag_fpc_truncation.R` writes `fpc_diagnostics_rules.csv` comparing K under all
three rules, plus the discarded-component test and the K sweep. If PCs beyond the
5% cut carry no incremental prediction, the floor is free; if they do, it deletes
signal. Neither threshold is defensible if the peak day wanders across the sweep.

---

## 2026-07-29 — Session 13: config migration fallout repaired

### `[FINDING]` The YAML migration silently deleted three things from `00_config.R`
The regex used to rewrite `site_years()` matched greedily and removed the whole
function rather than replacing its body. The same edit dropped the shared plot
style. Lost:

| Symbol | Consequence |
|---|---|
| `site_years()` | Startup check errored — the symptom Andrew hit |
| `PAL`, `theme_wh` | **Every figure-producing script (01–09, 06b, diag) would have failed** |
| `WY_BREAKS`, `WY_LABELS` | Month axes on all water-year plots |
| `K_BETA` | Scripts 03, 04, 05 |

Only the first announced itself. The rest sat downstream of a working
`00_config.R` and would have surfaced one script at a time.

### `[CHANGE]` Audit method changed from spot-checking to enumeration
Rather than reading scripts looking for problems, extracted **every symbol each
script references** and diffed against **every symbol the config layer defines**.
That is what surfaced `PAL`/`theme_wh`, which no amount of reading `00_config.R`
would have caught, because the omission was invisible there.

A second scan checked every *function call* in every script against base R, the
attached packages, locally defined functions, and the config layer. Two real
findings among the comment-text noise:

- `06b_decision_window.R` called `date_of()` which it defined, but the sibling
  `mon_of()` was missing. Both now alias the shared `wday_date()` / `wday_month()`
  from `00_config.R`, so a date cannot be formatted two ways in two figures.
- `explain_methods_figures.R` referencing `fit_penalized_beta` — comment text
  only, function is defined locally. No action.

### `[CHANGE]` `wday_date()` / `wday_month()` promoted to `00_config.R`
Previously duplicated in `06b` and `manuscript/_common.R`. `_common.R` keeps its
own copy deliberately: it sources `config.R` but never runs `00_config.R`, so it
must stand alone when knitting a single `.Rmd`.

### `[FINDING]` `WY_B`/`WY_L` vs `WY_BREAKS`/`WY_LABELS` naming split
The `explain/` and `diag` scripts use the short names; the pipeline uses the long
ones. Rather than renaming across a dozen files, `00_config.R` now defines both,
with the short ones as aliases.

---

## 2026-07-29 — Session 13: post-migration audit; two real breaks found

### `[FINDING]` Two genuine bugs from the config.R migration
Andrew hit `could not find function "site_years"` and asked for a full downstream
audit. The audit found:

1. **`R/06_daily_sensitivity.R` called `simulate_beta()` without sourcing it.**
   When `simulate_beta()` moved into `fn_fit_beta.R` in Session 9, script 06 kept
   the call but never got the matching `source()` line. Invisible until script 06
   actually runs — several minutes in, after 01–05 have written output.
2. **Stale startup message** naming `posterior.params`, a YAML key deleted in
   Session 12.

Also repaired an error message in script 01 still directing readers to
`posterior.params.model_filter` and `posterior.params.year_from_name` instead of
`params_filter()` and `params_year_name` in `config.R`.

### `[FINDING]` What the audit cleared
- All 94 `CFG$group$key` references resolve against the new list — verified by static scan, not by eye.
- No remaining `site_file()`, `years_from`, `yaml::`, or `config.yml` references in code.
- Every project function called is reachable from that script's `source()` lines.
- All files balance on parens, braces and brackets.
- The `first_year + seq_len()` hits in 01 and 04 are the intended guarded fallbacks, not leftovers.

### `[CHANGE]` `check_setup.R` — preflight verification
Seven sections, about one second, no data required: packages, files present,
every script parses, config loads and exports what it should, every referenced
`CFG` setting exists, `source()` lines match function use, and data inputs
(reported but not fatal, so the code can be checked on a machine without the
data folder mounted).

**Section 6 is the one that would have caught the `simulate_beta()` bug.** It
maps shared functions to their defining file and flags any script that calls one
without sourcing it.

Run it after any edit to `config.R`, `R/00_config.R`, or `R/fn_fit_beta.R`.

### `[OPEN]` `simulate_beta()` reads fields the fit objects must carry
It expects `beta_draws`, `Vbeta`, `scale_draws`, `scale_ref`. Scripts 03 and 04
build these, but `check_setup.R` cannot verify them without running the pipeline
— they are only checkable once `beta_recruitment.rds` exists. If script 06 fails
on a missing field, that is where to look.

---

## 2026-07-29 — Session 13: post-migration audit

### `[FINDING]` `%||%` was lost in the YAML removal — the one real break
`06b_decision_window.R` uses it seven times for setting defaults and would have
failed on its first line of real work. It had been defined inside the block that
parsed `config.yml`, and went with it. Restored near the top of `00_config.R`,
before first use, rather than at the foot of a file relying on lazy lookup.

### `[FINDING]` The reported `site_years` error was a STALE FILE, not a missing function
`site_years()` is defined at line ~112 and called at ~203, and the load order
verifies. The error came from an older `00_config.R` still in the session — one
whose `site_years()` referenced `CFG$posterior$params`, which no longer exists in
the plain-R config. Inside `tryCatch` that surfaced as a per-site `[ERROR]` line
that looked like a data problem.

Two guards added so this cannot recur silently:
- `CONFIG_VERSION` stamp in `00_config.R`, to compare against the repository copy.
- The startup check now **hard-stops** if `params_path()`, `params_filter()` or `site_years()` is absent, telling you to restart R, instead of catching it per site.

**Practical note: `source()` does not clear the previous definitions.** After
editing config files, *Session → Restart R* before re-sourcing.

### `[CHANGE]` Full downstream audit performed
Checked every script against what `config.R` + `00_config.R` provide:

| Check | Result |
|---|---|
| Config symbols used but not provided | Only `%||%` — fixed |
| Every script sources `00_config.R` | All 11 ✓ |
| Scripts using `fit_beta_curve`/`simulate_beta` source `fn_fit_beta.R` | All 6 ✓ |
| `RUN_ALL.R` steps exist on disk | All 10 ✓ |
| `.rds` handoffs between scripts | All 10 objects consistent |
| Bracket balance, all R files | Clean |
| Rmd chunk fences | All 4 balanced |
| Stale `site_file()` / `yaml::` / `years_from` | None outside historical comments |

### `[CHANGE]` `check_setup.R` added at the project root
Runs in about a second, needs no data, and verifies: package availability, config
loads, required objects and functions exist, paths resolve, params CSVs parse and
yield years, and every pipeline file is present. Catches the class of failure that
otherwise appears halfway through a run.

---

## 2026-07-29 — Session 12: config.yml replaced with plain R

### `[DECISION]` YAML dropped. `config.R` is now the single settings file.
Andrew's call, and the right one — I should have offered it rather than defending
YAML. The case for a data-format config is that non-programmers edit it or a
second language reads it. **Neither applies here.** What YAML actually bought was
a whitespace-significant language with no syntax checking in the editor and error
messages carrying no line numbers, which cost an hour to a duplicate-key failure
caused by one lost indent level.

`config.R` gives syntax highlighting, autocomplete, line-numbered errors, and
lets site quirks be ordinary `switch()` branches — which is what they were in the
original code and should have stayed.

### `[DECISION]` The `CFG` list structure is unchanged
94 references to `CFG$...` across 10 groups exist downstream. `config.R` builds
**the identical nested list**, so not one of them needed editing. The R literal
was generated from the YAML programmatically rather than retyped, so no value
could drift in translation.

### `[CHANGE]` Site paths are now three readable functions
Replaces `site_file(site, "posterior_dir", "posterior_pattern")` and the
`posterior.params.overrides` blocks:

- `posterior_path(site)`
- `flow_path(site)` 
- `params_path(site)` — a `switch()` with the Jefferson branch
- `params_filter(site, d)` — an `if()` with the BigHole lag-column branch

Adding a normal site needs no code at all; an odd one needs a `switch()` branch.
Compare with the YAML version, where the same thing required a correctly indented
nested override block and failed silently on a mis-paste.

### `[CHANGE]` Files touched
`config.R` (**new**), `config.yml` and `config_posterior_block.yml` (**deleted**),
`R/00_config.R`, `R/01`, `R/02`, `R/04`, `R/07`, `R/08`, `manuscript/_common.R`,
`manuscript/results_by_site.Rmd`, `manuscript/results_among_sites.Rmd`,
`render_site.R`, `README.md`, `docs/notes/FILE_MAP.md`,
`docs/notes/PROJECT_STRUCTURE.md`, `docs/GITHUB_PAGES.md`.

The `yaml` package is no longer a dependency.

### `[FINDING]` `manuscript/_common.R` was still parsing config.yml
Caught on the final sweep. Deleting `config.yml` without this fix would have
broken every page of the website at render time — and only at render time, well
after the analysis appeared to be working.

### `[CHANGE]` `posterior$years_from` removed
With `params_path()` explicit and readable, the "params_csv vs first_year" switch
was redundant. `site_years()` always reads the CSV and falls back to `first_year`
with a loud warning if it is missing.

---

## 2026-07-29 — Session 11: calendar years read from the params CSVs

### `[DECISION]` `posterior.first_year` replaced by year extraction; kept only as a fallback
Rolling out to 13 more sites made the hardcoded start year untenable. Years now
come from the JAGS parameter CSVs, reproducing the old extraction
(`filter(name == 'Estimated NAdults') %>% pull(Year) %>% unique()`).

**This is not just convenience — it turns an unverifiable assumption into a
check.** `first_year` gave only a start; the CSV gives the start *and the count*,
so scripts 01 and 04 now **stop** if the year count disagrees with the posterior's
column count. A wrong start year shifts every lag by a full year and is invisible
in the results, so this closes the highest-risk silent failure left in the design.

### `[CHANGE]` `config.yml` — `posterior.params` with per-site overrides
All three site-specific behaviours from the old code are now config, not code:

| Old special case | Now |
|---|---|
| Two directories (LL vs Jefferson) | `dir` default + `overrides.Jefferson.Waterloo.dir` |
| Two filename patterns | `pattern` with `<STREAMSECTION>` (site name, dot removed) |
| `BigHole.Melrose` filters on `SummerLag == 2 & WinterLag == 2` | `overrides.BigHole.Melrose.filter_cols` |

`filter_cols` is declarative column == value pairs rather than an eval'd
expression, so a config file cannot execute arbitrary code. Adding a site is a
config edit; only the keys that differ need to be given.

### `[CHANGE]` `R/00_config.R` — `site_years()` plus a per-site startup report
`source("R/00_config.R")` now prints OK / MISSING / ERROR and the year range for
every active site. Scaling to 14 sites, that is where a misconfigured site
announces itself — immediately, rather than three scripts later as a shifted lag.

### `[FINDING]` `04_fit_beta_survival.R` was still building years from `first_year`
Caught while checking downstream consistency. Had it shipped, script 01 would have
used real years and script 04 assumed ones, putting the recruitment and survival
arms on **different calendars** — every survival lag offset against every
recruitment lag, with nothing anywhere complaining. Both now call `site_years()`
and both hard-error on a count mismatch.

### `[CHANGE]` Gaps in the year record are now handled rather than assumed away
The old `years[(REC_LAG + 1):nyr]` silently assumed contiguity. Recruit years are
now matched to spawning years explicitly, so pairs straddling a missing year are
dropped and counted rather than mis-paired. `site_years()` reports gaps at load.

### `[CHANGE]` Provenance recorded
`response.rds` stores `years_all` and `years_source` (the CSV path, or
"first_year (assumed)"), so a saved fit can be audited without re-deriving where
its calendar came from.

### `[OPEN]` Add an `overrides` block per site as you roll out
Only `Jefferson.Waterloo` and `BigHole.Melrose` are configured. Any site whose
CSV lives elsewhere, uses a different filename, or needs a different row filter
needs a block. The startup report will tell you which.

---

## 2026-07-29 — Session 10: decision-window section added to the site

### `[CHANGE]` `manuscript/results_by_site.Rmd` — new section 3.4
Sits between "where to put a fixed volume" (3.3, unconstrained) and
"whole-population production" (now 3.5), because it is the constrained version of
the same question. Contents:

- the window definition, read from `config.yml`, with a note when it wraps the 1 October boundary
- **06b-f** curve across the season with baseline discharge on the right axis
- **06b-g** best feasible day + the cost table
- **06b-h** every feasible schedule scored
- **06b-i** benefit forgone, with prose that branches on how flat the surface is

### `[DECISION]` Two passages branch on the result rather than being written once
**`frac_retained`** produces one of three framings: constraint close to free
(≥ 90%), costs something real (50–90%), or *the biology wants water when the
allocation system cannot deliver it* (< 50%). The third case is written as an
abstract-worthy finding, because it points at changing the rules about when water
can be re-timed rather than at buying more of it — a different intervention
entirely.

**Flatness of the benefit surface** produces: timing is not the binding decision /
matters moderately / is the binding decision. The first case is the one most
easily missed, and it is *good news* for a water user — release when it is
operationally easiest rather than negotiating for a date. Plotting only the
optimum hides it completely.

A gate warning renders at the foot of the section if any curve failed script 05.

### `[FINDING]` `FIG()` would have published a site with broken images
`render_site.R` copies figures into `manuscript/figures/`, but `FIG()` resolved an
absolute path into `output/figures/`. That works when knitting a single `.Rmd`
locally and fails silently once `_site/` reaches `gh-pages`, because `output/` is
git-ignored and never gets there. The site would have looked correct on the
machine that built it and broken everywhere else.

Fixed: `FIG()` prefers the relative copy, falls back to the absolute path **with a
warning**, and still degrades to "Figure not available" if neither exists.

---

## 2026-07-29 — Session 9: allocation-season analysis added

### `[DECISION]` The decision window is a constrained optimisation, not a zoom
Water allocation happens roughly May–October (ramp-up to ramp-down). Restricting
to it changes four things, not just the axis limits:

1. **The best feasible day is an argmax over a subset** and can differ from the global optimum.
2. **Its interval must be recomputed within the subset.** Truncating the unconstrained interval is wrong: a simulation whose global peak fell in March does not drop out, it *relocates* to its best feasible day, and where it relocates to is information.
3. **Volume-release starts must be restricted so the whole window fits inside the season** — a 60-day release starting late September would otherwise spill past ramp-down.
4. **A new quantity script 06 never computed: what the constraint costs.** `frac_retained` = benefit at the best feasible day ÷ benefit at the unconstrained optimum. If it is low, the biology wants water at a time no allocation mechanism can deliver — which is itself a finding worth reporting.

### `[FINDING]` The window wraps the water-year boundary
May 1 is water-year day 213; October 31 is day 31. The allocation season is
therefore *not* a contiguous range on the analysis axis. `06b` builds an ordered
`dec_idx` and plots on a `pos` axis so the figures read May → October
contiguously. Windows are specified as calendar month-day in `config.yml` and
converted internally.

### `[FINDING]` 1/Q leverage is strongest exactly inside this window
Baseline discharge falls sharply from the snowmelt peak to autumn base flow, and
benefit per cfs scales as 1/Q. So the best day to *release* can sit well after
the peak of β(t), and the gap between them is the actionable part. Figure 06b-f
plots both on one panel with discharge on the right axis so they cannot be
confused.

### `[CHANGE]` Files
- `R/06b_decision_window.R` — **new**. Four figures, three tables.
  - `06b_f` curve across the season with the 1/Q driver overlaid
  - `06b_g` best feasible day + cost of the constraint
  - `06b_h` every feasible schedule scored (start × duration heatmap)
  - `06b_i` benefit forgone relative to optimal — **tells a water user whether timing is worth negotiating over**, which a plot of the optimum alone hides
- `R/fn_fit_beta.R` — `simulate_beta()` moved here so 06 and 06b share one definition
- `R/06_daily_sensitivity.R` — sources the shared file instead of defining it
- `config.yml` — `decision_window: start/end/label`
- `RUN_ALL.R`, `manuscript/_common.R` — wired

### `[OPEN]` Figure 06b-i may be the most important one
If the benefit surface is flat across the season, timing is nearly irrelevant and
the operational message is "release when it is easiest" — which is a *better*
outcome for a water user than a sharp optimum, and is easy to miss when only the
optimum is plotted. Worth checking before any briefing.

### `[OPEN]` `results_by_site.Rmd` does not yet include a decision-window section
Data is exposed in `_common.R` as `DW`, `DWDAY`, `DWCOST`, `DWSCH`.

---

## 2026-07-29 — Session 8: survival arm silently NaN — root cause found

### `[FINDING]` One bug, four steps, surfacing far from its cause
Survival validation died with
`arguments imply differing number of rows: 1, 0`. Andrew's instinct that `cv_one()`
was responsible was correct. The chain:

1. `05_validate.R` passed `sz <- rep(0, length(y))` for survival, because survival
   genuinely has no stock covariate — density is already removed when the process
   deviate is built.
2. A constant column is **rank deficient**. `lm()` returns `NA` for its
   coefficient rather than erroring.
3. `cv_one()` computed `cf["S_z"] * stock_z[te]`. In R, `NA * 0` is `NA`, so every
   prediction in every fold became `NA`, `is.finite(pred)` was all `FALSE`, and
   `r2()` received two empty vectors and returned `NaN`. **Nothing errored.**
4. Every permutation replicate returned `NaN` too, so `nr <- nr[is.finite(nr)]`
   filtered to `numeric(0)`, and
   `data.frame(..., null_r2 = numeric(0))` threw — naming the `data.frame` call
   but not the empty column.

The error appeared four steps downstream of the cause, in a different object,
with a message that pointed at neither. Textbook silent failure: the zeroing
looked harmless, and R's `NA` propagation carried it invisibly.

### `[CHANGE]` `R/05_validate.R`
- `cv_one()` takes `stock_z = NULL` and drops the term entirely rather than zeroing it; `use_stock` also rejects any constant column defensively.
- Caller passes `NULL` for survival, not `rep(0, n)`.
- `sp_use` guard: an fpc fit returns `sp = NA_real_`, and handing that to `gam()` for the penalized comparison arm is undefined. `NULL` means "estimate it".
- `cv_one()` returns `NA_real_` with a **warning** when no fold scores, and warns when fewer than half score. It no longer returns `NaN` quietly.
- `.one()` helper converts any missing or wrong-length fit field to `NA` and names it, so a stale fit object cannot reproduce this class of cryptic error.
- Empty null distributions are skipped with a warning instead of thrown.

### `[FINDING]` Norris recruitment gate, first full run
```
beta:fpc         blocked R2 = +0.043   LOO = +0.112   p = 0.068   PASS
beta:penalized   blocked R2 = -0.019   LOO = +0.161   p = 0.182   fail
seasonal         blocked R2 = -0.063   LOO = +0.152   p = 0.227   fail
```
The two estimators **disagree**, which by the standard set in Session 6 means no
daily recommendation is defensible at this site: fpc clears the gate, penalized
and the seasonal anchor do not. `edf = 10` is the cap (`fpc_max`), so the FPC arm
is running at maximum flexibility — worth checking whether the gate result
survives `K < 10` via `R/diag_fpc_truncation.R`.

Also note LOO exceeds blocked for all three arms, by 0.07–0.21. That gap is the
autocorrelation leak the blocked design exists to remove.

---

## 2026-07-29 — Session 7: FPC-only reviewer exposure assessed

### `[FINDING]` Two objections attack the paper's novel claims directly
Asked what reviewers would say to `estimator = "fpc"` alone. Most FPC critiques
are generic; **two are specific to this design and land on the headline results**:

1. **Cross-site basis incomparability (kills RQ2 as written).** FPCA runs per site,
   so eigenfunctions differ between sites and β(t) curves live in different spaces.
   "Does the same feature recur across independent populations" then confounds
   biology with basis similarity — two sites with similar hydrology get similar
   eigenfunctions and look alike regardless of the fish. The penalized arm has no
   such problem: one B-spline basis everywhere.

2. **Rank-K covariance (kills RQ1's precision claim).** `Vbeta` excludes truncation
   uncertainty, so simulated curves cannot take shapes outside the K retained
   components — best-day intervals are anticonservative, structurally rather than
   by degree, and will not narrow with more data at fixed K.

### `[CHANGE]` `docs/notes/FPC_reviewer_critiques.md`
Eight anticipated critiques with the reviewer's own phrasing, an honest fairness
assessment, and concrete pre-emptions. Also states the defensible case *for* FPC:
continuity with the weighted-hydrograph literature and the coworker's BoR scripts,
no smoothing parameter to justify, and η guaranteed to be a realizable flow
contrast.

### `[CHANGE]` `R/diag_fpc_truncation.R` — three pre-submission checks
- **Discarded-component test.** Regress the response on the components truncation
  threw away; F-test the incremental fit. If they carry nothing, truncation was
  harmless *in this data*, whatever the general theory says. Highest-value check
  here — converts a structural objection into a settled empirical question.
- **K sensitivity sweep.** Peak day across K = 3…10. If it moves more than ~45
  days, there is no daily claim to make.
- **Cross-site basis alignment**, plus it writes `fpc_common_basis.rds` — a pooled
  common eigenfunction basis, which is the fix for objection 1.

### `[DECISION]` Recommendation stands: keep both arms
`compare_estimators: true` costs seconds and makes objections 1, 2, 4 and 5 moot
in one move. "Both a smoothness prior and a flow-variance prior place the optimum
in the same window" cannot be attacked on estimator grounds.

If FPC-only is chosen anyway, three things must happen **before** submission, none
of which is small enough to do during revision: common cross-site basis, block
bootstrap over the full procedure for best-day intervals, and the discarded-
component plus K-sweep diagnostics.

### `[OPEN]` Functional PLS not addressed in Methods
A methods-literate reviewer will ask why unsupervised truncation rather than
components selected by covariance with the response. Reiss & Ogden (2007) *JASA*
102:984–996. No need to use it, but Methods should say why not.

---

## 2026-07-29 — Session 6: FPC estimator restored as a second arm

### `[DECISION]` Both estimators are fitted and gated; `penalized` stays primary
`fn_fit_beta.R` now dispatches on `estimator = "penalized" | "fpc"` with an
identical return structure, so scripts 03–06 needed no structural change. Set in
`config.yml` (`fitting.estimator`), with `fitting.compare_estimators: true`
running the other arm through the same folds and the same permutation nulls.

**Rationale for keeping `penalized` primary is specific to the daily deliverable,
not a general preference.** Three reasons, in order of weight:

1. **Eigenfunctions are global.** φ₂ onward oscillate across all twelve months, so
   a coefficient fitted because of a real August effect also moves β(t) in
   December and March. For a "which day should I release" recommendation an
   apparent optimum can sit on eigenfunction geometry rather than signal.
2. **The FPC covariance has rank K.** Curves simulated from it can only take
   shapes the K retained components can make, so truncation uncertainty is
   absent and best-day intervals come out **too narrow**. Script 06's whole
   resolution machinery depends on an honest covariance.
3. **Truncation selects on the wrong criterion.** Components are ranked by flow
   variance and then tested against recruitment. A mode with little flow variance
   can still be the one fish respond to, and truncation *deletes* rather than
   shrinks it (Jolliffe 1982, Applied Statistics 31:300–303).

### `[DECISION]` Agreement between estimators is the reporting standard for daily guidance
Where the two priors put the peak in the same place, the result does not depend on
which prior was chosen — stronger evidence than either estimator's own interval,
because it survives a change of assumption rather than assuming one. Where they
disagree, the daily structure is supplied by the estimator and **no daily
recommendation is defensible**. This is now the stated criterion.

### `[FINDING]` A likely explanation for the old fpc arm's apparent skill
`.fit_beta_fpc()` re-selects K from the training years **inside every CV fold**,
so folds score the whole procedure including selection. The old pipeline chose
`n_fpc` once on the full record and reused it inside folds — a leak that inflates
apparent skill, and a plausible reason the old fpc arm scored cv_R² = +0.126 under
leave-one-out and collapsed under blocked CV.

### `[CHANGE]` Files touched
- `R/fn_fit_beta.R` — dispatcher + `.fit_beta_penalized()` + `.fit_beta_fpc()`
- `config.yml` — `estimator`, `compare_estimators`, `fpc_target_var`, `fpc_max`
- `R/00_config.R` — exposes `ESTIMATOR`, `COMPARE`, `FPC_VAR`, `FPC_MAX`
- `R/03`, `R/04` — pass the estimator through
- `R/05_validate.R` — `cv_one()` gains `est`; scores both β arms; `form` column now `beta:penalized` / `beta:fpc` / `seasonal`
- `R/explain/explain_estimator_choice.R` — **new**, 5 teaching figures

### `[OPEN]` Downstream columns changed
`gate.csv` `form` values are no longer `"beta"`. `manuscript/_common.R::GATE_OK()`
defaults to `form = "beta"` and will need `grepl("^beta", form)` or an explicit
estimator argument. Check before rendering the site.

### `[OPEN]` Worth considering later, not now
If the fpc arm outperforms, the reason is likely that the leading flow modes
happen to align with the biology — in which case **functional PLS** (components
chosen by covariance with the response rather than variance of the predictor)
is the principled version and fixes objection 3 directly. Reiss & Ogden (2007),
*JASA* 102:984–996. Not worth building until the gate says one arm wins.

---

## 2026-07-29 — Session 5: functional β(t) restored; pipeline rebuilt around three research questions

### `[DECISION]` The 365-point curve is the primary estimand; seasonal windows become the confirmatory anchor
Overrules Session 4's simplification. The reason is a project goal I had
underweighted: the deliverable includes **daily guidance for water managers and
leased-water holders** — which day does an acre-foot buy the most trout. A
four-window model cannot answer that; it can only say "summer matters."

Both models are now fitted on identical folds with identical permutation nulls,
with explicit roles:
- **functional β(t)** — descriptive and management layer (RQ1, RQ2), at whatever resolution the data support
- **four seasonal windows** — confirmatory layer and the gate (4 df, real power)

If they disagree, the seasonal model wins on inference and β(t) describes
structure *within* a window the seasonal test established.

### `[FINDING]` β(t) is not the curve a water manager needs — this is the key result
Standardization is `x(t) = (log Q(t) − ch(t)) / σ`, so β(t) is the effect of a
one-SD standardized log anomaly. Managers release cfs. Adding ΔQ on day t gives

    Δη(t) = β(t) · log(1 + ΔQ / Q̄(t)) / σ   ≈   β(t) · ΔQ / (σ · Q̄(t))

**Benefit per cfs is β(t) divided by that day's baseline discharge.** Ten cfs on a
150 cfs September baseflow is +6.5%; the same ten cfs on a 2,000 cfs June peak is
+0.5%. Thirteen-fold difference for identical water. The management curve can
therefore peak on entirely different days than β(t).

This falls straight out of the model structure, is directly actionable, and yields
a testable cross-site prediction: smaller streams should show larger benefit per
cfs. Tested in `results_among_sites.Rmd` §4.

### `[DECISION]` Resolution is reported, not hidden
A penalized curve with effective df `edf` over 365 days resolves roughly `365/edf`
days — at edf ≈ 4, about 90 days. So no single date is defensible. Script 06
simulates β(t) from its full covariance and reports the **distribution of the best
day**, plus a credible window. If the window spans most of the year it says so and
refuses to name a day.

Two supporting choices: **contrasts, not overlapping CIs** (adjacent days are
strongly correlated, so `Var(β(t₁) − β(t₂)) = V₁₁ + V₂₂ − 2V₁₂` can be far smaller
than either variance alone), and **simultaneous rather than pointwise bands** when
pointing at a peak.

### `[DECISION]` Production is derived, not fitted
Recruitment and survival are the two processes with data. Production is a
consequence, obtained by perturbing flow in a day-block and measuring ΔSP through
the IPM forward simulation under common random numbers (`07_production_sensitivity.R`,
73 five-day blocks). This automatically handles compounding — a survival gain
raises spawners, which feeds the Ricker three years later — which a third
regression would not.

### `[CHANGE]` Pipeline is now nine scripts
`00_config`, `fn_fit_beta`, `01_build_response`, `02_build_flow`,
`03_fit_beta_recruitment`, `04_fit_beta_survival`, `05_validate`,
`06_daily_sensitivity`, `07_production_sensitivity`, `08_scenarios_bor`,
`09_figures`.

Count rose from six because three response processes and a daily deliverable were
added, not because structure regressed. Still down from eighteen, and every script
has one job.

### `[CHANGE]` Website and publishing
`manuscript/` holds `index.Rmd`, `methods.Rmd`, `results_by_site.Rmd` (RQ1, RQ3)
and `results_among_sites.Rmd` (RQ2), sharing `_common.R` so every number is read
from `output/` and missing inputs render as NOT AVAILABLE.

`render_site.R` builds `_site/`; `publish_site.sh` pushes it to `gh-pages` via a
git worktree. **Rendering is local by necessity, not preference:** the `.Rmd`
files read `output/`, which is git-ignored, so GitHub Actions would find nothing
to render.

### `[OPEN]` The life-history timeline in `R/09_figures.R` is a placeholder
The RQ2 alignment test compares β(t) against known spawning, incubation,
emergence, and rearing timing. **That timeline must come from the literature and
be fixed before looking at β(t)** — setting it afterwards guarantees agreement and
proves nothing. Currently a stub that needs editing and citing.

### `[OPEN]` Site-level covariates for RQ2 §4
Regulation degree, elevation, thermal regime, baseline discharge, confinement,
diversion records. None is in the data folder. Fourteen sites supports one,
possibly two — pick on mechanistic grounds before fitting.

### `[OPEN]` Sites are not independent replicates
Several share a basin, a climate signal, and in some cases a reservoir. Shared
β(t) may reflect shared weather rather than shared biology. A basin-level random
effect is the fix; not yet implemented. Stated as a limit in
`results_among_sites.Rmd` §7.

---

## 2026-07-29 — Session 4: `WH_BOR_Trout` built on the IPM posterior

### `[DECISION]` Response comes from the null IPM posterior, NOT the mark–recapture estimates
Andrew's call, and there is a real argument for it beyond preference: Arm B
projects with the IPM's own `la0`, `b`, `sigmaR`. Estimating the flow effect
against a *different* response construction would mean fitting one definition of
recruitment and projecting another. The IPM also enforces age-structure coherence
and fills years the mark–recapture missed. `PROPOSAL_01` is retained in `docs/` as
a record of the option not taken.

**What comes back:** the circularity guard (the null fit is now load-bearing) and
combining across draws. **What stays gone:** FPCA-as-estimator, `sp_mode`,
`estimator`, Rubin pooling, the null-vs-flow-informed diagnostic,
`01_extract_flow_climatology.R`. Roughly 70% of the simplification survives.

### `[FINDING]` Numbers-vs-biomass mismatch in the old response construction
`WorkingFPCA_robust.R` line 125:
```r
S <- obj$BUGSoutput$sims.list$NAdults        # comment says "BAdults[t]"
```
It pulls adult **numbers**, while the IPM's Ricker uses adult **biomass** in
grams (`la0 + log(BAdults) - b*BAdults`). So `log(R/S)` was estimated against one
stock definition and projected with another. `config.yml` now defaults to
`stock_node: "BAdults"`, with `"NAdults"` available to reproduce the old result.

### `[FINDING]` Age 4 in the abundance CSV is a plus group
Confirmed. Moot now that the response comes from the IPM, but recorded.

### `[CHANGE]` New project `WH_BOR_Trout` created — 18 scripts → 6
`00_config`, `01_build_response`, `02_build_flow`, `03_fit_recruitment`,
`04_validate`, `05_project_scenarios`, `06_figures`, plus `RUN_ALL.R`.
Paths live only in `config.yml`. Data referenced, not copied.

Design decisions worth recording:
- **Draws combined by simulation, not Rubin's rules.** `g*_m = g_m + N(0, se_m)`, then quantiles. Exact, no unbiasedness assumption, quantile levels in the output names so an interval cannot be mislabelled.
- **One QR decomposition reused across all draws.** The design matrix is draw-invariant because discharge is data. Thousands of regressions run in under a second.
- **Partial pooling implemented with the same shrinkage formula as the teaching figure**, so `explain_partial_pooling.R` and `03_fit_recruitment.R` match line for line.
- **Gate enforcement is structural.** `05` refuses to write `armB_eta.rds` if `04` failed. A projection built on a failed gate is indistinguishable from a real one.

### `[OPEN]` Three verification items before quoting any number
1. **The posterior is the NULL fit.** No script can check this.
2. **`posterior.first_year: 1980`.** Script 01 prints the implied year range — confirm.
3. **Water-year alignment.** `spawn_water_year = recruit_year − REC_LAG + 1`. A one-year error is invisible; it shifts every window by a year and still gives plausible coefficients. Highest-risk assumption in the design.

### `[OPEN]` `R/armB/13_survival_production.R` needs ~20 lines rewired
`forward_sim_production()` expects `f$draws$beta_t`; point it at `armB_eta.rds`.
Do not run until the recruitment gate has a settled answer.

---

## 2026-07-29 — Session 2: reframing, comprehension materials

### `[DECISION]` Full clean-up of all 18 scripts accepted
Session 1 declined a single-pass rewrite on attribution-risk grounds. Andrew
overruled: the goal is clarity and simplification, not debugging, and changed
numbers are acceptable. **Binding.** The staged-order caution from Session 1 is
withdrawn as a blocker; it survives only as a suggestion for how to sequence work.

### `[FINDING]` Mark–recapture stage already produces standard errors
`FISabundance_length_function_wDetection.R` returns `Est`, `SE`, `LCL`, `UCL` per
Stream × Section × Age × Year (fish/km), via model-averaged length-dependent
capture efficiency (`N = marked / p̂`, delta-method SE). Written to
`AllBrownTrout_AllYears_PopulationEstimates_wDet_071625.csv` and copied straight
into the JAGS data folder.

**The SEs are currently discarded.** The JAGS model uses point estimates and
generates its own uncertainty. This is the structural fact behind Proposal 01.

### `[FINDING]` Answers to Session 1's blocking questions
| Question | Answer |
|---|---|
| `Surv[]` monitored per year? | Yes → survival emulator is buildable |
| `weight2` per draw? | Yes → biomass budget is buildable |
| Harvest in the IPM? | No → surplus production = ΔB, no removals term |
| `get_site_lag("Madison.Norris")` | **3** → equals `REC_LAG`; flow and spawners reference the same calendar year |
| `BAdults` units | grams |
| Mark–recapture design | External to the IPM, by MFWP agreement, so published numbers match |

### `[FINDING]` `flow_lag = rec_lag = 3` confirmed — interpretation constraint
Because both lags are 3, the hydrograph and the spawning stock are from the same
calendar year. Any pathway by which spawn-year flow affects adult abundance is
differenced out of `log(R/S)`. **What is being estimated is a spawn-year effect,
not an age-0 rearing-year effect.** Code comments in `03_score_flow_signal.R` and
`05_forward_sim.R` describing it as rearing-year are wrong and must be fixed
wherever the pipeline lands.

### `[CHANGE]` Documents created
- `docs/00_SCRIPT_MAP.md` — plain-language description of all 20 scripts + jargon glossary (FPCA, β(t), penalized vs fpc, sp/sp_mode, Rubin pooling, run_cv, permutation null) with references
- `docs/PROPOSAL_01_direct_measurement_error.md` — Suggestion 1
- `R/explain/explain_methods_figures.R` — 9 teaching figures, simulated data, no inputs needed
- `R/explain/explain_partial_pooling.R` — 2 figures on hierarchical shrinkage
- `PROJECT_LOG.md`, `docs/daily/2026-07-29.md`
- `setup_github.sh`, `docs/GITHUB_SETUP.md`, `.gitignore`

### `[OPEN]` **Decision required before further code changes**
Which framework to build toward:
- **A** — keep the four-stage pipeline; clean and consolidate 18 scripts → ~9; no statistical change
- **B** — Arm A / Arm B split at Norris only (direct measurement-error regression for inference, JAGS retained for projection)
- **C** — straight to hierarchical multi-site version of B, all 14 sites
- **D** — build B at Norris, run side by side against the current result, then choose *(recommended)*

### `[OPEN]` Carried from Session 1, not yet actioned
- Distribution of `SE/Est` across site-years — needed before trusting MR SEs as a measurement-error term
- Whether the delta-method SE is optimistic in low-catch years
- Confirm the water-year alignment assumption: recruit-year `Y` maps to water year `Y − REC_LAG + 1`. **Most likely off-by-one in the whole design.**

### `[OPEN]` Multiple-comparisons risk flagged
Plan to run 14 sites and report those with low p-values is a selection problem.
At α = 0.05 across 14 sites you expect ~0.7 false positives under a global null.
Hierarchical pooling is the principled alternative and is also more powerful.
Raised; not yet decided.

---

## 2026-07-29 — Session 1: code review

### `[FINDING]` Tier-1 defects in the existing pipeline
Full ledger in `REVIEW_and_PATCHES.md`. Headlines:

1. **β(t) bands labelled 95% are actually 80%.** `pool_rubin()` uses `qt(0.9, df)` and `qt(0.75, df)`; figure subtitles say 95%. Every β(t) figure understates the interval by ~40%.
2. **`build_flow_cache.R` never writes the cache.** `save_site_flow()` is commented out inside the driver loop. `built` stays empty; the script prints "Cached 0 sites" every run. Whatever is in `data/flow_fd/` is stale. The STEP 2 round-trip check passes trivially because `.reference_fd()` prefers the live builder over the stored `.rds` — it verifies the builder against itself.
3. **`residual_sigmaR()` subtracts overfit variance.** Removes `Var(η̂)` — fitted variance from ~9 parameters on 43 points — from the null process SD. Projection ribbons are too narrow.
4. **The CV gate tests a different model than the one shipped.** `cv_compare()` re-estimates `sp` per fold; production uses `sp_fixed`.
5. **`FLOW_LAG` read from config in the projection, from the fit in the fit.** They agree today; nothing enforces it.

Tier 2 (statistical structure) and Tier 3 (hygiene, 10 items) also in the review.

### `[CHANGE]` Modules created
- `REVIEW_and_PATCHES.md`
- `R/15_pooling_and_cv.R` — posterior propagation replacing Rubin, direction probabilities, blocked CV, circular-shift permutation null, CV-shrunk variance correction
- `R/14_seasonal_baseline.R` — four-window water-year estimator + head-to-head
- `R/13_survival_production.R` — survival emulator + exact biomass production budget + factorial pathway attribution
- `methods_PNAS.Rmd`, `RESULTS.Rmd` — both branch on the validation gate

**Status of these five files:** written against the *current* framework. If
Proposal 01 is adopted, `15` and `14` carry over largely intact, `13` needs its
inputs rewired, and the two `.Rmd`s need their inference sections rewritten.
Nothing here is wasted, but nothing here should be run until the framework
decision is made.

### `[FINDING]` Norris gate status (from prior sessions, not re-verified)
- `estimator = "fpc"`: cv_R² = +0.126 (LOO); collapses under blocked CV
- `estimator = "penalized"`: cv_R² = −0.078, edf ≈ 4
- Permutation p = 0.116
- FPC+OLS apparent skill traced to temporal interpolation bias

### `[DECISION]` Two analysis arms stay separate
Rule curve (summer *mean* flow → equilibrium K and MS) and FPCA emulator
(hydrograph *shape* → recruitment) answer different questions. Not to be merged.
Carried forward from earlier sessions. **Still binding.**
