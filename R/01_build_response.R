# =============================================================================
# 01_build_response.R
#
# Build the response from the NULL IPM posterior.
#
#   in : <SITE>_IndicatorVarSel_NullMod_Apr26_02.rds
#   out: output/models/response.rds, output/tables/response_summary.csv, figures
#
#        logRS : [M draws x T recruit-years] matrix, one log(R/S) series per
#                posterior draw. Uncertainty in abundance is carried forward as
#                the SPREAD ACROSS DRAWS rather than collapsed to a point estimate.
#
# THE THREE THINGS THIS SCRIPT GETS RIGHT
# ---------------------------------------
# 1. THE NULL MODEL. The posterior must come from the flow-NAIVE IPM. If flow
#    covariates were in the fit, a flow signal is already embedded in R and S
#    before any regression runs, and the analysis partly recovers its own
#    assumption. This is the circularity guard. Script 00 cannot verify it for
#    you -- confirm the filename really is the null fit.
#
# 2. THE STOCK IS BIOMASS, NOT NUMBERS. The IPM's Ricker is
#        lRm = la0 + log(BAdults) - b*BAdults
#    with BAdults in grams. The previous pipeline built log(R/S) using NAdults
#    (adult numbers) while its own comment said BAdults. That meant the flow
#    effect was estimated against one definition of stock and projected with
#    another. config.R defaults to BAdults; set stock_node = "NAdults" only to
#    reproduce the old result side by side.
#
# 3. DRAWS ARE THINNED ON A DETERMINISTIC GRID, not sampled. The kept row index
#    is saved, so demography draw i in Arm B is guaranteed to be the same
#    posterior sample as coefficient draw i. No seed, no drift.
#
# Run:  source("R/00_config.R"); source("R/01_build_response.R")
# =============================================================================

source(here::here("R", "00_config.R"))
suppressPackageStartupMessages({ library(tidyr); library(purrr) })

logRS_list <- list(); meta_list <- list()

