# =============================================================================
# RUN_ALL.R -- the whole pipeline, in order.
#
#     source("RUN_ALL.R")
#
# Each script saves its output before the next begins, so they can also be run
# one at a time. That is the recommended way the first few times.
#
#   00  configuration and input checks
#   01  null-IPM posterior      ->  log(R/S) per draw
#   02  daily discharge         ->  standardized 365-day curves + baseline flow
#   03  beta_R(t)               ->  RECRUITMENT sensitivity, per day    [primary]
#   04  beta_S(t)               ->  SURVIVAL sensitivity, per day
#   05  THE GATE                ->  blocked CV + permutation, both curves,
#                                   both model forms, plus the resolution check
#   06  daily sensitivity       ->  RQ1: benefit per cfs, best-day windows,
#                                   release schedules for a fixed volume
#   06b decision window        ->  RQ1: the same, restricted to the season when
#                                   water can actually be released, plus what
#                                   that constraint costs
#   07  production sensitivity  ->  RQ1: whole-population answer via forward sim
#   08  BoR scenarios           ->  RQ3: effects and day-by-day attribution
#   09  presentation figures    ->  RQ2: life-history overlay + derived_stats.csv
#
# Scripts 03, 04 and 07 are the slow ones (thousands of spline fits, and a
# 73-block simulation sweep). Expect tens of minutes for a single site.
# =============================================================================

t0 <- Sys.time()

# Cheap preflight. Catches a missing source() line, an undefined CFG setting, or
# a syntax slip in one second, rather than several minutes into the run after
# three scripts have already written output.
if (file.exists(here::here("check_setup.R")))
  message("  (tip: source(\"check_setup.R\") verifies the whole project first)")

source(here::here("R", "00_config.R"))

steps <- c("01_build_response", "02_build_flow",
           "03_fit_beta_recruitment", "04_fit_beta_survival",
           "05_validate", "06_daily_sensitivity", "06b_decision_window",
           "07_production_sensitivity", "08_scenarios_bor", "09_figures")

for (s in steps) {
  message("\n", strrep("=", 70), "\n  ", s, "\n", strrep("=", 70))
  ok <- tryCatch({ source(here::here("R", paste0(s, ".R"))); TRUE },
                 error = function(e) {
                   message("\n  STOPPED in ", s, ":\n  ", conditionMessage(e)); FALSE })
  if (!ok) break
}

message("\n", strrep("=", 70))
message(sprintf("  finished in %.1f minutes", as.numeric(difftime(Sys.time(), t0, units = "mins"))))
message("  figures -> output/figures/    tables -> output/tables/")

# Which figures were split per site, and which could not be. A figure that
# cannot be split shows a gap on every per-site page, and that must be visible
# here rather than discovered when the site renders.
if (exists("fig_report")) fig_report()
message("")
message("  SEPARATE ARM, not run above:")
message("    source('R/10_rulecurve.R')   equilibrium K and MS under BoR summer flows")
message("    It reads the FLOW-INFORMED IPM and its own standardization, so it is")
message("    deliberately outside this chain. Different question, different inputs.")
message("\n  READ THESE TWO FILES FIRST:")
message("    output/tables/gate.csv               did the curve survive validation?")
message("    output/tables/best_day_intervals.csv can you honestly name a day?")
message("    output/tables/decision_window_schedule.csv  when to release, by volume")
message("    output/tables/derived_stats.csv       every number the manuscript quotes")
message("\n  If `resolvable` is FALSE, report a season and say the record cannot")
message("  resolve finer. That is a finding about Montana flow records, not a failure.")
message(strrep("=", 70), "\n")
