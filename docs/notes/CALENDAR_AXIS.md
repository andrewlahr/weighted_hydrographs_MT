# The calendar-year axis: what it costs and what it buys

The analysis runs on **calendar day of year** (1 = 1 January). Earlier versions
used a water year (1 October – 30 September). This records why it changed, and
the one thing to watch.

---

## Why it changed

Interpretability. The audience for the ecology is not the audience for the water
management, and a figure whose x-axis starts in October needs explaining to
everyone in the first group. That cost is paid on every figure, in every talk,
for the life of the project.

Two further simplifications came with it that were not the original motivation:

**The lag mapping stopped being ambiguous.** The IPM selects a flow lag on a
calendar basis. On a water-year axis that had to be *translated*, and the
translation needed a conditional offset — a calendar year straddles two water
years, and which one applied depended on whether the mechanism sat in Oct–Dec or
Jan–Sep. On a calendar axis:

```r
flow_year <- function(recruit_year, site) recruit_year - flow_lag(site)
```

No offset, nothing to get wrong, and it is exactly the quantity the IPM chose.

**The allocation season stopped wrapping.** May–October is days 121–304 on a
calendar axis: one contiguous range. On the water-year axis May was day 213 and
October was day 31, so the season wrapped the boundary and `06b` needed an
ordered index and a separate plotting position to handle it. That machinery is
gone.

---

## The one real cost

Brown trout spawn in **October–November**. Incubation runs into the following
spring. A calendar year cuts that sequence.

For a site with `flow_lag = recruit_lag` (Madison.Norris, lag 3), the hydrograph
year is the **spawning year**, and it contains:

| Period | In the window? |
|---|---|
| Pre-spawn summer conditions (Jul–Sep) | ✓ |
| **Spawning (Oct–Nov)** | ✓ |
| Early incubation (Dec) | ✓ |
| Late incubation (Jan–Mar of the *following* year) | ✗ |
| Emergence, first summer | ✗ |

So spawning and the first two months of incubation are inside; the rest is not.
That is a narrower loss than "the mechanism is cut in half" — but it is real, and
if redd scour or dewatering in February drives recruitment at a site, this design
cannot see it.

For a site with `flow_lag = recruit_lag − 1` (BigHole.Melrose, lag 2), the
hydrograph year is the **age-0 rearing year**, which contains emergence, the full
first summer, and the start of the first autumn. Nothing important is cut. The
calendar axis is arguably a *better* fit for these sites than the water year was.

---

## How to state this in the manuscript

Say it plainly in Methods, once:

> Hydrographs were indexed on the calendar year, matching the basis on which the
> integrated population model selected its flow lag. For sites whose selected lag
> identifies spawning-year conditions, this window includes autumn spawning and
> December incubation but excludes incubation from January onward; sites whose
> selected lag identifies age-0 rearing-year conditions have the relevant period
> fully contained.

A reviewer who knows brown trout will notice the split. Naming it first is much
better than being asked.

---

## If you need the missing months

Two options, in increasing order of effort:

1. **Report β(t) for the following January–March as a supplementary panel.** The
   flow data exist; it is one extra join at `flow_year + 1`. Enough to say whether
   anything is there.
2. **Add the following Jan–Mar as a fifth window.** Cleaner inferentially, costs
   one parameter, and makes the incubation hypothesis testable rather than
   assumed away.

Neither is worth doing before the primary model clears the gate. If flow does not
predict recruitment inside the main window, adding months will not rescue it.

---

## Seasonal windows

Pre-registered in `config.R` as calendar quarters. Each is contiguous and needs
no explanation to a non-specialist. They read differently depending on the site's
flow lag, and both readings are coherent:

| Window | Days | `flow_lag = 3` (spawning year) | `flow_lag = 2` (rearing year) |
|---|---|---|---|
| `winter` | 1–90 | pre-spawn winter | late incubation |
| `runoff` | 91–181 | snowmelt, adult habitat | emergence, fry displacement |
| `summer` | 182–273 | adult condition pre-spawn | first-summer rearing |
| `autumn` | 274–365 | **spawning**, early incubation | first autumn |

The functional β(t) is the primary estimand; these four windows are the
confirmatory anchor with real statistical power. See `README.md`.
