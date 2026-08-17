# =============================================================================
# 08_scenarios_bor.R  --  RESEARCH QUESTION 3. How do results change under BoR
#                         forecasted flows?
#
#   in : beta_recruitment.rds, beta_survival.rds, flow.rds, gate.rds, BoR flows
#   out: output/models/scenarios.rds, output/tables/scenario_effects.csv,
#        output/tables/scenario_day_attribution.csv
#
# TWO OUTPUTS, AND THE SECOND IS THE MORE USEFUL ONE
# --------------------------------------------------
# 1. THE MULTIPLIER. eta = SUM_t beta(t) x_scen(t) per scenario, so recruitment
#    multiplies by exp(eta) and survival shifts by eta on the logit scale. One
#    number per scenario. Standard, and what a summary table needs.
#
# 2. THE DAY-BY-DAY ATTRIBUTION -- new, and it answers *why*. Decompose
#
#        eta_scenario - eta_historical = SUM_t beta(t) * [x_scen(t) - x_hist(t)]
#
#    Each day contributes beta(t) times how much that day CHANGED. A scenario can
#    hurt because flow drops on days the fish care about, or because it drops a
#    lot on days they don't. Those have completely different management
#    implications, and the multiplier alone cannot tell them apart.
#
# THE STANDARDIZATION TRAP
# ------------------------
# Scenario flows must be standardized with the TRAINING climatology and TRAINING
# global SD, saved by script 02. If each scenario were standardized against
# itself, a uniformly drier future would be re-centred to look average and the
# entire effect would silently vanish. This is a classic error and it is
# invisible when it happens.
#
# Run:  source("R/00_config.R"); source("R/08_scenarios_bor.R")
# =============================================================================

source(here::here("R", "00_config.R"))
suppressPackageStartupMessages({ library(tidyr); library(purrr); library(lubridate) })

BR   <- readRDS(file.path(OUT, "models", "beta_recruitment.rds"))
BS   <- if (file.exists(file.path(OUT, "models", "beta_survival.rds")))
          readRDS(file.path(OUT, "models", "beta_survival.rds")) else NULL
FLOW <- readRDS(file.path(OUT, "models", "flow.rds"))
GATE <- readRDS(file.path(OUT, "models", "gate.rds"))$gate

site <- SITES[1]
FS <- FLOW$sites[[site]]
bor_path <- path_of(CFG$paths$bor_flow)
if (!file.exists(bor_path))
  stop("BoR flow file not found: ", bor_path, "\n  Set CFG$paths$bor_flow in config.R.")

bor <- readRDS(bor_path)
if (is.list(bor) && !is.data.frame(bor)) bor <- bor[[1]]
message("\n== BoR file ==\n  columns: ", paste(names(bor), collapse = ", "))

flow_col <- intersect(c("Flow_cfs", "Discharge", "flow"), names(bor))[1]
if (is.na(flow_col)) stop("No recognisable flow column in the BoR file.")
grp <- intersect(c("Scenario", "Period", "Type"), names(bor))
message("  grouping by: ", paste(grp, collapse = ", "))


# =============================================================================
# 1. SCENARIO CURVES, ON THE TRAINING SCALE
# =============================================================================
sc <- bor %>%
  mutate(Date = as.Date(Date), doy = yday(Date), year = year(Date)) %>%
  filter(doy <= 365, .data[[flow_col]] > 0) %>%
  left_join(FS$climatology, by = "doy") %>%                 # TRAINING climatology
  # Calendar axis: doy and year come straight from the date, so there is no
  # day-index remapping and no year reassignment -- unlike the water-year
  # version, which needed both here and downstream.
  mutate(flow_std = (log(.data[[flow_col]]) - ch) / FS$global_sd)      # TRAINING sd

# one 365-day curve per scenario-block per calendar year
curves <- sc %>%
  group_by(across(all_of(grp)), year) %>%
  filter(dplyr::n() == 365L) %>% ungroup() %>%
  arrange(across(all_of(grp)), year, doy)

