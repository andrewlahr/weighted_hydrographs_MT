# Proposal 02 — The daily estimand

**Read this before the code.** It contains one result that changes what you hand a
water manager, and one method that decides how finely you are allowed to speak.

---

# Part 1 — β(t) is not the curve a water manager needs

This is the most important thing in this document.

Your standardization is

$$x(t) = \frac{\log Q(t) - \bar{c}(t)}{\sigma}$$

and the model is $\eta = \sum_t \beta(t)\,x(t)$.

So β(t) is *the effect of a one-standard-deviation standardized log anomaly on day
t*. A manager does not release standard deviations. They release **cfs**, or
acre-feet, on a real day with a real baseline flow.

Work out what adding $\Delta Q$ on day $t$ actually does:

$$\Delta\eta(t) = \beta(t)\cdot\frac{\log\!\left(Q(t) + \Delta Q\right) - \log Q(t)}{\sigma} = \frac{\beta(t)}{\sigma}\log\!\left(1 + \frac{\Delta Q}{\bar{Q}(t)}\right)$$

where $\bar{Q}(t) = \exp(\bar{c}(t))$ is the geometric-mean baseline discharge on
day $t$. For small releases this is approximately

$$\Delta\eta(t) \approx \frac{\beta(t)}{\sigma\,\bar{Q}(t)}\,\Delta Q$$

**The benefit per cfs is β(t) divided by that day's baseline discharge.**

## Why this matters enormously here

Consider two days with *identical* β(t):

| | baseline flow | 10 cfs added | proportional change |
|---|---|---|---|
| Late June (snowmelt peak) | 2,000 cfs | +10 | +0.5% |
| Mid September (base flow) | 150 cfs | +10 | +6.5% |

Same β, same water, **thirteen times the effect**. On the Madison below Ennis
Lake the seasonal range in discharge is more than an order of magnitude, so
dividing by $\bar{Q}(t)$ does not nudge the curve — it can reverse which part of
the year looks most valuable.

This means:

- **β(t) is the ecological curve.** It answers "when is the fish population
  sensitive to hydrologic conditions?" That is research question 2.
- **s(t) = β(t) / (σ·Q̄(t)) is the management curve.** It answers "when does a unit
  of water buy the most fish?" That is research question 1.

They are different shapes and they answer different questions. Reporting β(t) to
an irrigator as if it were the release schedule would systematically point them at
high-flow periods where their water is diluted.

**Both go in the manuscript.** The distinction is a contribution, not a
caveat — as far as I know it is not made explicitly in the functional
flow–recruitment literature, and it is the bridge between the ecology and the
management application.

## Diminishing returns come free

Use the exact form, not the derivative:

$$\Delta\eta(t) = \frac{\beta(t)}{\sigma}\log\!\left(1 + \frac{\Delta Q}{\bar{Q}(t)}\right)$$

The logarithm means the hundredth cfs buys less than the first. So the model
already tells a manager that spreading 500 acre-feet over three weeks beats dumping
it in two days — without any extra assumption. That is a directly useful result and
it falls out of the log-transform you already had.

## The volume-constrained version, which is the real decision

A manager rarely asks "what if I add 10 cfs on 12 August". They ask "I have 800
acre-feet of leased water — **when do I release it?**"

Releasing volume $V$ evenly across a window $W$ of $|W|$ days gives
$\Delta Q = \kappa V / |W|$ cfs, and the total benefit is

$$\Delta\eta(W, V) = \frac{1}{\sigma}\sum_{t \in W}\beta(t)\,\log\!\left(1 + \frac{\kappa V}{|W|\,\bar{Q}(t)}\right)$$

Maximise over $W$. This is what `06_daily_sensitivity.R` optimises, and the output
is a table of the best windows for each of several volumes. **That table is the
deliverable for research question 1.** Not a curve — a schedule.

---

# Part 2 — How finely are you allowed to speak?

You want daily guidance. The data may not support daily guidance. Rather than
argue about it, measure it.

## The wrong way

Plot β(t) with pointwise 95% bands, find the highest point, report that day.

Three problems. Pointwise bands are not simultaneous, so the chance that the *whole
curve* is compatible with flat is much higher than any single point suggests.
Adjacent days are strongly correlated, so "the highest point" moves a lot under
resampling. And a penalized spline with, say, 4 effective degrees of freedom
carries roughly 365/4 ≈ 90 days of resolution — you cannot read a date off it.

## The right way: the distribution of the argmax

Simulate the whole curve from its uncertainty, many times. Each time, ask which
day is best. Collect the answers.

```
for s in 1..S:
    draw beta^(s)  from its full distribution
    compute s^(s)(t) = beta^(s)(t) / (sigma * Qbar(t))
    record  t*^(s) = argmax_t  s^(s)(t)

the histogram of t* IS the answer
```

Then report the central 80% interval of $t^*$:

- Spread over 200 days → **you cannot advise on timing.** Say so.
- Clustered in three weeks → **"the optimal release window is 5 Aug – 2 Sep (80% credible)."** Defensible, and exactly what a manager can act on.

The width of that interval is set by your data, not by a modelling choice. It is
the honest resolution of your answer, and it is a *reportable result* rather than a
limitation to be buried.

## Contrasts, not overlapping intervals

"Is day A better than day B?" is **not** answered by whether their confidence
intervals overlap. Because adjacent days are highly correlated,

$$\mathrm{Var}\!\left[\beta(t_1) - \beta(t_2)\right] = V_{11} + V_{22} - 2V_{12}$$

and $V_{12}$ is large and positive for nearby days. The variance of the
*difference* can be far smaller than the variance of either point. So you can
often say confidently that September beats June even when both pointwise bands
cross zero.