for (site in SITES) {

  message("\n== ", site, " ==")
  pp <- posterior_path(site)
  if (!file.exists(pp)) { warning("no posterior: ", pp, " -- skipped"); next }

  obj <- readRDS(pp)
  sl  <- obj$BUGSoutput$sims.list
  if (is.null(sl)) stop("No $BUGSoutput$sims.list in ", pp)

  # ---------------------------------------------------------------------------
  # 1. pull recruits and stock
  # ---------------------------------------------------------------------------
  Rn <- CFG$posterior$recruit_node
  Sn <- CFG$posterior$stock_node

  if (!Rn %in% names(sl))
    stop("Recruit node '", Rn, "' not in the posterior.\n  Nodes present: ",
         paste(head(names(sl), 40), collapse = ", "))
  Rmat <- sl[[Rn]]

  if (Sn %in% names(sl)) {
    Smat <- sl[[Sn]]
  } else {
    fb <- CFG$posterior$stock_fallback
    if (!all(fb %in% names(sl)))
      stop("Stock node '", Sn, "' absent and fallback (",
           paste(fb, collapse = " + "), ") unavailable.")
    message("  '", Sn, "' not saved -> reconstructing as ", paste(fb, collapse = " + "),
            " (standing adult biomass).")
    Smat <- Reduce(`+`, lapply(fb, function(k) sl[[k]]))
  }

  if (!is.matrix(Rmat) || !is.matrix(Smat))
    stop("Recruit and stock nodes must be [draws x years] matrices.")

  # ---------------------------------------------------------------------------
  # 2. calendar years
  # ---------------------------------------------------------------------------
  nyr <- min(ncol(Rmat), ncol(Smat))
  message("  posterior: ", nrow(Rmat), " draws x ", nyr, " year columns")

  # ---------------------------------------------------------------------------
  # Years come from the JAGS parameter CSV, not from an assumed start year.
  #
  # THIS IS THE CHECK THE OLD DESIGN COULD NOT DO. A wrong first_year shifts
  # every lag by a whole year and is invisible downstream -- the analysis still
  # produces plausible coefficients. Reading the real years gives both the start
  # AND the count, so a mismatch against the posterior's column count is a hard
  # error here instead of a silent misalignment three scripts later.
  # ---------------------------------------------------------------------------
  years <- site_years(site)

  if (is.null(years)) {
    years <- CFG$posterior$first_year + seq_len(nyr) - 1L
    warning(site, ": falling back to first_year = ", CFG$posterior$first_year,
            ". Years are ASSUMED contiguous and unverified.", call. = FALSE)
    message("  years: ", min(years), "-", max(years), "  (ASSUMED, not read)")
  } else {
    if (length(years) != nyr)
      stop("\n", site, ": the params CSV gives ", length(years), " years (",
           min(years), "-", max(years), ") but the posterior has ", nyr,
           " year columns.\n",
           "  These must match. One of the following is wrong:\n",
           "    * params_filter() in config.R keeps the wrong rows for this site\n",
           "    * params_year_name in config.R points at the wrong series\n",
           "    * the params CSV and the posterior .rds are from different model runs\n",
           "  CSV: ", attr(years, "path"))
    message("  years: ", min(years), "-", max(years), "  (read from ",
            basename(attr(years, "path")), ", matches the posterior)")
  }

  # ---------------------------------------------------------------------------
  # 3. thin on a deterministic grid
  # ---------------------------------------------------------------------------
  M_all <- nrow(Rmat)
  keep  <- if (M_all > CFG$posterior$max_draws)
    round(seq(1, M_all, length.out = CFG$posterior$max_draws)) else seq_len(M_all)
  Rmat <- Rmat[keep, seq_len(nyr), drop = FALSE]
  Smat <- Smat[keep, seq_len(nyr), drop = FALSE]
  message("  thinned to ", length(keep), " draws (deterministic grid)")

  # ---------------------------------------------------------------------------
  # 4. apply the lag and build log(R/S)
  # ---------------------------------------------------------------------------
  # Recruits counted in year t were spawned in year t - REC_LAG, so they pair
  # with the stock of that earlier year.
  # A recruit year is usable only if its spawning year is ALSO in the record.
  # With contiguous years this is just "drop the first REC_LAG years"; with gaps
  # it drops any pair that straddles one. match() handles both without assuming
  # a fixed offset -- which the old `years[(REC_LAG+1):nyr]` form silently did.
  cand <- years[-seq_len(min(REC_LAG, length(years)))]
  sy_all <- match(cand - REC_LAG, years)
  recruit_years <- cand[!is.na(sy_all)]
  ry <- match(recruit_years, years)
  sy <- match(recruit_years - REC_LAG, years)

  n_dropped <- length(cand) - length(recruit_years)
  if (n_dropped)
    message("  ", n_dropped, " recruit-year(s) dropped: no spawning year ",
            REC_LAG, " years earlier in the record.")

  R <- Rmat[, ry, drop = FALSE]
  S <- Smat[, sy, drop = FALSE]

  if (any(R <= 0) || any(S <= 0)) {
    n_bad <- sum(R <= 0) + sum(S <= 0)
    warning(n_bad, " non-positive R or S values -> those cells become NA.")
    R[R <= 0] <- NA; S[S <= 0] <- NA
  }

  logRS <- log(R) - log(S)

  if (length(recruit_years) < CFG$qc$min_years) {
    warning(site, ": only ", length(recruit_years), " recruit-years. Skipped.")
    next
  }

  # ---------------------------------------------------------------------------
  # 5. WHICH CALENDAR YEAR'S HYDROGRAPH PREDICTS THIS RECRUIT YEAR
  # ---------------------------------------------------------------------------
  # NOT simply recruit_year - REC_LAG. The IPM's indicator-variable selection
  # chose a flow lag PER SITE (Madison.Norris = 3, BigHole.Melrose = 2), encoding
  # a different biological hypothesis at each: spawning-year conditions versus
  # age-0 rearing-year conditions. flow_year() in config.R carries that
  # choice and converts it to the calendar-year axis.
  #
  # A one-year error here is INVISIBLE -- it shifts every flow window by a year
  # and still produces plausible coefficients. The diagnostic below prints the
  # actual calendar span so the mapping can be checked by eye rather than trusted.
  L      <- flow_lag(site)
  flow_yr <- flow_year(recruit_years, site)

  mech <- if (L >= REC_LAG) "spawning-year conditions" else "age-0 rearing-year conditions"
  message("  flow lag: ", L, " year(s)  (", mech, ")")
  message("  recruit year ", min(recruit_years), " <- calendar year ", min(flow_yr),
          "   |   ", max(recruit_years), " <- ", max(flow_yr))
  if (L != REC_LAG)
    message("  NOTE: the flow lag (", L, ") differs from the recruit lag (", REC_LAG,
            "), so the hydrograph year is NOT the spawning year at this site.")
  if (L == REC_LAG)
    message("  NOTE: spawning is Oct-Nov of the hydrograph year, so December\n",
            "        incubation is inside the window but January onward is not.\n",
            "        See docs/notes/CALENDAR_AXIS.md.")


  logRS_list[[site]] <- list(
    logRS = logRS, R = R, S = S,
    recruit_years = recruit_years,
    flow_year = flow_yr, flow_lag = L,
    keep = keep, stock_node = Sn, posterior_file = pp,
    years_all = years,
    years_source = if (is.null(attr(years, "path"))) "first_year (assumed)"
                   else attr(years, "path"))

  meta_list[[site]] <- data.frame(
    site = site, n_draws = nrow(logRS), n_years = ncol(logRS),
    first = min(recruit_years), last = max(recruit_years),
    stock_node = Sn,
    mean_logRS = mean(logRS, na.rm = TRUE),
    sd_between_years = sd(colMeans(logRS, na.rm = TRUE)),
    sd_across_draws  = mean(apply(logRS, 2, sd, na.rm = TRUE)))
}

