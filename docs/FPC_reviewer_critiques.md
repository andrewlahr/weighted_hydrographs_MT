# If you go `estimator = "fpc"` only: what reviewers will say

Ordered by how much damage each does to **your** claims, not by how often it gets
raised in general. Two of these attack your headline results directly.

For each: the critique in the language a reviewer would use, whether it is fair,
and what you can do *now* to defuse it.

---

## 1. Your β(t) curves are not comparable across sites

**The critique.** *"FPCA is performed separately at each site, so the eigenfunctions
differ between sites. The authors' cross-site comparison of β(t) therefore compares
functions estimated in different bases, and apparent agreement or disagreement may
reflect differences in the basis rather than in the biological response."*

**Fair?** Yes, and this is the one I would lead with as a reviewer. It is not a
philosophical objection — it is a direct problem with `results_among_sites.Rmd`.
RQ2 rests on "does the same β(t) feature recur across independent populations,"
and if each site's β(t) is built from a different set of shapes, recurrence is
confounded with basis similarity. Two sites with similar hydrology get similar
eigenfunctions and will look more alike than two sites with different hydrology,
*regardless of the fish*.

The penalized arm does not have this problem: every site uses the same B-spline
basis over the same 365 days, so the curves live in one space and are directly
comparable.

**Pre-emptions, in order of effort.**

- **Common basis.** Pool all sites' standardized curves, run one FPCA, and use those shared eigenfunctions everywhere. Site-specific scores, common Φ. This fixes the objection cleanly and costs about ten lines. It is what I would do if you go FPC-only.
- **Report basis similarity.** Compute the pairwise inner products between sites' leading eigenfunctions and publish the matrix. If they are near-identical, the objection is defused empirically.
- **Fall back to the penalized arm for RQ2 only**, and say so. Defensible but awkward to justify.

---

## 2. Your best-day intervals are too narrow, and a statistician will know it

**The critique.** *"The uncertainty in β(t) is derived from the sampling covariance of
the retained component scores, conditional on K. It therefore excludes uncertainty
in the truncation itself. The reported credible intervals for the optimal release
window are anticonservative by an unknown amount."*

**Fair?** Yes, and it lands squarely on RQ1's headline. Your whole resolution
argument — "the optimal window is X to Y with 80% probability" — is only as good as
the covariance the simulation draws from. FPC's `Vbeta` has rank K, so simulated
curves can only take shapes the K retained components can make. Curves that would
put the peak elsewhere are not merely improbable, they are *unrepresentable*.

This is worse than an ordinary too-narrow interval, because the narrowness is
structural rather than a matter of degree, and it will not shrink with more data
at fixed K.

**Pre-emptions.**

- **Bootstrap the whole procedure.** Resample years (in blocks, to respect autocorrelation), re-run FPCA *and* K-selection *and* the regression inside each replicate, and take the best-day interval from the bootstrap distribution. This is the honest interval and it is the answer to the critique. Expect it to be considerably wider.
- **Report both arms' intervals side by side.** If the penalized interval is wider, say so and quote the wider one.
- Do **not** report the analytic rank-K interval as if it were calibrated. That is the specific thing that would get flagged.

---

## 3. K is a researcher degree of freedom

**The critique.** *"The number of retained components was chosen to explain 90% of flow
variance, with a cap of 10. Neither threshold is justified, and no sensitivity
analysis is presented. Given that the central claim concerns the timing of peak
sensitivity to within weeks, the robustness of that timing to K is essential."*

**Fair?** Completely. And it is easy to test, which makes omitting it look worse.

**Pre-emption.** Run the argmax across K = 3, 4, …, 10 and across variance
thresholds of 80 / 90 / 95%, and put the resulting best-day estimates in a
supplementary figure. **If the peak day moves substantially with K, you cannot
make a daily claim** — and you would much rather discover that yourself than have
a reviewer discover it.

---

## 4. Dimension reduction is unsupervised with respect to the response

**The critique.** *"Components are ranked by variance in the predictor and then tested
against the response. There is no guarantee the retained components span the
biologically relevant subspace; a low-variance mode of flow variation could carry
the entire recruitment signal and would be discarded before testing."*

**Fair?** The general objection is textbook (Jolliffe 1982, *Applied Statistics*
31:300–303). But unlike the first three, **this one you can answer empirically and
decisively** — and the diagnostic is cheap.

**Pre-emption — run this and report it.** Regress the response on the *discarded*
components. If they carry no predictive relationship, truncation was harmless in
your data, whatever the theory says. `R/diag_fpc_truncation.R` (below) does it and
prints a one-line verdict.

This is the single highest-value thing in this document. One paragraph in Methods
citing that diagnostic converts a structural objection into a settled question.

---

## 5. Local features of β(t) may be artefacts of global basis functions

