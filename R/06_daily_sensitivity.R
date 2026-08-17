# =============================================================================
# 06_daily_sensitivity.R  --  RESEARCH QUESTION 1. The deliverable for managers.
#
#   in : output/models/beta_recruitment.rds, output/models/beta_survival.rds,
#        output/models/gate.rds
#   out: output/models/sensitivity.rds
#        output/tables/sensitivity_daily.csv     -- benefit per cfs, every day
#        output/tables/release_windows.csv       -- best window per volume
#        output/tables/best_day_intervals.csv    -- the honest resolution
#
# WHAT THIS SCRIPT PRODUCES, AND WHY IT IS NOT beta(t)
# ----------------------------------------------------
# beta(t) is the effect of a one-SD standardized log anomaly. Nobody releases
# standard deviations. Adding deltaQ cfs on day t changes the flow signal by
#
#     delta_eta(t) = beta(t)/sigma * log(1 + deltaQ / Qbar(t))
#
# so the benefit per cfs is beta(t) / (sigma * Qbar(t)). Because baseline
# discharge here spans more than an order of magnitude across the year, dividing
# by Qbar(t) RESHAPES the curve. The same 10 cfs is a ~6% proportional increase at
# September base flow and ~0.5% at the June snowmelt peak: thirteen times the
# effect from identical water and identical beta.
#
#     beta(t)  answers  "when is the population sensitive to hydrology?"   (RQ2)
#     s(t)     answers  "when does a unit of water buy the most fish?"     (RQ1)
#
# Both are reported. They are different shapes.
#
# THE LOG ALSO GIVES YOU DIMINISHING RETURNS FOR FREE. Using the exact form rather
# than the derivative means the hundredth cfs buys less than the first, so the
# model tells a manager that spreading 500 acre-feet over three weeks beats
# dumping it in two days -- with no extra assumption.
#
# HOW PRECISELY CAN YOU NAME A DAY?
# ---------------------------------
# Not by finding the peak of the fitted curve. Instead: simulate the whole curve
# from its full uncertainty many times, and each time ask which day is best. The
# DISTRIBUTION OF THAT ANSWER is the honest resolution.
#
#   spread over 200 days  -> you cannot advise on timing. Say so.
#   clustered in 3 weeks  -> "optimal window 5 Aug - 2 Sep (80% credible)".
#
# The width is set by your data, not by a modelling choice, and it is a reportable
# result rather than a limitation.
#
# Simulation uses BOTH uncertainty sources and the FULL 365x365 covariance:
#   pick a posterior draw m   -> abundance uncertainty
#   add MVN(0, V_beta * scale_m) -> regression uncertainty, WITH between-day
#                                   correlation, which is why contrasts are
#                                   sharper than overlapping intervals suggest
#
# Run:  source("R/00_config.R"); source("R/06_daily_sensitivity.R")
# =============================================================================

source(here::here("R", "00_config.R"))
source(here::here("R", "fn_fit_beta.R"))   # simulate_beta()
suppressPackageStartupMessages({ library(tidyr); library(purrr) })

BR   <- readRDS(file.path(OUT, "models", "beta_recruitment.rds"))
BS   <- if (file.exists(file.path(OUT, "models", "beta_survival.rds")))
          readRDS(file.path(OUT, "models", "beta_survival.rds")) else NULL
GATE <- readRDS(file.path(OUT, "models", "gate.rds"))$gate

N_SIM      <- if (is.null(CFG$sensitivity$n_sim)) 4000L else CFG$sensitivity$n_sim
DELTA_CFS  <- if (is.null(CFG$sensitivity$delta_cfs)) 10 else CFG$sensitivity$delta_cfs
VOLUMES_AF <- if (is.null(CFG$sensitivity$volumes_af)) c(200, 1000, 5000) else CFG$sensitivity$volumes_af
WINDOW_LEN <- if (is.null(CFG$sensitivity$window_lengths)) c(7, 14, 30, 60) else CFG$sensitivity$window_lengths
CRED       <- if (is.null(CFG$sensitivity$cred_level)) 0.80 else CFG$sensitivity$cred_level
AF_TO_CFS  <- 0.50417   # 1 acre-foot per day = 0.50417 cfs

set.seed(CFG$fitting$seed)