if (!length(logRS_list)) stop("No site produced a response. Check config.R -> CFG$paths.")
meta <- bind_rows(meta_list)

message("\n== response summary ==")
print(as.data.frame(meta), row.names = FALSE, digits = 3)


# =============================================================================
# 6. THE DIAGNOSTIC THAT MATTERS MOST
# -----------------------------------------------------------------------------
# Two kinds of variation live in log(R/S):
#
#   BETWEEN YEARS  -- real differences in recruitment. This is what flow could
#                     possibly explain.
#   ACROSS DRAWS   -- how uncertain the IPM is about any single year.
#
# If the across-draw spread is comparable to the between-year spread, then most
# of what looks like recruitment variation is the IPM saying "I don't know", and
# no flow covariate will explain it. That is a real ceiling on the analysis and
# you should know where it sits before fitting anything.
# =============================================================================
var_split <- meta %>%
  transmute(site,
            `real between-year variation` = sd_between_years^2,
            `posterior uncertainty`       = sd_across_draws^2) %>%
  pivot_longer(-site, names_to = "source", values_to = "variance")

f1a <- ggplot(var_split, aes(site, variance, fill = source)) +
  geom_col(alpha = 0.85) +
  scale_fill_manual(values = c(PAL[["blue"]], PAL[["red"]]), name = NULL) +
  coord_flip() +
  labs(title = "Figure 1a. How much of log(R/S) is signal, and how much is the IPM being unsure?",
       subtitle = paste0("Blue = variation between years, which flow might explain. Red = spread across posterior draws.\n",
                         "If red is comparable to blue, the ceiling on any flow analysis is low, and that is worth\n",
                         "knowing BEFORE you fit a model rather than after."),
       x = NULL, y = "variance in log(R/S)") +
  theme_wh + theme(legend.position = "bottom")