keyed <- curves %>% distinct(across(all_of(grp)), year)
message("  ", nrow(keyed), " complete scenario-calendar-years")
if (!nrow(keyed)) stop("No scenario-calendar-year has a complete 365-day record.")

Xs <- curves %>%
  select(all_of(grp), year, doy, flow_std) %>%
  pivot_wider(names_from = doy, values_from = flow_std)
meta <- Xs[, c(grp, "year")]
Xs <- as.matrix(Xs[, as.character(1:365)])
stopifnot(!anyNA(Xs))

# historical mean curve, the reference the multiplier is relative to
x_hist <- colMeans(FS$curves)

# extrapolation check
rng <- apply(FS$curves, 2, function(v) max(abs(v)))
meta$frac_extrap <- rowMeans(sweep(abs(Xs), 2, rng, ">"))
message(sprintf("  mean fraction of days outside the training flow range: %.1f%%",
                100 * mean(meta$frac_extrap)))


# =============================================================================
# 2. eta PER SCENARIO-YEAR, PER POSTERIOR DRAW
# =============================================================================
score <- function(f, label) {
  Bd <- f$beta_draws                            # [M x 365]
  eta <- Bd %*% t(sweep(Xs, 2, x_hist, "-"))    # centred on historical mean
  data.frame(meta, process = label,
             eta = colMeans(eta),
             eta_lo = apply(eta, 2, quantile, .025, names = FALSE),
             eta_hi = apply(eta, 2, quantile, .975, names = FALSE),
             p_negative = colMeans(eta < 0))
}

parts <- list(score(BR$fits[[site]], "recruitment"))
if (!is.null(BS) && !is.null(BS$fits[[site]]))
  parts[[2]] <- score(BS$fits[[site]], "survival")
sy <- bind_rows(parts)

# readable effect
ms <- if (!is.null(BS) && !is.null(BS$fits[[site]])) BS$fits[[site]]$mean_survival else NA
sy$effect <- ifelse(sy$process == "recruitment",
                    100 * (exp(sy$eta) - 1),
                    100 * (plogis(qlogis(ms) + sy$eta) - ms))
sy$effect_units <- ifelse(sy$process == "recruitment",
                          "% change in recruits per stock",
                          "survival percentage points")

eff <- sy %>%
  group_by(across(all_of(c(grp, "process")))) %>%
  summarise(n_years = dplyr::n(), eta = mean(eta),
            effect = mean(effect), effect_lo = quantile(effect, .1, names = FALSE),
            effect_hi = quantile(effect, .9, names = FALSE),
            p_negative = mean(p_negative), frac_extrap = mean(frac_extrap),
            effect_units = first(effect_units), .groups = "drop") %>%
  arrange(process, effect)

# See the note in 06: the label is "beta:<estimator>", never plain "beta".
passes <- GATE %>% filter(form == paste0("beta:", ESTIMATOR), site == !!site) %>%
  pull(passes)
eff$status <- if (all(passes, na.rm = TRUE)) "supported" else "UNSUPPORTED - gate failed"

message("\n== scenario effects ==")
print(as.data.frame(eff %>% select(-effect_units)), row.names = FALSE, digits = 3)


# =============================================================================
# 3. DAY-BY-DAY ATTRIBUTION  --  WHY a scenario helps or hurts
# =============================================================================
attrib <- bind_rows(lapply(list(list(BR$fits[[site]], "recruitment"),
                                if (!is.null(BS)) list(BS$fits[[site]], "survival")),
  function(z) {
    if (is.null(z) || is.null(z[[1]])) return(NULL)
    b <- colMeans(z[[1]]$beta_draws)
    kk <- meta %>% select(all_of(grp))
    ug <- unique(kk)
    bind_rows(lapply(seq_len(nrow(ug)), function(i) {
      sel <- which(Reduce(`&`, lapply(grp, function(g) kk[[g]] == ug[[g]][i])))
      dx  <- colMeans(Xs[sel, , drop = FALSE]) - x_hist    # flow change, by day
      data.frame(ug[i, , drop = FALSE], process = z[[2]], doy = 1:365,
                 month = MON_L[findInterval(1:365, MON_B)],
                 beta = b, delta_x = dx, contribution = b * dx)
    }))
  }))