# =============================================================================
# THE ONE CUSTOM FUNCTION -- simulate whole beta(t) curves from their full
# uncertainty. Everything else in this script is arithmetic on its output.
# =============================================================================
# simulate_beta() now lives in R/fn_fit_beta.R so that 06 and 06b share one
# definition rather than drifting apart.


# =============================================================================
# LOOP OVER PROCESSES
# =============================================================================
daily_rows <- list(); window_rows <- list(); interval_rows <- list()
sim_store <- list(); simult_rows <- list()

jobs <- list()
for (s in names(BR$fits)) jobs[[length(jobs) + 1]] <- list(p = "recruitment", s = s, f = BR$fits[[s]])
if (!is.null(BS)) for (s in names(BS$fits)) jobs[[length(jobs) + 1]] <- list(p = "survival", s = s, f = BS$fits[[s]])

for (J in jobs) {

  f <- J$f; site <- J$s; proc <- J$p
  message("\n== ", proc, " | ", site, " ==")

  B    <- simulate_beta(f)                     # [n_sim x 365] curves
  Qbar <- f$Qbar; sigma <- f$global_sd

  # ---------------------------------------------------------------------------
  # 1. THE MANAGEMENT CURVE
  # ---------------------------------------------------------------------------
  # Exact effect of adding DELTA_CFS on a single day, per simulated curve.
  lever <- log(1 + DELTA_CFS / Qbar) / sigma           # length 365, day-specific
  Sens  <- sweep(B, 2, lever, "*")                     # [n_sim x 365]

  # ---------------------------------------------------------------------------
  # 2. SIMULTANEOUS BAND CRITICAL VALUE
  # ---------------------------------------------------------------------------
  # For any claim about WHERE the curve is high, a pointwise band is the wrong
  # tool: it covers each day at 95% but the whole curve at far less. The
  # simultaneous critical value is the 95th percentile of the largest
  # standardized deviation anywhere on the curve. Typically ~2.7-3.2, not 1.96.
  # (Ruppert, Wand & Carroll 2003 sec. 6.5; Marra & Wood 2012.)
  b_hat <- colMeans(B); se_pt <- apply(B, 2, sd)
  c_sim <- quantile(apply(abs(sweep(B, 2, b_hat, "-")) / rep(se_pt, each = nrow(B)),
                          1, max), 0.95, names = FALSE)
  message(sprintf("  simultaneous 95%% critical value = %.2f  (pointwise would use 1.96)", c_sim))
  simult_rows[[length(simult_rows) + 1]] <-
    data.frame(process = proc, site = site, c_simultaneous = c_sim)

  # ---------------------------------------------------------------------------
  # 3. DAILY TABLE
  # ---------------------------------------------------------------------------
  # Survival is on the logit scale, so also convert to survival PERCENTAGE POINTS
  # at the observed mean rate -- that is the number a manager can read.
  s_hat <- colMeans(Sens)
  daily <- data.frame(
    process = proc, site = site, doy = 1:365,
    month = MON_L[findInterval(1:365, MON_B)],
    Qbar_cfs = Qbar,
    beta = b_hat,
    beta_lo_pt = b_hat - 1.96 * se_pt,  beta_hi_pt = b_hat + 1.96 * se_pt,
    beta_lo_sim = b_hat - c_sim * se_pt, beta_hi_sim = b_hat + c_sim * se_pt,
    p_beneficial = colMeans(B > 0),
    sens_per_delta = s_hat,
    sens_lo = apply(Sens, 2, quantile, .025, names = FALSE),
    sens_hi = apply(Sens, 2, quantile, .975, names = FALSE),
    p_top10pct = colMeans(t(apply(Sens, 1, function(v) v >= quantile(v, 0.90)))),
    delta_cfs = DELTA_CFS)

  # readable effect size
  daily$effect <- if (proc == "recruitment") {
    100 * (exp(s_hat) - 1)                       # percent change in recruits/stock
  } else {
    ms <- f$mean_survival
    100 * (plogis(qlogis(ms) + s_hat) - ms)      # survival percentage points
  }
  daily$effect_units <- if (proc == "recruitment")
    paste0("% change in recruits per stock from +", DELTA_CFS, " cfs on that day") else
    paste0("survival percentage points from +", DELTA_CFS, " cfs on that day")

  daily_rows[[length(daily_rows) + 1]] <- daily

  # ---------------------------------------------------------------------------
  # 4. HOW PRECISELY CAN WE NAME THE BEST AND WORST DAY?
  # ---------------------------------------------------------------------------
  best  <- apply(Sens, 1, which.max)
  worst <- apply(Sens, 1, which.min)
  a <- (1 - CRED) / 2
  iv <- function(v, lbl) {
    q <- quantile(v, c(a, .5, 1 - a), names = FALSE)
    data.frame(process = proc, site = site, which = lbl,
               lo_doy = q[1], median_doy = q[2], hi_doy = q[3],
               width_days = q[3] - q[1],
               lo_month = MON_L[findInterval(q[1], MON_B)],
               median_month = MON_L[findInterval(q[2], MON_B)],
               hi_month = MON_L[findInterval(q[3], MON_B)],
               cred_level = CRED, resolvable = (q[3] - q[1]) <= 90)
  }
  ivs <- bind_rows(iv(best, "most beneficial day"), iv(worst, "most harmful day"))
  interval_rows[[length(interval_rows) + 1]] <- ivs
  sim_store[[paste(proc, site)]] <- list(best = best, worst = worst, Sens = NULL)

  for (i in seq_len(nrow(ivs))) {
    r <- ivs[i, ]
    message(sprintf("  %-20s %s %.0f%% window: day %.0f-%.0f (%s-%s), width %.0f days -- %s",
                    r$which, sprintf("%.0f%%", 100 * CRED), 100 * CRED,
                    r$lo_doy, r$hi_doy, r$lo_month, r$hi_month, r$width_days,
                    ifelse(r$resolvable, "RESOLVABLE", "NOT RESOLVABLE at daily scale")))
  }
  if (!all(ivs$resolvable))
    message("     -> The window is wider than 90 days. Report a SEASON, not a date.\n",
            "        This is a property of the data, not a failure of the analysis.")

  # ---------------------------------------------------------------------------
  # 5. THE VOLUME-CONSTRAINED RELEASE SCHEDULE  <- the actual management answer
  # ---------------------------------------------------------------------------
  # "I have V acre-feet. When do I release it?" Spread V evenly over a window of
  # length W starting on day d, then maximise the total benefit over d and W.
  for (V in VOLUMES_AF) for (WL in WINDOW_LEN) {
    dQ <- AF_TO_CFS * V / WL                       # cfs sustained over the window
    gain <- log1p(dQ / Qbar) / sigma               # per-day leverage, length 365
    starts <- 1:365
    # total benefit for each start day, per simulated curve, with wrap-around
    tot <- vapply(starts, function(d) {
      ix <- ((d - 1L + seq_len(WL) - 1L) %% 365L) + 1L
      as.numeric(B[, ix, drop = FALSE] %*% gain[ix])
    }, numeric(nrow(B)))                           # [n_sim x 365]
    bestd <- apply(tot, 1, which.max)
    m <- colMeans(tot)
    d0 <- which.max(m)
    q <- quantile(bestd, c(a, 1 - a), names = FALSE)
    window_rows[[length(window_rows) + 1]] <- data.frame(
      process = proc, site = site, volume_af = V, window_days = WL,
      sustained_cfs = dQ,
      best_start_doy = d0,
      best_start_month = MON_L[findInterval(d0, MON_B)],
      start_lo = q[1], start_hi = q[2], start_width = q[2] - q[1],
      delta_eta = m[d0],
      effect = if (proc == "recruitment") 100 * (exp(m[d0]) - 1) else
        100 * (plogis(qlogis(f$mean_survival) + m[d0]) - f$mean_survival),
      p_positive = mean(tot[, d0] > 0))
  }
}

