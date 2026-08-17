# =============================================================================
# 09_figures.R  --  presentation figures + every number the manuscript quotes.
#
#   out: output/figures/09_*.png, output/tables/derived_stats.csv
#
# Scripts 02-08 make DIAGNOSTIC figures -- those are for you while you work.
# These are the ones that go in front of other people.
#
# The centrepiece is Figure 9a: beta_R(t) and beta_S(t) overlaid on a brown trout
# life-history timeline. That figure IS research question 2. The ecological claim
# lives in whether the resolved features line up with known life-stage timing:
# positive beta_R during incubation implicates redd dewatering; negative during
# runoff implicates fry displacement; a survival effect at summer base flow
# implicates thermal and habitat limitation of adults.
#
# derived_stats.csv holds every number the manuscript quotes. Quote from it, never
# by hand -- that is how prose and data stay in sync when the analysis is re-run.
#
# Run:  source("R/00_config.R"); source("R/09_figures.R")
# =============================================================================

source(here::here("R", "00_config.R"))
suppressPackageStartupMessages({ library(tidyr); library(purrr) })

rd <- function(f) { p <- file.path(OUT, "models", f); if (file.exists(p)) readRDS(p) else NULL }
BR <- rd("beta_recruitment.rds"); BS <- rd("beta_survival.rds")
GT <- rd("gate.rds"); SE <- rd("sensitivity.rds")
PR <- rd("production.rds"); SC <- rd("scenarios.rds")
if (is.null(BR) || is.null(GT)) stop("Run scripts 01-05 first.")

STATS <- list()
# `value` is stored as CHARACTER for every stat. The table mixes numbers
# (cv_R2, edf) with labels (estimator, fpc_rule), and bind_rows() refuses to
# combine a double column with a character one. Storing one type avoids that, and
# costs nothing: read.csv() returns a mixed column as character regardless, so
# this simply makes the in-memory type match the on-disk type. V() and Vi() in
# manuscript/_common.R coerce back with as.numeric() when formatting.
stat <- function(n, v, note = "") {
  STATS[[n]] <<- data.frame(stat = n, value = as.character(v), note = note,
                            stringsAsFactors = FALSE)
}

# =============================================================================
# LIFE-HISTORY TIMELINE -- edit these to match your system, and CITE them
# =============================================================================
# CALENDAR day-of-year (1 = 1 JANUARY). These were previously coded on the
# water-year index and were three months out of place after the axis migration --
# "spawning" was being drawn at 1 Jan - 2 Mar. Any alignment found against them
# would have been spurious.
#
# TWO THINGS TO UNDERSTAND BEFORE USING THIS FIGURE
#
# 1. WRAPPING STAGES. Incubation runs Dec-Mar and so crosses the calendar
#    boundary. It is entered as TWO segments (Dec, and Jan-Mar) sharing one stage
#    label. That split is the calendar axis showing its cost honestly: the two
#    halves of incubation sit in different lag years and cannot both be resolved
#    by a single beta(t).
#
# 2. WHICH STAGES ARE EVEN IN FRAME depends on the site's flow lag. beta(t) is
#    estimated on ONE calendar year. At a lag equal to the recruit lag that year
#    contains autumn spawning; at a shorter lag it contains emergence and first
#    summer. Read the stage bands only for the stages the lag actually reaches.
#
# *** THESE ARE PLACEHOLDERS. Replace with values from the literature or from
# *** local MFWP observation, CITE them, and fix them BEFORE looking at beta(t).
# *** Setting them afterwards guarantees agreement and demonstrates nothing.
LIFE <- data.frame(
  stage = c("spawning", "incubation", "incubation", "emergence",
            "first summer", "first winter", "first winter"),
  start = c(274, 335,   1, 121, 182, 335,   1),
  end   = c(334, 365,  90, 181, 273, 365,  90),
  cite  = c("Oct-Nov, MFWP redd surveys",
            "Dec-Mar (segment 1 of 2)", "Dec-Mar (segment 2 of 2)",
            "May-Jun", "Jul-Sep",
            "Dec-Mar age-0 (segment 1 of 2)", "Dec-Mar age-0 (segment 2 of 2)"),
  stringsAsFactors = FALSE)