# =============================================================================
# FIGURES
# =============================================================================
note <- if (all(passes, na.rm = TRUE)) "beta(t) passed validation in script 05." else
  "*** GATE FAILED in script 05. These are arithmetic, not supported findings. ***"

f8a <- ggplot(eff, aes(effect, reorder(do.call(paste, c(eff[grp], sep = " / ")), effect))) +
  geom_vline(xintercept = 0, linetype = 2, colour = PAL[["red"]]) +
  geom_linerange(aes(xmin = effect_lo, xmax = effect_hi), colour = PAL[["mute"]], linewidth = .7) +
  geom_point(aes(colour = frac_extrap), size = 3.2) +
  scale_colour_gradient(low = PAL[["blue"]], high = PAL[["red"]],
                        name = "fraction of days\noutside training range") +
  facet_wrap(~ process, scales = "free_x") +
  labs(title = "Figure 8a. Effect of BoR scenarios, relative to historical mean flow",
       subtitle = paste0("Bars span the 10th-90th percentile across years within a scenario.\n",
                         "Red points are extrapolating: beta(t) is being evaluated where no data constrained it.\n", note),
       x = "effect", y = NULL) + theme_wh

f8b <- attrib %>%
  ggplot(aes(doy, contribution,
             fill = if ("Scenario" %in% names(attrib)) Scenario else "all")) +
  geom_hline(yintercept = 0, linetype = 2, colour = PAL[["mute"]]) +
  geom_col(width = 1, alpha = .8) +
  facet_grid(process ~ if ("Scenario" %in% names(attrib)) Scenario else ".",
             scales = "free_y") +
  scale_x_continuous(breaks = MON_B, labels = MON_L) +
  labs(title = "Figure 8b. WHICH DAYS make a scenario better or worse?",
       subtitle = paste0("beta(t) x (scenario flow - historical flow), day by day. Summing gives the multiplier.\n",
                         "A scenario can hurt because flow drops on days that matter, or drops a lot on days that\n",
                         "don't. Those have different management responses -- the multiplier alone cannot tell them apart."),
       x = NULL, y = "contribution to eta", fill = NULL) +
  theme_wh + theme(legend.position = "none")

f8c <- attrib %>%
  filter(process == "recruitment") %>%
  select(all_of(grp), doy, beta, delta_x) %>%
  pivot_longer(c(beta, delta_x)) %>%
  mutate(name = recode(name, beta = "beta(t): where the fish are sensitive",
                       delta_x = "scenario minus historical flow")) %>%
  ggplot(aes(doy, value, colour = if ("Scenario" %in% names(attrib)) Scenario else "all")) +
  geom_hline(yintercept = 0, linetype = 2, colour = PAL[["mute"]]) +
  geom_line(linewidth = .7) +
  facet_wrap(~ name, ncol = 1, scales = "free_y") +
  scale_x_continuous(breaks = MON_B, labels = MON_L) +
  labs(title = "Figure 8c. Do the scenario changes land where the fish are sensitive?",
       subtitle = "The product of these two panels is Figure 8b. Overlap is what determines whether a scenario matters.",
       x = NULL, y = NULL, colour = NULL) +
  theme_wh + theme(legend.position = "bottom")

for (nm in c("f8a", "f8b", "f8c"))
  ggsave(file.path(OUT, "figures", paste0("08_", nm, ".png")), get(nm),
         width = 10, height = if (nm == "f8c") 6 else 5.2, dpi = 150)

saveRDS(list(scenario_years = sy, effects = eff, attribution = attrib,
             x_hist = x_hist, gate_passed = all(passes, na.rm = TRUE), run = Sys.time()),
        file.path(OUT, "models", "scenarios.rds"))
write.csv(eff, file.path(OUT, "tables", "scenario_effects.csv"), row.names = FALSE)
write.csv(attrib, file.path(OUT, "tables", "scenario_day_attribution.csv"), row.names = FALSE)
message("\n  wrote output/models/scenarios.rds and 2 tables\n")