This requires the **full 365 × 365 covariance matrix** of β(t), not just the
pointwise standard errors. `03_fit_beta_recruitment.R` extracts it via
`predict(..., type = "lpmatrix")` and saves it. Everything downstream —
simultaneous bands, argmax distributions, window optimisation, pairwise
comparisons — uses it.

## Simultaneous bands

For any claim about *where* the curve is high, you need a band that covers the
whole function at once. Simulate, then find the critical value:

$$c_{0.95} = \text{95th percentile of } \max_t \frac{|\beta^{(s)}(t) - \hat\beta(t)|}{\mathrm{se}(t)}$$

Typically $c \approx 2.7$–$3.2$ rather than 1.96, so simultaneous bands are
noticeably wider. Report both, labelled. (Ruppert, Wand & Carroll 2003 §6.5;
Marra & Wood 2012.)

---

# Part 3 — Three processes, two regressions

You asked for recruitment, survival, and production. That is three answers but only
two regressions, and the distinction matters.

**Recruitment — β_R(t).** Response is $\log(R_t / B_{t-3})$ from the null IPM.
Flow lag 3, so this is *spawn-year* conditions. Because the flow lag equals the
recruit lag, flow and stock reference the same calendar year and any pathway from
spawn-year flow to adult abundance is differenced out. State this plainly: it is a
spawn-year effect, not an age-0 rearing-year effect.

**Survival — β_S(t).** Response is the survival process deviate from the null IPM,

$$\varepsilon_t = \mathrm{logit}(s_t) - \phi_0 - \phi_N \frac{N_{\mathrm{all},t-1}}{100}$$

i.e. the part of survival the density-dependent null model leaves unexplained.
Regressing survival *itself* on flow would re-attribute density-driven variation to
flow, because flow drives recruitment which drives density at a lag. The survival
lag is **not** 3 — adult survival responds to contemporaneous or prior-year
conditions. Lags 0 and 1 are fitted and gated separately.

**Production — not a regression.** Production is a *consequence* of recruitment and
survival propagated through the age structure, so fitting a third curve would be
wrong. Instead, take a numerical derivative through the population model:

```
for each day-block b:
    run the forward simulation with a small release on block b
    run it again with no release, SAME random number streams
    production sensitivity(b) = difference in mean surplus production
```

Common random numbers mean the difference is signal, not noise. This approach
automatically captures **compounding**: a survival gain raises the spawning stock,
which feeds the Ricker three years later. Two separate curves added together would
miss that entirely, and the interaction can be large.

Compute at 5-day block resolution (73 blocks). That is not a compromise — it is
already finer than the argmax analysis will support.

---

# Part 4 — The seasonal model stays, in a different role

You said you are still interested in it. Good, and it has a specific job:

| | Role | Degrees of freedom | Purpose |
|---|---|---|---|
| **Seasonal windows** | pre-registered confirmatory | 4 | Does flow matter at all? The gate. |
| **β(t)** | resolved description | 3–15 | *When*, at the resolution the data support. |

This is the standard confirmatory/exploratory split and it **strengthens** the
manuscript rather than hedging it. The seasonal model is the powered test; β(t) is
the description of structure within whichever windows the test supports. If they
disagree, the seasonal model wins on inference and β(t) is telling you where inside
a window the action is.

Practical consequence: the gate in `05_validate.R` runs on **both**. A β(t) that
fails while the seasonal model passes means "flow matters, but we cannot resolve
when." That is still a publishable finding and still useful to managers — it says
*release in this season, we cannot tell you which week.*

---

# Part 5 — How this maps to your three research questions

**RQ1 — guidance for water managers.**
Outputs: `s(t)` with simultaneous bands; the argmax distribution and its 80%
window; the volume-constrained release schedule table; production sensitivity by
block. Scripts 03, 04, 06, 07.

**RQ2 — what daily findings say about Montana trout population ecology.**
Outputs: β_R(t) and β_S(t) overlaid on a brown trout life-history timeline
(spawning, incubation, emergence, first summer, first winter). The ecological claim
lives in whether the resolved features line up with known life-stage timing —
positive β_R during incubation implicates redd dewatering; negative during runoff
implicates fry displacement. Divergence between β_R(t) and β_S(t) is itself the
finding: it says the two vital rates are limited at different times of year, which
has direct implications for which life stage is the bottleneck. Script 09,
`manuscript/results_by_site.Rmd`.

**RQ3 — BoR forecasted flows.**
Outputs: η per scenario computed as $\sum_t \beta(t) x_{\text{scen}}(t)$; the
recruitment and survival multipliers; and — new, and more useful than a multiplier
— **which days the scenarios change most, weighted by β(t)**. That decomposition
says *why* a scenario hurts, not just how much. Script 08.

---

# References

| Topic | Source |
|---|---|
| Signal regression / functional linear models in `mgcv` | Wood (2017) *Generalized Additive Models*, 2nd ed., §7.10 |
| Simultaneous confidence bands | Ruppert, Wand & Carroll (2003) *Semiparametric Regression*, §6.5 |
| Coverage of GAM intervals | Marra & Wood (2012) *Scand. J. Stat.* 39:53–74 |
| Scalar-on-function regression review | Reiss et al. (2017) *Int. Stat. Rev.* 85:228–249 |
| Blocked CV for temporally structured data | Roberts et al. (2017) *Ecography* 40:913–929 |
| Flow–ecology functional response | Ruhi et al. (2018) *Freshwater Biology* 63:1360–1374 |
| Brown trout redd dewatering / incubation flows | Shirvell & Dungey (1983) *TAFS* 112:355–367 |
| Flow timing and salmonid recruitment | Fausch et al. (2001) *Ecol. Appl.* 11:1438–1455 |