daily     <- bind_rows(daily_rows)
windows_t <- bind_rows(window_rows)
intervals <- bind_rows(interval_rows)
simult    <- bind_rows(simult_rows)

# gate status attached to every table, so no number travels without its warrant
# Since the estimator comparison was added, gate.csv labels the functional arms
# "beta:penalized" and "beta:fpc" -- never plain "beta". An exact match here
# returned ZERO rows, so the join below produced all-NA `passes` and every
# downstream table reported "Gate passed: NA" without erroring.
# The guidance curve is the PRIMARY estimator's, so that is the row to take.
beta_form <- paste0("beta:", ESTIMATOR)
gsum <- GATE %>% filter(form == beta_form) %>%
  select(process, site, passes, r2_blocked, p_value)
if (!nrow(gsum))
  warning("No gate rows for '", beta_form, "'. gate.csv has: ",
          paste(unique(GATE$form), collapse = ", "),
          ". Downstream `passes` will be NA.", call. = FALSE)
daily     <- left_join(daily, gsum, by = c("process", "site"))
windows_t <- left_join(windows_t, gsum, by = c("process", "site"))
intervals <- left_join(intervals, gsum, by = c("process", "site"))


# =============================================================================
# FIGURES
# =============================================================================
gate_note <- function(d) if (all(d$passes, na.rm = TRUE))
  "beta(t) passed validation in script 05." else
  "*** beta(t) DID NOT PASS validation. Shapes below are not supported findings. ***"

