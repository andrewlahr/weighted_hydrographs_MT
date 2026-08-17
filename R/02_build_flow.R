# =============================================================================
# 02_build_flow.R
#
# Daily discharge -> a standardized 365-day curve per calendar year.
#
#   in : <SITE>_imputed.csv   (Date, Flow_imputed)
#   out: output/models/flow.rds, output/tables/flow_windows.csv, figures
#
#        curves      [n_years x 365]  standardized anomalies, THE MODEL INPUT
#        Qbar        length-365             geometric-mean baseline discharge, cfs
#        global_sd   scalar                 the standardization scale
#        windows     seasonal means, for the confirmatory anchor model only
#
# WHY THE FULL 365 COLUMNS ARE KEPT
# ---------------------------------
# The primary estimand is beta(t), a value for every day of the year. The four
# seasonal means are also computed, but only as the pre-registered confirmatory
# test (see docs/PROPOSAL_02_daily_estimand.md, Part 4). Both come out of here.
#
# WHY Qbar(t) IS SAVED -- READ THIS
# ---------------------------------
# beta(t) is the effect of a one-SD standardized log anomaly. A manager releases
# CFS. Converting between them requires the baseline discharge on that day:
#
#     delta_eta(t) = beta(t)/sigma * log(1 + deltaQ / Qbar(t))
#
# so the benefit per cfs is beta(t) / (sigma * Qbar(t)). Because discharge here
# spans more than an order of magnitude across the year, dividing by Qbar(t)
# RESHAPES the curve and can change which season looks most valuable. Qbar is
# therefore not a detail -- it is half of the management answer.
#
# Qbar(t) = exp(mean of log Q on day t) -- the geometric mean, which is the right
# centre because the model works in logs.
#
# THE THREE STANDARDIZATION STEPS
#   1. log(flow)                  -- flow is multiplicative; logs make it additive
#   2. minus the day-of-year mean -- removes the seasonal cycle, leaving the anomaly
#   3. divided by ONE global SD   -- one number for the whole record, not per day.
#      A per-day SD would make a quiet winter wobble look as important as a swing
#      at the snowmelt peak.
#
# CALENDAR-YEAR AXIS (1 Jan - 31 Dec, day 1 = 1 January).
#
# Chosen for interpretability: the results go to water managers, irrigators and
# lease-holders who work in calendar years. The cost is real and is stated rather
# than hidden -- brown trout spawn in autumn and emerge the following spring, so
# that single biological window straddles the year boundary and no calendar year
# contains all of it. The site-specific flow lag, not the axis, is what selects
# between the spawning-year and rearing-year hypotheses. A mechanism running
# continuously across the turn of the year (incubation, Dec-Mar) is split between
# two lag years and will read weakly in both. See docs/notes/CALENDAR_AXIS.md.
#
# Run:  source("R/00_config.R"); source("R/02_build_flow.R")
# =============================================================================

source(here::here("R", "00_config.R"))
suppressPackageStartupMessages({ library(lubridate); library(tidyr); library(purrr) })

flow_all <- list()

for (site in SITES) {

  message("\n== ", site, " ==")
  fp <- flow_path(site)
  if (!file.exists(fp)) { warning("no flow file: ", fp, " -- skipped"); next }

  q <- read.csv(fp, stringsAsFactors = FALSE) %>%
    mutate(Date = ymd(Date), year = year(Date), doy = yday(Date)) %>%
    filter(!is.na(Flow_imputed), Flow_imputed > 0, doy <= 365)

  complete <- q %>% count(year) %>% filter(n == 365L) %>% pull(year)
  q <- q %>% filter(year %in% complete)
  message("  ", length(complete), " complete calendar years (",
          min(complete), "-", max(complete), ")")

  # --- standardize, keeping the constants ------------------------------------
  clim <- q %>% group_by(doy) %>%
    summarise(ch = mean(log(Flow_imputed)), .groups = "drop")

  q <- q %>% left_join(clim, by = "doy") %>%
    mutate(anomaly = log(Flow_imputed) - ch)
  global_sd <- sd(q$anomaly)
  q <- q %>% mutate(flow_std = anomaly / global_sd)
  message(sprintf("  global SD = %.4f", global_sd))

  # --- calendar-year axis ------------------------------------------------------
  # `doy` (1 = 1 Jan) and `year` come straight from the date, so there is nothing
  # to remap. The water-year version needed a day-index shift and a year
  # reassignment here; both are gone, and so is the wrap-around bookkeeping they
  # forced downstream (see the note on the incubation window at the foot of this
  # file). Complete-year filtering already happened above.

  # --- THE MODEL INPUT: one row per year, one column per day of year -
  curves <- q %>%
    select(year, doy, flow_std) %>%
    arrange(year, doy) %>%
    pivot_wider(names_from = doy, values_from = flow_std) %>%
    arrange(year)
  wy <- curves$year
  curves <- as.matrix(curves[, -1, drop = FALSE])
  colnames(curves) <- 1:365
  stopifnot(ncol(curves) == 365L, !anyNA(curves))

  # --- baseline discharge on the calendar-year axis, in cfs ---------------------
  Qbar <- q %>% group_by(doy) %>%
    summarise(Qbar = exp(mean(log(Flow_imputed))), .groups = "drop") %>%
    arrange(doy) %>% pull(Qbar)
  message(sprintf("  baseline discharge: %.0f cfs (min, %s) to %.0f cfs (max, %s)",
                  min(Qbar), MON_L[findInterval(which.min(Qbar), MON_B)],
                  max(Qbar), MON_L[findInterval(which.max(Qbar), MON_B)]))
  message("  -> that ", sprintf("%.0f", max(Qbar) / min(Qbar)),
          "-fold seasonal range is why beta(t)/Qbar(t) is a different curve from beta(t).")

  # --- seasonal means, for the confirmatory anchor only ----------------------
  win <- vapply(WINDOWS, function(w) rowMeans(curves[, w[1]:w[2], drop = FALSE]),
                numeric(nrow(curves)))
  if (is.null(dim(win))) win <- matrix(win, nrow = nrow(curves))
  colnames(win) <- WIN

  flow_all[[site]] <- list(
    site = site, curves = curves, years = wy, Qbar = Qbar,
    global_sd = global_sd, climatology = clim, windows = win, daily = q)
}