**The critique.** *"Eigenfunctions beyond the first oscillate across the full annual
cycle. Structure in β(t) during periods with no hypothesized mechanism may
therefore reflect the basis rather than the data, and the interpretation of
specific dates is correspondingly weakened."*

**Fair?** Yes, and it is aimed precisely at what makes your paper novel. Your
entire contribution is daily-resolution interpretation. A basis whose elements
span the whole year makes "day 285 matters and day 200 does not" harder to
defend than it would be with a local basis.

**Pre-emptions.**

- Report the **simultaneous** band, not the pointwise one. Features that survive a simultaneous band are not basis artefacts.
- Show the eigenfunctions themselves in SI. Readers can then see which oscillations are shapes and which are signal. Figure 1 of `R/explain/explain_estimator_choice.R` is exactly this figure.
- Restrict interpretation to periods where **both** estimators agree. Which is the argument for not going FPC-only.

---

## 6. Component interpretations are post-hoc

**The critique.** *"The authors describe PC2 as representing snowmelt timing. PC2 is
defined as the direction of maximal remaining variance orthogonal to PC1; its
correspondence to a biological process is an interpretation applied after the fact,
and its sign is arbitrary."*

**Fair?** Yes, if you label components. Orthogonality is a mathematical
constraint, not a biological one, and nothing forces mode 2 to be one coherent
process.

**Pre-emption.** Don't interpret individual components. Interpret **β(t)**, which
is basis-independent, and treat the components purely as computational machinery.
Show them in SI without biological labels. This costs you nothing — β(t) is what
you care about anyway.

---

## 7. The emulator cannot represent novel hydrograph shapes

**The critique.** *"Because β(t) is constrained to the span of the training
eigenfunctions, the model is structurally unable to respond to features of
projected future hydrographs that were absent from the historical record."*

**Fair?** True but double-edged, and you can turn it into a strength. It means the
model will not extrapolate wildly into shapes it has never seen — arguably safer
than the penalized arm for RQ3.

**Pre-emption.** State it as a deliberate property, and quantify it: project each
BoR scenario-year onto the retained eigenfunctions and report the **fraction of
its variance the basis cannot capture**. That number belongs in the RQ3 section
either way, and framing it yourself is much better than having it framed for you.

---

## 8. Procedural checks a methods-literate reviewer will make

| Check | Your status |
|---|---|
| Was K re-selected inside every CV fold? | **Yes** — `.fit_beta_fpc()` re-selects from training years only. Say so explicitly in Methods; the old pipeline did not, and that is a plausible reason its FPC arm scored +0.126 under LOO and collapsed under blocked CV. |
| Was FPCA itself refitted inside folds? | **Yes** — `prcomp` runs on training curves only. |
| Why not FPCR-R, functional PLS, or FLiRTI? | Not currently addressed. See below. |
| Is the PCA sign convention stable? | `prcomp` signs are arbitrary and can flip. Irrelevant for β(t), which is invariant, but fix signs before plotting components. |

**On the alternatives question.** A reviewer who knows this literature will ask why
unsupervised truncation rather than the supervised alternative. **Functional PLS**
chooses components by covariance *with the response* rather than variance of the
predictor — which is objection 4 fixed by construction. Reiss & Ogden (2007),
*JASA* 102:984–996, compare FPCR and FPLS for exactly this class of model. You do
not have to use it, but you should be able to say why you didn't.

---

## What FPC-only *is* defensible for

I have been one-sided; here is the honest other side.

- **The seasonal question.** "Does summer base flow matter?" — FPC is fine. It answers this as well as anything.
- **Continuity with the weighted-hydrograph literature**, including your coworker's BoR extension scripts. If FPCA-weighted hydrographs are the established approach in this line of work, departing from it needs its own justification.
- **No smoothing parameter to defend.** You trade one tuning decision (`sp`) for another (`K`), but `K` is more transparent and easier for a reader to reason about.
- **η is guaranteed to be a realizable flow contrast**, because β(t) lives in the span of things flow actually does.

---

## The recommendation

FPC-only is defensible for *whether* and *which season*. It is weakest at exactly
the two places your paper is novel: **daily timing** (objections 2 and 5) and
**cross-site synthesis** (objection 1).

Given that `compare_estimators: true` costs seconds, the ratio of risk to effort
strongly favours keeping both and reporting agreement. "Both a smoothness prior
and a flow-variance prior place the optimum in the same window" is a sentence no
reviewer can attack on estimator grounds, and it makes objections 1, 2, 4 and 5
moot in one move.

If you go FPC-only anyway, do these three before submission:

1. **Common eigenfunction basis across sites** (fixes 1)
2. **Block bootstrap over the full procedure** for best-day intervals (fixes 2)
3. **The discarded-component diagnostic** and a **K sensitivity sweep** (fixes 3 and 4)

All three are small. None is small enough to do during revision under a deadline.
