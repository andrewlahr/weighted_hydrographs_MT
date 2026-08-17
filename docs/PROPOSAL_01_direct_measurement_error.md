# Suggestion 1 — Separate the *inference* question from the *projection* question

**Status:** proposed, not implemented. Decide before anything gets rewritten.
**Everything else I've suggested can wait behind this one**, because it changes how
many scripts there need to be.

---

## The observation that prompted this

Your mark–recapture stage already produces, for every Stream × Section × Age × Year:

```
Est    SE    LCL    UCL          (fish per km)
```

**It gives you an uncertainty estimate, and the current pipeline throws it away.**
The JAGS model consumes the point estimates, generates its own uncertainty from its
own structure, and everything downstream then works to propagate *that* — which is
what Rubin pooling, the null-vs-flow-informed comparison, and the circularity
diagnostic all exist to manage.

You have measurement error measured directly. You're spending four scripts
reconstructing a substitute for it.

---

## What the pipeline currently looks like

```
   MR estimates            JAGS null IPM          FPCA emulator        forward sim
   (Est ± SE)      ───►    Ricker + survival ───► log(R/S) ~ beta(t) ──►  scenarios
                            │                      │
                     SE discarded here      needs the circularity guard,
                                            Rubin pooling, null-vs-flow arms,
                                            estimator choice, sp_mode
```

Four stages. Each one needs machinery to undo an assumption made by the previous
one. That is where the confusion you're describing comes from — it isn't that any
individual piece is wrong, it's that the *chain* generates its own problems.

## What I'm proposing

```
                     ┌── ARM A (inference) ───────────────────────────┐
   MR estimates      │   one model:  log(R/S) ~ density + flow,       │
   (Est ± SE)  ──────┤   with the MR standard errors IN the model      │──► the coefficients
                     └────────────────────────────────────────────────┘
                     ┌── ARM B (projection) ──────────────────────────┐
   JAGS IPM ─────────┤   existing forward sim / rule curve,           │──► BoR scenarios
                     │   with Arm A's coefficients plugged in          │
                     └────────────────────────────────────────────────┘
```

**Arm A answers "does flow affect recruitment?"** It never touches the IPM, so
there is nothing to guard against circularity — the response is built from raw
abundance estimates that never saw a hydrograph.

**Arm B answers "what happens under BoR scenarios?"** It keeps the JAGS model,
because you genuinely need age structure, survival, and a launch state to project.

---

## The Arm A model, written out

For site $j$, recruit-year $t$:

**Measurement layer** — this is the part you currently discard.
$$\log \hat{R}_{j,t} \sim N\!\left(\log R_{j,t},\ \tau^2_{R,j,t}\right), \qquad \tau_{R,j,t} \approx \frac{\mathrm{SE}_{j,t}}{\mathrm{Est}_{j,t}}$$

(The SE/Est ratio is the coefficient of variation, which is approximately the SD on
the log scale. Same for spawners.)

**Process layer** — the Ricker plus flow, on four seasonal windows.
$$\log\!\left(\frac{R_{j,t}}{S_{j,t-3}}\right) = \alpha_j - b_j S_{j,t-3} + \sum_{k=1}^{4} \gamma_{j,k}\, z_{j,t,k} + \varepsilon_{j,t}$$

where $z_{j,t,k}$ is the mean standardized flow anomaly in season $k$ (autumn
spawning, overwinter incubation, spring runoff, summer base flow) on a water-year
axis.

**That's the whole model.** Three lines. You can write it in a manuscript and a
reviewer can check it.

What disappears, and why you don't need it:

| Machinery | Why it's no longer needed |
|---|---|
| Circularity guard | The response is raw MR estimates. Nothing to guard. |
| Null vs flow-informed arms | Only one response exists. |
| Rubin pooling | Measurement error is *inside* the model. Nothing to pool afterwards. |
| `estimator = "penalized"` vs `"fpc"` | Four seasonal windows, no basis to choose. |
| `sp_mode` | No smoothing parameter. |
| Response-construction sensitivity | Only one construction. |

Six sources of confusion, all downstream of one structural choice.

---

## The part I think matters most: fit all 14 sites at once

You wrote that you have "13 other sites with possibly lower p values / positive
results." I want to flag the risk in that plan directly, because it's the sort of
thing that gets caught in review.

**With 14 sites tested separately at α = 0.05, you expect roughly one significant
result by chance even if flow does nothing anywhere.** Selecting the sites that came
out significant and writing those up is the garden of forking paths. A reviewer who
notices 14 sites were tested and 3 reported will ask, and there is no good answer
after the fact.

The principled alternative is also the more *powerful* one: **fit all sites in one
hierarchical model.**

