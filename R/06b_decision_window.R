# =============================================================================
# 06b_decision_window.R
#
# The same analysis as script 06, restricted to the season in which water
# allocation decisions are actually made.
#
#   in : output/models/beta_recruitment.rds, beta_survival.rds, gate.rds
#   out: output/tables/decision_window_*.csv, output/figures/06b_*.png
#
# WHY THIS IS NOT JUST A ZOOM
# ---------------------------
# The full calendar year is the right ECOLOGICAL domain: beta(t) is estimated over
# all 365 days and the manuscript should report it that way. But nobody can
# release water in February. Leased water, shepherded water and reservoir
# re-timing are negotiated and delivered across the irrigation season.
#
# Restricting to that season changes the OPTIMISATION, not only the axis limits:
#
#   * The best FEASIBLE day is the argmax over a subset of days. It can be a
#     different day from the global optimum, with a different benefit.
#   * Its credible interval must be recomputed within the subset. Truncating the
#     unconstrained interval gives the wrong answer -- simulations whose global
#     peak fell in March do not vanish, they relocate to their best feasible day,
#     and that relocation is information.
#   * The volume-release optimisation must only consider start days whose whole
#     window fits inside the feasible season.
#   * And the quantity a manager most needs is one script 06 never computes:
#     WHAT DOES THE CONSTRAINT COST? If the true optimum is in April and you can
#     only act from May, how much of the achievable benefit is still on the table?
#
# WHY THE ANSWER MAY BE COUNTERINTUITIVE
# --------------------------------------
# Benefit per cfs is beta(t) / (sigma * Qbar(t)) -- see docs/PROPOSAL_02. Within
# May-October, Qbar falls by a large factor from the snowmelt peak to autumn base
# flow. So the 1/Q leverage rises steeply across exactly this window, and the
# best day to RELEASE can sit well after the best day for beta(t) alone.
# Figure 06b-f plots both so the two are not confused.
#
# Run:  source("R/00_config.R"); source("R/06b_decision_window.R")
# =============================================================================

source(here::here("R", "00_config.R"))
source(here::here("R", "fn_fit_beta.R"))          # simulate_beta()
suppressPackageStartupMessages({ library(tidyr); library(purrr) })

BR   <- readRDS(file.path(OUT, "models", "beta_recruitment.rds"))
BS   <- if (file.exists(file.path(OUT, "models", "beta_survival.rds")))
          readRDS(file.path(OUT, "models", "beta_survival.rds")) else NULL
GATE <- readRDS(file.path(OUT, "models", "gate.rds"))$gate

N_SIM      <- CFG$sensitivity$n_sim        %||% 4000L
DELTA_CFS  <- CFG$sensitivity$delta_cfs    %||% 10
VOLUMES_AF <- CFG$sensitivity$volumes_af   %||% c(200, 1000, 5000)
WINDOW_LEN <- CFG$sensitivity$window_lengths %||% c(7, 14, 30, 60)
CRED       <- CFG$sensitivity$cred_level   %||% 0.80
AF_TO_CFS  <- 0.50417                      # 1 acre-foot per day = 0.50417 cfs

set.seed(CFG$fitting$seed)                 # same seed as 06: identical curves


# =============================================================================
# THE DECISION WINDOW
# -----------------------------------------------------------------------------
# Config gives the window as month-day; the analysis runs on calendar day of
# year, so 1 May = 121 and 31 Oct = 304 and the season is a plain contiguous
# range. `pos` is retained as the position within the window (1 = the first
# feasible day), because the release-scheduling code below needs to guarantee
# that a window of a given DURATION fits entirely inside the season -- that
# constraint is about position within the window, not about day of year.
# =============================================================================
md_to_doy <- function(md)
  as.integer(format(as.Date(paste0("2001-", md)), "%j"))   # non-leap year
DW_START <- md_to_doy(CFG$decision_window$start %||% "05-01")
DW_END   <- md_to_doy(CFG$decision_window$end   %||% "10-31")
DW_LABEL <- CFG$decision_window$label %||% "allocation season"