# --- 6a: THE KEY FIGURE. beta(t) vs the management curve, same panel scale ----
f6a <- daily %>%
  select(process, site, doy, `beta(t): ecological sensitivity` = beta,
         `s(t): benefit per cfs released` = sens_per_delta) %>%
  pivot_longer(-c(process, site, doy)) %>%
  group_by(process, site, name) %>%
  mutate(scaled = value / max(abs(value))) %>% ungroup() %>%
  ggplot(aes(doy, scaled, colour = name)) +
  geom_hline(yintercept = 0, linetype = 2, colour = PAL[["mute"]]) +
  geom_line(linewidth = 1) +
  scale_colour_manual(values = c(PAL[["ink"]], PAL[["red"]]), name = NULL) +
  scale_x_continuous(breaks = MON_B, labels = MON_L) +
  facet_grid(process ~ site) +
  labs(title = "Figure 6a. The ecological curve and the management curve are different shapes",
       subtitle = paste0("Both scaled to a maximum of 1 so the SHAPES can be compared.\n",
                         "s(t) = beta(t) / (sigma x Qbar(t)): the same water is a large proportional change at base\n",
                         "flow and a small one at the snowmelt peak. Read beta(t) for ecology, s(t) for management.\n",
                         gate_note(daily)),
       x = NULL, y = "scaled to max = 1") + theme_wh + theme(legend.position = "bottom")

# --- 6b: the management curve in real units, with simultaneous bands ---------
f6b <- ggplot(daily, aes(doy, effect)) +
  geom_hline(yintercept = 0, linetype = 2, colour = PAL[["mute"]]) +
  geom_ribbon(aes(ymin = 100 * (exp(sens_lo) - 1), ymax = 100 * (exp(sens_hi) - 1)),
              fill = PAL[["red"]], alpha = .15) +
  geom_line(colour = PAL[["red"]], linewidth = 1) +
  facet_grid(process ~ site, scales = "free_y") +
  scale_x_continuous(breaks = MON_B, labels = MON_L) +
  labs(title = paste0("Figure 6b. Benefit of adding ", DELTA_CFS, " cfs on a single day"),
       subtitle = paste0("Recruitment: percent change in recruits per unit stock. Survival: percentage points.\n",
                         "Positive = releasing water on that day helps. ", gate_note(daily)),
       x = NULL, y = "effect") + theme_wh

# --- 6c: THE RESOLUTION FIGURE -- how precisely can we name a day? -----------
bd <- bind_rows(lapply(names(sim_store), function(k) {
  z <- strsplit(k, " ")[[1]]
  data.frame(process = z[1], site = z[2],
             doy = c(sim_store[[k]]$best, sim_store[[k]]$worst),
             which = rep(c("most beneficial", "most harmful"),
                         c(length(sim_store[[k]]$best), length(sim_store[[k]]$worst))))
}))