if (!length(flow_all)) stop("No site produced flow curves. Check config.R -> CFG$paths$flow_dir.")

flow_windows <- bind_rows(lapply(flow_all, function(f)
  data.frame(site = f$site, year = f$years, f$windows)))


# =============================================================================
# DIAGNOSTIC FIGURES
# =============================================================================
S1 <- flow_all[[1]]
daily1 <- S1$daily

f2a <- daily1 %>%
  transmute(year, doy,
            `1. log discharge` = log(Flow_imputed),
            `2. anomaly (minus day-of-year mean)` = anomaly,
            `3. standardized (divided by one SD)` = flow_std) %>%
  pivot_longer(-c(year, doy), names_to = "step", values_to = "value") %>%
  ggplot(aes(doy, value, group = year)) +
  geom_line(alpha = .2, linewidth = .3, colour = PAL[["blue"]]) +
  facet_wrap(~ step, scales = "free_y") +
  scale_x_continuous(breaks = MON_B, labels = MON_L) +
  labs(title = paste0("Figure 2a. Standardizing the hydrograph -- ", S1$site),
       subtitle = "One line per calendar year. Axis runs Jan to Dec.",
       x = NULL, y = NULL) + theme_wh

# --- THE FIGURE THAT EXPLAINS WHY Qbar MATTERS -------------------------------
f2b <- data.frame(doy = 1:365, Qbar = S1$Qbar) %>%
  mutate(per_cfs = 1 / (S1$global_sd * Qbar),
         per_cfs_rel = per_cfs / max(per_cfs)) %>%
  pivot_longer(c(Qbar, per_cfs_rel)) %>%
  mutate(name = recode(name,
    Qbar = "baseline discharge (cfs)",
    per_cfs_rel = "leverage per cfs added: 1/(sigma x Qbar), scaled to max = 1")) %>%
  ggplot(aes(doy, value)) +
  geom_line(linewidth = 1, colour = PAL[["blue"]]) +
  facet_wrap(~ name, scales = "free_y", ncol = 1) +
  scale_x_continuous(breaks = MON_B, labels = MON_L) +
  labs(title = "Figure 2b. Why the management curve is not beta(t)",
       subtitle = paste0("Top: baseline flow. Bottom: how much a single cfs moves the standardized anomaly.\n",
                         "The same 10 cfs is a large proportional change at base flow and a negligible one at the\n",
                         "snowmelt peak. The management curve is beta(t) TIMES the bottom panel -- see script 06."),
       x = NULL, y = NULL) + theme_wh

f2c <- as.data.frame(as.table(cor(as.matrix(flow_windows[, WIN]), use = "complete.obs"))) %>%
  ggplot(aes(Var1, Var2, fill = Freq)) +
  geom_tile(colour = "white", linewidth = 1) +
  geom_text(aes(label = sprintf("%.2f", Freq)), size = 3.6, colour = PAL[["ink"]]) +
  scale_fill_gradient2(low = PAL[["red"]], mid = "white", high = PAL[["blue"]],
                       midpoint = 0, limits = c(-1, 1), name = "r") +
  labs(title = "Figure 2c. Correlation between the four seasonal windows",
       subtitle = "For the confirmatory anchor model only. Above |0.7| the model cannot separate those seasons.",
       x = NULL, y = NULL) + theme_wh

# --- how much do the curves themselves vary, day by day? --------------------
f2d <- data.frame(doy = 1:365,
                  sd_across_years = apply(S1$curves, 2, sd)) %>%
  ggplot(aes(doy, sd_across_years)) +
  geom_hline(yintercept = 1, linetype = 2, colour = PAL[["mute"]]) +
  geom_line(linewidth = .9, colour = PAL[["blue"]]) +
  scale_x_continuous(breaks = MON_B, labels = MON_L) +
  labs(title = "Figure 2d. Where is there year-to-year variation to learn from?",
       subtitle = paste0("SD of the standardized anomaly across years, by day. Dashed = the global average of 1.\n",
                         "beta(t) can only be estimated where flow actually VARIES between years. Days with little\n",
                         "variation will have wide uncertainty no matter how much the fish care about them."),
       x = NULL, y = "SD across years") + theme_wh

for (nm in c("f2a", "f2b", "f2c", "f2d"))
  ggsave(file.path(OUT, "figures", paste0("02_", nm, ".png")), get(nm),
         width = 9.5, height = if (nm == "f2b") 6 else 5, dpi = 150)

saveRDS(list(sites = flow_all, window_defs = WINDOWS, built = Sys.time()),
        file.path(OUT, "models", "flow.rds"))
write.csv(flow_windows, file.path(OUT, "tables", "flow_windows.csv"), row.names = FALSE)

message("\n  wrote output/models/flow.rds")
message("  contains: curves [years x 365], Qbar [365], global_sd, seasonal windows\n")