# On a calendar axis the allocation season is CONTIGUOUS (1 May = day 121,
# 31 Oct = day 304), so this is a plain range. On the water-year axis it wrapped
# the 1 October boundary and needed an ordered index plus a separate plotting
# position -- all of which is now gone.
if (DW_START > DW_END)
  stop("decision_window start (", DW_START, ") is after end (", DW_END,
       ") on the calendar axis. Check CFG$decision_window in config.R.")
dec_idx <- DW_START:DW_END
NDEC    <- length(dec_idx)

# doy_month() and doy_date() come from R/00_config.R -- shared with every other
# script so a date never gets formatted two different ways in two figures.
mon_of  <- doy_month
date_of <- doy_date

axis_df <- data.frame(pos = seq_len(NDEC), doy = dec_idx) %>%
  mutate(month = mon_of(doy))
brk <- axis_df[!duplicated(axis_df$month), ]
dec_axis <- scale_x_continuous(breaks = brk$pos, labels = brk$month,
                               limits = c(1, NDEC), expand = expansion(mult = 0.01))

message("\n== decision window: ", DW_LABEL, " ==")
message(sprintf("  %s to %s  |  %d days  |  calendar-year days %d-%d%s",
                CFG$decision_window$start %||% "05-01",
                CFG$decision_window$end   %||% "10-31",
                NDEC, DW_START, DW_END,
                if (DW_START > DW_END) " (wraps the 1 Oct boundary)" else ""))


# =============================================================================
# LOOP OVER PROCESSES AND SITES
# =============================================================================
curve_rows <- list(); cost_rows <- list(); sched_rows <- list(); grid_rows <- list()

jobs <- list()
for (s in names(BR$fits)) jobs[[length(jobs) + 1]] <- list(p = "recruitment", s = s, f = BR$fits[[s]])
if (!is.null(BS)) for (s in names(BS$fits)) jobs[[length(jobs) + 1]] <- list(p = "survival", s = s, f = BS$fits[[s]])