f6c <- ggplot(bd, aes(doy, fill = which)) +
  geom_histogram(bins = 73, alpha = .7, colour = NA, position = "identity") +
  geom_rect(data = intervals, inherit.aes = FALSE,
            aes(xmin = lo_doy, xmax = hi_doy, ymin = -Inf, ymax = Inf,
                colour = which), fill = NA, linetype = 3, linewidth = .5) +
  scale_fill_manual(values = c("most beneficial" = PAL[["blue"]],
                               "most harmful" = PAL[["red"]]), name = NULL) +
  scale_colour_manual(values = c("most beneficial" = PAL[["blue"]],
                                 "most harmful" = PAL[["red"]]), guide = "none") +
  scale_x_continuous(breaks = MON_B, labels = MON_L, limits = c(1, 365)) +
  facet_grid(process ~ site, scales = "free_y") +
  labs(title = "Figure 6c. How precisely can we name a day?",
       subtitle = paste0("Each simulated curve votes for its best and worst day. Dotted boxes are the ",
                         sprintf("%.0f%%", 100 * CRED), " intervals.\n",
                         "A NARROW cluster means real timing guidance. A spread across the year means the",
                         " honest answer\nis a season, not a date -- and the width is set by the data, not by us."),
       x = NULL, y = "simulations") + theme_wh + theme(legend.position = "bottom")

# --- 6d: P(this day is in the true best 10%) --------------------------------
f6d <- ggplot(daily, aes(doy, p_top10pct)) +
  geom_hline(yintercept = 0.10, linetype = 2, colour = PAL[["mute"]]) +
  geom_col(fill = PAL[["blue"]], width = 1) +
  facet_grid(process ~ site) +
  scale_x_continuous(breaks = MON_B, labels = MON_L) +
  labs(title = "Figure 6d. Probability each day is among the best 10% of days to release",
       subtitle = paste0("Dashed line = 0.10, what you would see if every day were equally good.\n",
                         "Days rising well above it are robustly good regardless of curve uncertainty.\n",
                         "This is often the most defensible timing statement available."),
       x = NULL, y = "probability") + theme_wh

# --- 6e: the release schedule table as a figure ------------------------------
f6e <- windows_t %>%
  filter(process == "recruitment") %>%
  ggplot(aes(best_start_doy, factor(window_days), colour = effect)) +
  geom_linerange(aes(xmin = start_lo, xmax = start_hi), linewidth = 1) +
  geom_point(size = 3.5) +
  scale_colour_gradient2(low = PAL[["red"]], mid = "grey85", high = PAL[["blue"]],
                         midpoint = 0, name = "% change in\nrecruits/stock") +
  scale_x_continuous(breaks = MON_B, labels = MON_L, limits = c(1, 365)) +
  facet_grid(site ~ paste0(volume_af, " acre-feet")) +
  labs(title = "Figure 6e. Where to put a fixed volume of water",
       subtitle = paste0("Optimal START day for releasing a given volume evenly over a given number of days.\n",
                         "Bars are the ", sprintf("%.0f%%", 100 * CRED),
                         " interval on the optimal start. Longer windows are usually better because\n",
                         "the log-response means the hundredth cfs buys less than the first."),
       x = NULL, y = "release window (days)") + theme_wh

for (nm in c("f6a", "f6b", "f6c", "f6d", "f6e"))
  ggsave(file.path(OUT, "figures", paste0("06_", nm, ".png")), get(nm),
         width = 10, height = 6, dpi = 150)


# =============================================================================
# SAVE
# =============================================================================
saveRDS(list(daily = daily, windows = windows_t, intervals = intervals,
             simultaneous = simult, best_day_sims = sim_store,
             settings = list(n_sim = N_SIM, delta_cfs = DELTA_CFS,
                             volumes_af = VOLUMES_AF, window_lengths = WINDOW_LEN,
                             cred_level = CRED),
             run = Sys.time()),
        file.path(OUT, "models", "sensitivity.rds"))
write.csv(daily,     file.path(OUT, "tables", "sensitivity_daily.csv"), row.names = FALSE)
write.csv(windows_t, file.path(OUT, "tables", "release_windows.csv"), row.names = FALSE)
write.csv(intervals, file.path(OUT, "tables", "best_day_intervals.csv"), row.names = FALSE)

message("\n  wrote 3 tables and 5 figures.")
message("\n  FOR A MANAGER: output/tables/release_windows.csv is the answer to")
message("  'I have V acre-feet, when do I release it?'")
message("  FOR THE MANUSCRIPT: best_day_intervals.csv is the honest resolution statement.")
message("\n  If `resolvable` is FALSE, do not report a date anywhere. Report the season")
message("  and say the record cannot resolve finer. That is a finding, not a failure.\n")