write.csv(LIFE, file.path(OUT, "tables", "life_history_timeline.csv"), row.names = FALSE)

curve_df <- function(B, label) if (is.null(B)) NULL else
  bind_rows(lapply(B$fits, function(f) {
    se <- sqrt(diag(f$Vbeta) + apply(f$beta_draws, 2, var))
    data.frame(site = f$site, process = label, doy = 1:365,
               beta = colMeans(f$beta_draws),
               lo = colMeans(f$beta_draws) - 1.96 * se,
               hi = colMeans(f$beta_draws) + 1.96 * se,
               scaled = colMeans(f$beta_draws) / max(abs(colMeans(f$beta_draws))))
  }))
cv <- bind_rows(curve_df(BR, "recruitment"), curve_df(BS, "survival"))

# =============================================================================
# FIG 9a -- RQ2: the curves against trout life history
# =============================================================================
f9a <- ggplot() +
  geom_rect(data = LIFE, aes(xmin = start, xmax = end, ymin = -Inf, ymax = Inf, fill = stage),
            alpha = .13) +
  geom_hline(yintercept = 0, linetype = 2, colour = PAL[["mute"]]) +
  geom_line(data = cv, aes(doy, scaled, colour = process), linewidth = 1.1) +
  scale_fill_brewer(palette = "Set2", name = "life stage") +
  scale_colour_manual(values = c(recruitment = PAL[["blue"]], survival = PAL[["green"]]),
                      name = "vital rate") +
  scale_x_continuous(breaks = MON_B, labels = MON_L) +
  facet_wrap(~ site) +
  labs(title = "Figure 9a. Flow sensitivity of recruitment and survival, against brown trout life history",
       subtitle = paste0("Curves scaled to a maximum of 1 so shapes can be compared. Shaded bands are life stages.\n",
                         "The ecological claim is whether resolved features align with stage timing: a positive effect\n",
                         "during incubation implicates redd dewatering; negative during runoff implicates fry\n",
                         "displacement; a summer survival effect implicates thermal and habitat limitation of adults."),
       x = NULL, y = "scaled sensitivity") + theme_wh

# mean sensitivity within each life stage -- the quotable version of 9a
# Mean sensitivity within each life stage. Wrapping stages have TWO rows in LIFE,
# so days are pooled by stage NAME before averaging -- otherwise December and
# Jan-Mar would appear as two separate "incubation" results.
stage_days <- lapply(split(LIFE, LIFE$stage), function(d)
  unlist(Map(`:`, d$start, d$end)))

stage_tab <- bind_rows(lapply(names(stage_days), function(nm) {
  cv %>% filter(doy %in% stage_days[[nm]]) %>%
    group_by(site, process) %>%
    summarise(stage = nm, mean_beta = mean(beta),
              frac_positive = mean(beta > 0),
              n_days = dplyr::n() / dplyr::n_distinct(site), .groups = "drop")
}))
write.csv(stage_tab, file.path(OUT, "tables", "life_stage_sensitivity.csv"), row.names = FALSE)

f9b <- ggplot(stage_tab, aes(mean_beta, stage, fill = process)) +
  geom_vline(xintercept = 0, linetype = 2, colour = PAL[["mute"]]) +
  geom_col(position = position_dodge(.7), width = .65, alpha = .85) +
  scale_fill_manual(values = c(recruitment = PAL[["blue"]], survival = PAL[["green"]]),
                    name = NULL) +
  facet_wrap(~ site) +
  labs(title = "Figure 9b. Mean flow sensitivity within each life stage",
       subtitle = "The quotable version of Figure 9a. Positive = wetter-than-normal conditions during that stage help.",
       x = "mean beta(t) over the stage", y = NULL) +
  theme_wh + theme(legend.position = "bottom")

figs <- list(`09_f9a_life_history` = f9a, `09_f9b_stage_means` = f9b)