for (J in jobs) {

  f <- J$f; site <- J$s; proc <- J$p
  message("\n-- ", proc, " | ", site)

  B     <- simulate_beta(f, N_SIM)
  Qbar  <- f$Qbar; sigma <- f$global_sd
  lever <- log1p(DELTA_CFS / Qbar) / sigma          # per-day leverage, length 365
  Sens  <- sweep(B, 2, lever, "*")                  # [n_sim x 365]

  # readable units: % change in recruits, or survival percentage points
  to_effect <- function(x) if (proc == "recruitment") 100 * (exp(x) - 1) else
    100 * (plogis(qlogis(f$mean_survival) + x) - f$mean_survival)

  # ---------------------------------------------------------------------------
  # 1. THE CURVE ACROSS THE FEASIBLE SEASON
  # ---------------------------------------------------------------------------
  s_hat <- colMeans(Sens); se <- apply(Sens, 2, sd)
  c_sim <- quantile(apply(abs(sweep(Sens, 2, s_hat, "-")) / rep(se, each = N_SIM),
                          1, max), 0.95, names = FALSE)

  curve_rows[[length(curve_rows) + 1]] <- data.frame(
    process = proc, site = site,
    pos = seq_len(NDEC), doy = dec_idx,
    month = mon_of(dec_idx), date = date_of(dec_idx),
    Qbar_cfs = Qbar[dec_idx],
    beta = colMeans(B)[dec_idx],
    effect       = to_effect(s_hat[dec_idx]),
    effect_lo    = to_effect(s_hat[dec_idx] - c_sim * se[dec_idx]),
    effect_hi    = to_effect(s_hat[dec_idx] + c_sim * se[dec_idx]),
    p_beneficial = colMeans(Sens > 0)[dec_idx],
    delta_cfs = DELTA_CFS)

  # ---------------------------------------------------------------------------
  # 2. BEST FEASIBLE DAY, AND WHAT THE CONSTRAINT COSTS
  # ---------------------------------------------------------------------------
  # Recomputed WITHIN the window, per simulated curve. Not a truncation of the
  # unconstrained interval: a simulation whose global peak fell in March does not
  # drop out, it relocates to its best feasible day, and where it lands matters.
  best_free <- apply(Sens, 1, which.max)
  best_dec  <- dec_idx[apply(Sens[, dec_idx, drop = FALSE], 1, which.max)]
  val_free  <- apply(Sens, 1, max)
  val_dec   <- apply(Sens[, dec_idx, drop = FALSE], 1, max)

  a  <- (1 - CRED) / 2
  qd <- quantile(match(best_dec, dec_idx), c(a, .5, 1 - a), names = FALSE)

  cost_rows[[length(cost_rows) + 1]] <- data.frame(
    process = proc, site = site,
    best_free_doy = median(best_free),
    best_free_date = date_of(round(median(best_free))),
    best_free_in_window = median(best_free) %in% dec_idx,
    best_dec_doy = dec_idx[round(qd[2])],
    best_dec_date = date_of(dec_idx[round(qd[2])]),
    lo_pos = qd[1], hi_pos = qd[3], width_days = qd[3] - qd[1],
    lo_date = date_of(dec_idx[max(1, round(qd[1]))]),
    hi_date = date_of(dec_idx[min(NDEC, round(qd[3]))]),
    effect_free = to_effect(median(val_free)),
    effect_dec  = to_effect(median(val_dec)),
    # what fraction of the achievable benefit survives the constraint
    frac_retained = median(val_dec) / median(val_free),
    p_constraint_binds = mean(!(best_free %in% dec_idx)),
    resolvable = (qd[3] - qd[1]) <= 60,
    cred_level = CRED)

  cr <- tail(cost_rows, 1)[[1]]
  message(sprintf("   best feasible day: %s  (%.0f%% interval %s to %s, %.0f days wide)",
                  cr$best_dec_date, 100 * CRED, cr$lo_date, cr$hi_date, cr$width_days))
  message(sprintf("   constraint binds in %.0f%% of simulations; retains %.0f%% of achievable benefit",
                  100 * cr$p_constraint_binds, 100 * cr$frac_retained))
  if (!cr$resolvable)
    message("   -> interval wider than 60 days: recommend a PERIOD, not a date.")

  # ---------------------------------------------------------------------------
  # 3. FIXED VOLUME, FEASIBLE STARTS ONLY
  # ---------------------------------------------------------------------------
  # Work in `pos` space so a release window cannot silently wrap out of the
  # feasible season: a 60-day release starting in late September would otherwise
  # spill into November, which no allocation agreement permits.
  for (V in VOLUMES_AF) for (WL in WINDOW_LEN) {
    if (WL > NDEC) next
    dQ   <- AF_TO_CFS * V / WL
    gain <- log1p(dQ / Qbar) / sigma
    starts <- seq_len(NDEC - WL + 1L)

    tot <- vapply(starts, function(p) {
      ix <- dec_idx[p + seq_len(WL) - 1L]
      as.numeric(B[, ix, drop = FALSE] %*% gain[ix])
    }, numeric(N_SIM))                                   # [n_sim x n_starts]

    m  <- colMeans(tot); p0 <- which.max(m)
    bq <- quantile(apply(tot, 1, which.max), c(a, 1 - a), names = FALSE)

    sched_rows[[length(sched_rows) + 1]] <- data.frame(
      process = proc, site = site, volume_af = V, window_days = WL,
      sustained_cfs = dQ,
      start_pos = p0, start_doy = dec_idx[p0], start_date = date_of(dec_idx[p0]),
      end_date = date_of(dec_idx[min(NDEC, p0 + WL - 1L)]),
      start_lo_date = date_of(dec_idx[max(1, round(bq[1]))]),
      start_hi_date = date_of(dec_idx[min(NDEC, round(bq[2]))]),
      start_width_days = bq[2] - bq[1],
      delta_eta = m[p0], effect = to_effect(m[p0]),
      p_positive = mean(tot[, p0] > 0))

    grid_rows[[length(grid_rows) + 1]] <- data.frame(
      process = proc, site = site, volume_af = V, window_days = WL,
      start_pos = starts, effect = to_effect(m))
  }
}