# --- 1b: the response through time, with the posterior ribbon ----------------
ts <- map_dfr(names(logRS_list), function(s) {
  L <- logRS_list[[s]]
  data.frame(site = s, recruit_year = L$recruit_years,
             med = apply(L$logRS, 2, median, na.rm = TRUE),
             lo  = apply(L$logRS, 2, quantile, .05, na.rm = TRUE, names = FALSE),
             hi  = apply(L$logRS, 2, quantile, .95, na.rm = TRUE, names = FALSE))
})

f1b <- ggplot(ts, aes(recruit_year, med)) +
  geom_hline(yintercept = 0, linetype = 2, colour = PAL[["mute"]]) +
  geom_ribbon(aes(ymin = lo, ymax = hi), fill = PAL[["blue"]], alpha = 0.22) +
  geom_line(colour = PAL[["blue"]], linewidth = 0.8) +
  geom_point(colour = PAL[["blue"]], size = 1.6) +
  facet_wrap(~ site, scales = "free_y") +
  labs(title = "Figure 1b. The response, with posterior uncertainty",
       subtitle = paste0("log(recruits / ", meta$stock_node[1], "). Ribbon = 90% across posterior draws.\n",
                         "Wide years are ones the IPM is unsure about; the model in script 03 weights them down."),
       x = "recruit year", y = "log(R/S)") +
  theme_wh

# --- 1c: stock and recruitment, the Ricker view ------------------------------
sr <- map_dfr(names(logRS_list), function(s) {
  L <- logRS_list[[s]]
  data.frame(site = s, recruit_year = L$recruit_years,
             S = apply(L$S, 2, median, na.rm = TRUE),
             R = apply(L$R, 2, median, na.rm = TRUE),
             S_lo = apply(L$S, 2, quantile, .05, na.rm = TRUE, names = FALSE),
             S_hi = apply(L$S, 2, quantile, .95, na.rm = TRUE, names = FALSE),
             R_lo = apply(L$R, 2, quantile, .05, na.rm = TRUE, names = FALSE),
             R_hi = apply(L$R, 2, quantile, .95, na.rm = TRUE, names = FALSE))
})

f1c <- ggplot(sr, aes(S, R)) +
  geom_linerange(aes(ymin = R_lo, ymax = R_hi), colour = PAL[["mute"]], linewidth = 0.35) +
  geom_linerange(aes(xmin = S_lo, xmax = S_hi), colour = PAL[["mute"]], linewidth = 0.35,
                 orientation = "y") +
  geom_point(aes(colour = recruit_year), size = 2.3) +
  scale_colour_gradient(low = PAL[["gold"]], high = PAL[["ink"]], name = "recruit year") +
  facet_wrap(~ site, scales = "free") +
  labs(title = "Figure 1c. Stock and recruitment from the null IPM",
       subtitle = paste0("Posterior medians with 90% intervals on both axes. Stock is ",
                         meta$stock_node[1], ", lagged ", REC_LAG, " years.\n",
                         "Flow is the deviation from this relationship -- that is what script 03 tries to explain."),
       x = paste0("stock (", meta$stock_node[1], ")"), y = "recruits") +
  theme_wh

for (nm in c("f1a", "f1b", "f1c"))
  ggsave(file.path(OUT, "figures", paste0("01_", nm, ".png")), get(nm),
         width = 9.5, height = 5.2, dpi = 150)


# =============================================================================
# 7. SAVE
# =============================================================================
saveRDS(list(sites = logRS_list, meta = meta, rec_lag = REC_LAG,
             stock_node = CFG$posterior$stock_node, built = Sys.time()),
        file.path(OUT, "models", "response.rds"))
write.csv(meta, file.path(OUT, "tables", "response_summary.csv"), row.names = FALSE)

message("\n  wrote output/models/response.rds")
message("  CHECK BEFORE CONTINUING:")
message("    1. the implied year range printed above")
message("    2. that the posterior file really is the NULL (flow-naive) fit")
message("    3. Figure 1a -- if posterior uncertainty dominates, expect a null result\n")