# =============================================================================
# FIG 9c -- RQ1: the management answer
# =============================================================================
if (!is.null(SE)) {
  figs[["09_f9c_management"]] <- SE$daily %>%
    ggplot(aes(doy, effect, colour = process)) +
    geom_hline(yintercept = 0, linetype = 2, colour = PAL[["mute"]]) +
    geom_line(linewidth = 1.1) +
    scale_colour_manual(values = c(recruitment = PAL[["blue"]], survival = PAL[["green"]]),
                        name = NULL) +
    scale_x_continuous(breaks = MON_B, labels = MON_L) +
    facet_grid(process ~ site, scales = "free_y") +
    labs(title = paste0("Figure 9c. Benefit of releasing ", SE$settings$delta_cfs,
                        " additional cfs, by day"),
         subtitle = paste0("Recruitment: % change in recruits per unit stock. Survival: percentage points.\n",
                           "This is beta(t) divided by baseline discharge -- a DIFFERENT SHAPE from Figure 9a,\n",
                           "because the same water is a larger proportional change at low flow."),
         x = NULL, y = "effect") + theme_wh + theme(legend.position = "none")

  iv <- SE$intervals
  for (i in seq_len(nrow(iv))) {
    k <- paste0(iv$process[i], "_", gsub(" ", "_", iv$which[i]))
    stat(paste0(k, "_lo_day"), iv$lo_doy[i], "calendar-year day")
    stat(paste0(k, "_hi_day"), iv$hi_doy[i], "calendar-year day")
    stat(paste0(k, "_width_days"), iv$width_days[i],
         paste0(100 * iv$cred_level[i], "% interval width"))
    stat(paste0(k, "_resolvable"), as.numeric(iv$resolvable[i]), "1 = width <= 90 days")
  }
  stat("delta_cfs", SE$settings$delta_cfs, "release size used for the sensitivity curve")
}

# =============================================================================
# FIG 9d -- RQ1: production
# =============================================================================
if (!is.null(PR)) {
  figs[["09_f9d_production"]] <- PR$production %>% filter(pathway == "both") %>%
    ggplot(aes(block_start, d_prod_pct, fill = d_prod_pct > 0)) +
    geom_hline(yintercept = 0, linetype = 2, colour = PAL[["mute"]]) +
    geom_col(width = PR$settings$block_days) +
    scale_fill_manual(values = c("TRUE" = PAL[["blue"]], "FALSE" = PAL[["red"]]), guide = "none") +
    scale_x_continuous(breaks = MON_B, labels = MON_L) +
    facet_wrap(~ site, scales = "free_y") +
    labs(title = "Figure 9d. Effect on total population production",
         subtitle = paste0("Percent change in mean annual surplus production from adding ",
                           PR$settings$delta_cfs, " cfs for ", PR$settings$block_days,
                           " days, propagated\nthrough the age-structured model. Includes compounding of survival into future spawning stock."),
         x = NULL, y = "% change in surplus production") + theme_wh
  bb <- PR$production %>% filter(pathway == "both")
  stat("production_best_block", bb$block_start[which.max(bb$d_prod_pct)], "calendar-year day")
  stat("production_best_pct", max(bb$d_prod_pct), "% change in surplus production")
  stat("production_worst_block", bb$block_start[which.min(bb$d_prod_pct)], "calendar-year day")
  stat("production_worst_pct", min(bb$d_prod_pct), "% change in surplus production")
}

# =============================================================================
# FIG 9e -- RQ3: scenarios
# =============================================================================
if (!is.null(SC)) {
  grp <- intersect(c("Scenario", "Period", "Type"), names(SC$effects))
  figs[["09_f9e_scenarios"]] <- SC$effects %>%
    ggplot(aes(effect, reorder(do.call(paste, c(SC$effects[grp], sep = " / ")), effect),
               colour = process)) +
    geom_vline(xintercept = 0, linetype = 2, colour = PAL[["red"]]) +
    geom_linerange(aes(xmin = effect_lo, xmax = effect_hi), linewidth = .7) +
    geom_point(size = 3) +
    scale_colour_manual(values = c(recruitment = PAL[["blue"]], survival = PAL[["green"]]),
                        name = NULL) +
    facet_wrap(~ process, scales = "free_x") +
    labs(title = "Figure 9e. Bureau of Reclamation scenarios",
         subtitle = paste0("Change relative to historical mean flow. Bars span the 10th-90th percentile across years.\n",
                           if (SC$gate_passed) "beta(t) passed validation." else
                           "*** GATE FAILED -- not supported findings. ***"),
         x = "effect", y = NULL) + theme_wh + theme(legend.position = "none")
  stat("n_scenarios", nrow(SC$effects), "scenario blocks")
  stat("scenario_worst_effect", min(SC$effects$effect), "most negative scenario effect")
  stat("scenario_best_effect", max(SC$effects$effect), "most positive scenario effect")
}