curves <- bind_rows(curve_rows); costs <- bind_rows(cost_rows)
sched  <- bind_rows(sched_rows); grids <- bind_rows(grid_rows)

# attach the gate so no number travels without its warrant
gsum <- GATE %>% filter(grepl("^beta", form)) %>%
  group_by(process, site) %>%
  summarise(passes = all(passes), .groups = "drop")
curves <- left_join(curves, gsum, by = c("process", "site"))
costs  <- left_join(costs,  gsum, by = c("process", "site"))
sched  <- left_join(sched,  gsum, by = c("process", "site"))

gate_note <- function(d) if (isTRUE(all(d$passes)))
  "Flow signal passed validation in script 05." else
  "*** GATE NOT PASSED. These are arithmetic, not findings. Do not brief them. ***"


# =============================================================================
# FIGURES
# =============================================================================

# --- 06b-f: the curve across the feasible season, with the 1/Q driver ---------
sc <- with(curves, max(abs(effect), na.rm = TRUE) / max(Qbar_cfs, na.rm = TRUE))

f6bf <- ggplot(curves, aes(pos)) +
  geom_hline(yintercept = 0, linetype = 2, colour = PAL[["mute"]]) +
  geom_line(aes(y = Qbar_cfs * sc), colour = PAL[["gold"]], linewidth = 0.8, alpha = 0.85) +
  geom_ribbon(aes(ymin = effect_lo, ymax = effect_hi), fill = PAL[["blue"]], alpha = 0.18) +
  geom_line(aes(y = effect), colour = PAL[["blue"]], linewidth = 1) +
  facet_grid(process ~ site, scales = "free_y") +
  dec_axis +
  scale_y_continuous(sec.axis = sec_axis(~ . / sc, name = "baseline discharge (cfs)")) +
  labs(title = paste0("Figure 6b-f. Benefit of adding ", DELTA_CFS,
                      " cfs, across the ", DW_LABEL),
       subtitle = paste0("Blue = effect of one day's release, with the 95% SIMULTANEOUS band ",
                         "(not pointwise -- see script 06).\n",
                         "Gold = baseline discharge on the right axis. Benefit per cfs scales as 1/Q, so the same\n",
                         "water buys progressively more as the hydrograph recedes. Where blue peaks LATER than\n",
                         "beta(t) does, that gap is the 1/Q leverage and it is the actionable part.\n",
                         gate_note(curves)),
       x = NULL, y = paste0(if (all(curves$process == "survival")) "survival percentage points"
                            else "% change in recruits per stock")) +
  theme_wh

# --- 06b-g: best feasible day, and what the constraint costs ------------------
f6bg <- costs %>%
  mutate(lab = paste0(process, "\n", site)) %>%
  ggplot(aes(y = lab)) +
  geom_linerange(aes(xmin = lo_pos, xmax = hi_pos), colour = PAL[["blue"]], linewidth = 2.2,
                 alpha = 0.5) +
  geom_point(aes(x = match(best_dec_doy, dec_idx)), colour = PAL[["blue"]], size = 3.5) +
  geom_text(aes(x = hi_pos, label = sprintf("  retains %.0f%% of achievable benefit",
                                            100 * frac_retained)),
            hjust = 0, size = 3, colour = "grey30") +
  dec_axis +
  labs(title = "Figure 6b-g. Best feasible release day, and what the season constraint costs",
       subtitle = paste0("Point = best day within the ", DW_LABEL, ". Bar = ",
                         sprintf("%.0f%%", 100 * CRED), " credible interval, recomputed WITHIN the window.\n",
                         "The percentage is how much of the unconstrained optimum survives the constraint:\n",
                         "100% means the best day was already inside the season; a low value means the biology\n",
                         "wants water at a time no allocation mechanism can deliver it.\n",
                         gate_note(costs)),
       x = NULL, y = NULL) +
  theme_wh + theme(plot.margin = margin(5.5, 90, 5.5, 5.5))