$$\gamma_{j,k} \sim N\!\left(\Gamma_k,\ \sigma^2_k\right)$$

Each site gets its own flow effect $\gamma_{j,k}$, but those effects are drawn from
a common distribution with mean $\Gamma_k$.

### What partial pooling does, in plain terms

Three ways to handle 14 sites:

1. **No pooling** — 14 separate fits. Each uses only ~43 points. Noisy. Multiple comparisons problem.
2. **Complete pooling** — one fit, all sites forced to share one coefficient. Ignores real site differences.
3. **Partial pooling** — the hierarchical model. Each site gets its own estimate, *pulled toward the group average by an amount proportional to how noisy that site is.*

A site with 40 years and tight MR estimates barely moves. A site with 18 years and
wide confidence intervals gets pulled hard toward the group. **The model decides how
much to pool from the data**, by estimating $\sigma_k$ — if sites really do differ,
$\sigma_k$ is large and little pooling happens.

`R/explain/explain_partial_pooling.R` shows this on simulated data where the truth
is known: the partially pooled estimates are closer to the truth than either
extreme, and the noisiest sites improve most.

### Why this is the better manuscript

Instead of *"at Madison.Norris, p = 0.116"*, your headline becomes:

> Across 14 Montana brown trout populations, a one-SD reduction in summer base flow
> was associated with a Γ% change in recruits per spawner (95% CI …), with
> site-level variation of σ.

That is a stronger claim, it uses all your data, and it has no selection problem.
And $\Gamma$ is exactly the quantity BoR needs, because they operate across the
basin, not at one gage.

### References

- Gelman & Hill (2007) *Data Analysis Using Regression and Multilevel/Hierarchical Models*, Ch. 12 — the clearest introduction to partial pooling that exists.
- Su, Peterman & Haeseker (2004) *CJFAS* 61:2471–2486 — hierarchical Ricker across multiple stocks. Almost exactly your design.
- Thorson et al. (2014) *Fish and Fisheries* 15:342–361 — hierarchical stock–recruit meta-analysis.
- Roberts et al. (2017) *Ecography* 40:913–929 — blocked CV for structured data.

---

## What this would cost you

I'd rather state the downsides plainly than sell this.

1. **Numbers will change.** You said you're not worried about that, so I'm noting it and moving on.
2. **You lose the age-structure constraint in the inference arm.** The JAGS model enforces that N3 comes from N2 last year. A direct regression doesn't. In exchange you get transparency. Arm B still has it.
3. **Someone must confirm the MR SEs are usable as-is.** They come from a delta-method approximation on `N = marked / p̂`, which can be optimistic if capture efficiency is poorly estimated in low-catch years. This needs a look before it's trusted — I'd want to see the distribution of SE/Est across site-years.
4. **It's new code.** Roughly 200 lines total, versus the ~2,500 in the current inference path. But it is 200 lines you haven't tested yet.
5. **Survival still needs the IPM.** The MR estimates are abundance by age, not survival, so the survival arm stays in Arm B.

---

## What I'd do about the existing 18 scripts either way

Independent of the decision above, the current pipeline collapses to about half its
size with no change in what it does:

- `10_penalized_beta.R` — **delete.** Duplicates functions already inside `WorkingFPCA_robust.R`.
- `07`, `08`, `09`, `12` — all four define `parse_block()` with the same regex. **One copy.**
- `09_make_figures.R` (394 lines) and `12_results_report.R` (296 lines) both regenerate figures and tables. **Merge into one, or let the `.Rmd` do it.**
- `01_extract_flow_climatology.R` exists to recover constants that `build_flow_cache.R` computed and discarded. **Have the cache builder save them.** That deletes a 135-line script and its verification step.
- `03`, `04` are ~40 lines each and are only ever called by `05`. **Fold in.**

That's 18 files → about 9, before any statistical change at all.

---

## The decision

**Which do you want to build toward?**

**A.** Keep the four-stage pipeline. Clean, document, consolidate 18 scripts → 9. No statistical change.

**B.** Arm A / Arm B split, single site (Norris) first. Direct measurement-error regression for inference; keep JAGS for projection.

**C.** Straight to the hierarchical multi-site version of B, all 14 sites at once.

**D.** Build B for Norris and run it **side by side** against the current result, then decide between A, B and C with both answers in front of you.

I'd recommend **D**. It costs maybe a day, it answers the question empirically
rather than by argument, and if the two approaches agree at Norris that is itself a
result worth a sentence in the manuscript. C is where I think you should end up, but
going there without seeing B on one site first means changing everything at once —
which is the situation you're currently trying to get out of.