# =============================================================================
# HEADLINE STATS
# =============================================================================
for (i in seq_len(nrow(GT$gate))) {
  g <- GT$gate[i, ]
  k <- paste0(g$process, "_", g$form)
  stat(paste0(k, "_r2_blocked"), g$r2_blocked, "blocked CV R2 -- the honest number")
  stat(paste0(k, "_perm_p"), g$p_value, "permutation p")
  stat(paste0(k, "_passes"), as.numeric(g$passes), "1 = passed the gate")
}
# ---------------------------------------------------------------------------
# HOW beta(t) WAS ESTIMATED.
#
# Recording this is not bookkeeping. Switching the estimator, or the fpc
# component-selection rule, changes every number in this file. Without the
# settings recorded alongside the results, a table cannot be reproduced or
# audited -- and a reviewer asking "how many components, chosen how?" has no
# answer. Methods reads these values rather than restating them by hand.
# ---------------------------------------------------------------------------
stat("estimator", ESTIMATOR, "how beta(t) was estimated")
if (identical(ESTIMATOR, "fpc")) {
  stat("fpc_rule", FPC_RULE, "component selection rule")
  stat("fpc_target_var", FPC_VAR, "% cumulative flow variance (cumulative/both)")
  stat("fpc_min_var", FPC_MIN, "% individual flow variance (individual/both)")
  stat("fpc_max", FPC_MAX, "hard cap on components")
} else {
  stat("k_beta", K_BETA, "spline basis dimension")
}
stat("compare_estimators", as.integer(COMPARE), "1 = the other arm was also gated")

for (s in names(BR$fits)) {
  stat(paste0("edf_recruitment_", s), BR$fits[[s]]$edf, "effective df of beta_R(t)")
  stat(paste0("n_years_", s), BR$fits[[s]]$n_years, "recruit-years")
  stat(paste0("flow_lag_", s), BR$fits[[s]]$flow_lag %||% NA,
       "IPM-selected flow lag (years); may differ from the recruit lag")

  # fpc-only provenance, per site: K and what actually determined it.
  if (!is.null(BR$fits[[s]]$n_fpc)) {
    stat(paste0("fpc_K_", s), BR$fits[[s]]$n_fpc, "components retained")
    stat(paste0("fpc_var_explained_", s), BR$fits[[s]]$fpc_var_explained,
         "% of flow variance retained")
    stat(paste0("fpc_K_capped_", s), as.integer(isTRUE(BR$fits[[s]]$fpc_K_capped)),
         "1 = fpc_max bound, not the variance rule")
    stat(paste0("fpc_K_unstable_", s), as.integer(isTRUE(BR$fits[[s]]$fpc_K_unstable)),
         "1 = a component sits within 0.5% of the threshold")
  }
}
if (!is.null(BS)) for (s in names(BS$fits)) {
  stat(paste0("edf_survival_", s), BS$fits[[s]]$edf, "effective df of beta_S(t)")
  # `surv_lag`, not `lag` -- named to distinguish it from the recruitment flow
  # lag in config.R. They are separate hypotheses: recruitment responds at a
  # spawning lag, survival responds in or near the year it is measured.
  stat(paste0("survival_lag_", s), BS$fits[[s]]$surv_lag,
       "IPM-independent survival flow lag (years), chosen by the sweep in script 04")
}

for (nm in names(figs))
  ggsave(file.path(OUT, "figures", paste0(nm, ".png")), figs[[nm]],
         width = 10, height = 5.6, dpi = 200)

write.csv(bind_rows(STATS), file.path(OUT, "tables", "derived_stats.csv"), row.names = FALSE)
message("\n  wrote ", length(figs), " presentation figures and derived_stats.csv")
message("  EDIT R/09_figures.R -> LIFE to match your system's life-history timing,")
message("  and cite the source. Figure 9a is the ecology result and it is only as")
message("  good as that timeline.\n")