# --- 06b-h: start day x window length, within the season ---------------------
f6bh <- grids %>% filter(process == "recruitment") %>%
  ggplot(aes(start_pos, factor(window_days), fill = effect)) +
  geom_tile() +
  geom_point(data = sched %>% filter(process == "recruitment"),
             aes(start_pos, factor(window_days)), inherit.aes = FALSE,
             shape = 21, size = 2.4, colour = "black", fill = "white", stroke = 0.9) +
  scale_fill_gradient2(low = PAL[["red"]], mid = "grey92", high = PAL[["blue"]],
                       midpoint = 0, name = "% change in\nrecruits/stock") +
  facet_grid(site ~ paste0(volume_af, " acre-feet")) +
  dec_axis +
  labs(title = "Figure 6b-h. Every feasible release schedule, scored",
       subtitle = paste0("Colour = benefit of releasing that volume, evenly, starting on that day, over that many days.\n",
                         "White circle = the optimum for that volume and duration. Only starts whose FULL window fits\n",
                         "inside the season are shown, so nothing here spills past ramp-down.\n",
                         gate_note(sched)),
       x = "release start date", y = "release duration (days)") +
  theme_wh

# --- 06b-i: how sharp is the timing decision? --------------------------------
# If the surface is flat across the season, timing does not matter and the
# operational message is "release whenever it is easiest". That is a useful
# finding and it is easy to miss when only the optimum is plotted.
f6bi <- grids %>% filter(process == "recruitment") %>%
  group_by(process, site, volume_af, window_days) %>%
  mutate(rel = effect - max(effect)) %>% ungroup() %>%
  ggplot(aes(start_pos, rel, colour = factor(window_days))) +
  geom_hline(yintercept = 0, linetype = 2, colour = PAL[["mute"]]) +
  geom_line(linewidth = 0.8) +
  scale_colour_viridis_d(name = "duration (days)", option = "D", end = 0.85) +
  facet_grid(site ~ paste0(volume_af, " acre-feet")) +
  dec_axis +
  labs(title = "Figure 6b-i. How much does the timing decision actually matter?",
       subtitle = paste0("Benefit relative to the best feasible schedule (0 = optimal). A curve that stays near zero\n",
                         "means timing is nearly irrelevant within the season -- release when it is operationally\n",
                         "easiest. A deep trough means timing is worth negotiating over.\n",
                         "This is the figure that tells a water user whether to care.\n",
                         gate_note(sched)),
       x = "release start date", y = "benefit forgone (percentage points)") +
  theme_wh

for (nm in c("f6bf", "f6bg", "f6bh", "f6bi"))
  ggsave(file.path(OUT, "figures", paste0("06b_", sub("^f6b", "", nm), ".png")),
         get(nm), width = 10, height = 6, dpi = 150)


# =============================================================================
# SAVE
# =============================================================================
saveRDS(list(curves = curves, costs = costs, schedule = sched, grid = grids,
             dec_idx = dec_idx, window = list(start = DW_START, end = DW_END,
                                              label = DW_LABEL, n_days = NDEC),
             settings = list(n_sim = N_SIM, delta_cfs = DELTA_CFS,
                             volumes_af = VOLUMES_AF, window_lengths = WINDOW_LEN,
                             cred_level = CRED),
             run = Sys.time()),
        file.path(OUT, "models", "decision_window.rds"))

write.csv(curves, file.path(OUT, "tables", "decision_window_daily.csv"), row.names = FALSE)
write.csv(costs,  file.path(OUT, "tables", "decision_window_cost.csv"), row.names = FALSE)
write.csv(sched,  file.path(OUT, "tables", "decision_window_schedule.csv"), row.names = FALSE)

message("\n  wrote 4 figures and 3 tables for the ", DW_LABEL, ".")
message("  decision_window_schedule.csv is the operational deliverable: for each")
message("  volume and duration, when to start and what it buys.")
message("\n  READ decision_window_cost.csv BEFORE briefing anyone. If frac_retained is")
message("  low, the honest message is that the biology wants water at a time the")
message("  allocation system cannot deliver it -- which is itself worth saying.\n")
