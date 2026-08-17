# =============================================================================
# 04_fit_beta_survival.R  --  beta_S(t): when does flow affect ADULT SURVIVAL?
#
#   in : the null IPM posterior, output/models/flow.rds
#   out: output/models/beta_survival.rds, output/tables/beta_survival.csv
#
# WHY SURVIVAL IS A SEPARATE CURVE, NOT A COPY OF THE RECRUITMENT ONE
# -------------------------------------------------------------------
# 1. THE LAG IS DIFFERENT. Recruitment uses a 3-year lag because it maps spawning
#    to age-2 recruits. Adult survival over year t responds to conditions IN year
#    t, or the year before for overwinter effects. Inheriting lag 3 would be a
#    different biological hypothesis. Lags 0 and 1 are fitted and gated
#    separately here, and the winner's p-value is Bonferroni-adjusted.
#
# 2. THE RESPONSE IS THE PROCESS DEVIATE, NOT SURVIVAL ITSELF. The null IPM
#    already explains part of survival with density:
#        logit(s_t) = phi0 + phiN * NALL[t-1]/100 + deviate
#    Regressing raw survival on flow would re-attribute density-driven variation
#    to flow, because flow drives recruitment which drives density at a lag. So
#    the response is what the null model LEAVES UNEXPLAINED:
#        e_t = logit(s_t) - phi0 - phiN * NALL[t-1]/100
#    This is the exact analogue of using log(R/S) for recruitment.
#
# 3. IT IS ADDITIVE ON THE LOGIT SCALE. beta_S(t) shifts logit(survival), not
#    survival. A "multiplier" is meaningless for a probability. Script 06 converts
#    to survival points at the observed mean rate, which is what a manager reads.
#
# WHY THIS IS THE SCIENTIFICALLY INTERESTING CURVE
# ------------------------------------------------
# If beta_R(t) and beta_S(t) peak at DIFFERENT times of year, the two vital rates
# are limited by flow in different seasons -- which tells you which life stage is
# the bottleneck and when. That divergence is the core of research question 2.
#
# Run:  source("R/00_config.R"); source("R/04_fit_beta_survival.R")
# =============================================================================

source(here::here("R", "00_config.R"))
source(here::here("R", "fn_fit_beta.R"))
suppressPackageStartupMessages({ library(tidyr); library(purrr) })

FLOW   <- readRDS(file.path(OUT, "models", "flow.rds"))
RESP   <- readRDS(file.path(OUT, "models", "response.rds"))
K_BETA <- if (is.null(CFG$fitting$k_beta)) 20L else CFG$fitting$k_beta
SURV_LAGS <- if (is.null(CFG$fitting$survival_lags)) 0:1 else CFG$fitting$survival_lags
set.seed(CFG$fitting$seed)

fits <- list()

for (site in SITES) {

  message("\n== ", site, " ==")
  pp <- posterior_path(site)
  if (!file.exists(pp)) { warning("no posterior: ", pp); next }
  FS <- FLOW$sites[[site]]
  if (is.null(FS)) { warning("no flow curves for ", site); next }

  sl <- readRDS(pp)$BUGSoutput$sims.list
  need <- c("Surv", "lSurv0", "b6S")
  miss <- setdiff(need, names(sl))
  if (length(miss)) {
    warning(site, ": missing node(s) ", paste(miss, collapse = ", "),
            ". Survival curve cannot be fitted. Re-run the IPM with Surv[] monitored.")
    next
  }

  # --- reuse the SAME thinned draws as the recruitment arm -------------------
  # Non-negotiable: survival draw i must be the same posterior sample as
  # recruitment draw i, or the two curves cannot be combined in script 07.
  keep <- RESP$sites[[site]]$keep

  Surv <- sl$Surv[keep, , drop = FALSE]
  NALL <- if (!is.null(sl$NALL)) sl$NALL[keep, , drop = FALSE] else {
    if (!all(c("N2", "N3", "N4") %in% names(sl)))
      stop("NALL absent and N2/N3/N4 unavailable to reconstruct it.")
    message("  NALL not monitored; reconstructing as N2 + N3 + N4.")
    (sl$N2 + sl$N3 + sl$N4)[keep, , drop = FALSE]
  }
  phi0 <- as.numeric(sl$lSurv0)[keep]
  phiN <- as.numeric(sl$b6S)[keep]

  nyr <- min(ncol(Surv), ncol(NALL))

  # Years MUST come from the same source script 01 used. If 01 reads the real
  # years and this script assumes contiguity from first_year, the recruitment and
  # survival arms end up indexed on different calendars, every survival lag is
  # offset against every recruitment lag, and nothing anywhere complains.
  years <- site_years(site)
  years <- years[4:length(years)]
  if (is.null(years)) {
    years <- CFG$posterior$first_year + seq_len(nyr) - 1L
    warning(site, ": survival years fall back to first_year. ",
            "Confirm script 01 used the same fallback.", call. = FALSE)
  } else if (length(years) != nyr) {
    stop("\n", site, ": params CSV gives ", length(years), " years but the ",
         "survival nodes have ", nyr, " columns. See the same check in script 01.")
  }

  # survival in year t is driven by density at t-1, so usable years start at 2
  ti <- 2:nyr
  S_t   <- pmin(pmax(Surv[, ti, drop = FALSE], 1e-6), 1 - 1e-6)
  N_prev <- NALL[, ti - 1L, drop = FALSE]
  E <- qlogis(S_t) - phi0 - phiN * (N_prev / 100)      # the process deviate
  surv_years <- years[ti]

  message(sprintf("  survival deviate: %d draws x %d years | SD %.4f",
                  nrow(E), ncol(E), sd(E)))
  if (!is.null(sl$sigmaSurv))
    message(sprintf("  sanity check: that SD should be near sigmaSurv (median %.4f)",
                    median(as.numeric(sl$sigmaSurv)[keep])))

  # ---------------------------------------------------------------------------
  # LAG SWEEP. On the calendar axis the mapping is direct: survival year t is
  # matched to calendar year t - Lg. Lag 0 is contemporaneous (flow during the
  # year survival is measured); lag 1 is the preceding year, which is the
  # overwinter hypothesis.
  #
  # This lag is SEPARATE from the recruitment flow lag in config.R. Survival
  # responds to conditions in the year it is measured, not at a spawning lag, so
  # it is swept here and gated in script 05 rather than inherited.
  # ---------------------------------------------------------------------------
  lag_fits <- list()
  for (Lg in SURV_LAGS) {
    idx  <- match(surv_years - Lg, FS$years)
    ok   <- which(!is.na(idx))
    if (length(ok) < CFG$qc$min_years) {
      message(sprintf("  lag %d: only %d aligned years, skipped.", Lg, length(ok)))
      next
    }
    Ek <- E[, ok, drop = FALSE]
    Ck <- FS$curves[idx[ok], , drop = FALSE]
    ref <- fit_beta_curve(colMeans(Ek), Ck, k = K_BETA, estimator = ESTIMATOR, fpc_rule = FPC_RULE, fpc_target_var = FPC_VAR,
                        fpc_min_var = FPC_MIN, fpc_max = FPC_MAX)
    message(sprintf("  lag %d: %d years | sp = %.4g | edf = %.2f | in-sample R2 = %.3f",
                    Lg, length(ok), ref$sp, ref$edf, ref$r2))
    # Two DIFFERENT year vectors, and they must not share a name. An earlier
    # version had `years =` twice here: R builds a length-2 list where `$years`
    # silently returns only the first, so the hydrograph provenance was lost and
    # `surv_years` and `years` downstream both held the response years.
    lag_fits[[as.character(Lg)]] <- list(lag = Lg, ref = ref, E = Ek, Curves = Ck,
                                         surv_years = surv_years[ok],       # response
                                         flow_years = FS$years[idx[ok]])    # predictor
  }
  if (!length(lag_fits)) { warning(site, ": no usable survival lag."); next }

  # --- refit the best-fitting lag across all draws --------------------------
  # NOTE: choosing the lag by in-sample fit and then quoting its statistics is
  # post-selection inference. Script 05 gates every lag and Bonferroni-adjusts
  # the winner. The full sweep is saved so the whole surface is visible.
  best <- names(lag_fits)[which.max(sapply(lag_fits, function(z) z$ref$r2))]
  B <- lag_fits[[best]]
  message("  -> refitting lag ", B$lag, " across all draws")

  M <- nrow(B$E)
  beta_draws <- matrix(NA_real_, M, 365); scale_draws <- numeric(M)
  pb <- utils::txtProgressBar(min = 0, max = M, style = 3, width = 40)
  for (m in seq_len(M)) {
    f <- fit_beta_curve(B$E[m, ], B$Curves, k = K_BETA, sp = B$ref$sp, estimator = ESTIMATOR, fpc_rule = FPC_RULE, fpc_target_var = FPC_VAR,
                        fpc_min_var = FPC_MIN, fpc_max = FPC_MAX)
    beta_draws[m, ] <- f$beta; scale_draws[m] <- f$scale
    utils::setTxtProgressBar(pb, m)
  }
  close(pb)

  fits[[site]] <- list(
    site = site, lag_sweep = lapply(lag_fits, function(z)
      data.frame(lag = z$lag, n_years = length(z$surv_years), edf = z$ref$edf,
                 sp = z$ref$sp, r2_insample = z$ref$r2)),
    beta_draws = beta_draws, Vbeta = B$ref$Vbeta, scale_draws = scale_draws,
    scale_ref = B$ref$scale, edf = B$ref$edf, sp = B$ref$sp, r2_insample = B$ref$r2,
    # --- estimator provenance --------------------------------------------------
    # Which estimator produced this fit, and for fpc, exactly how K was chosen.
    # Without this you cannot tell six months later whether a saved curve came
    # from a smoothness prior or a rank-4 truncation -- and those are different
    # claims about the world. NULL for the penalized arm.
    estimator = B$ref$estimator,
    fpc_rule = B$ref$fpc_rule, n_fpc = B$ref$n_fpc,
    fpc_var_explained = B$ref$var_explained,
    fpc_var_individual = B$ref$var_individual,
    fpc_K_cumulative = B$ref$K_cumulative, fpc_K_individual = B$ref$K_individual,
    fpc_K_capped = B$ref$K_capped, fpc_K_unstable = B$ref$K_unstable,
    E = B$E, Curves = B$Curves,
    surv_years = B$surv_years,      # years the deviate was measured in
    flow_years = B$flow_years,      # calendar years of the hydrographs used
    surv_lag = B$lag,               # which lag won the sweep

    mean_survival = mean(plogis(qlogis(mean(S_t)))),
    Qbar = FS$Qbar, global_sd = FS$global_sd, n_years = length(B$surv_years))
}

if (!length(fits)) {
  message("\n  NO SURVIVAL CURVE FITTED. Downstream scripts will run recruitment only.")
  message("  If Surv[] was not monitored per year in the null IPM, it must be re-run.\n")
} else {

  bt <- bind_rows(lapply(fits, function(f) {
    se <- sqrt(diag(f$Vbeta) + apply(f$beta_draws, 2, var))
    data.frame(site = f$site, lag = f$surv_lag, doy = 1:365,
               beta = colMeans(f$beta_draws),
               lo = colMeans(f$beta_draws) - 1.96 * se,
               hi = colMeans(f$beta_draws) + 1.96 * se,
               p_pos = colMeans(f$beta_draws > 0))
  }))

  f4a <- ggplot(bt, aes(doy, beta)) +
    geom_hline(yintercept = 0, linetype = 2, colour = PAL[["mute"]]) +
    geom_ribbon(aes(ymin = lo, ymax = hi), fill = PAL[["green"]], alpha = .2) +
    geom_line(colour = PAL[["green"]], linewidth = 1) +
    facet_wrap(~ paste0(site, "  (lag ", lag, ")"), scales = "free_y") +
    scale_x_continuous(breaks = MON_B, labels = MON_L) +
    labs(title = expression(paste("Figure 4a. ", beta[S], "(t) -- flow and adult survival")),
         subtitle = paste0("Effect on logit(adult survival) of a one-SD wetter-than-normal day.\n",
                           "Response is the survival process deviate: what the density-dependent null model\n",
                           "leaves unexplained. Pointwise 95% bands; script 06 locates peaks properly."),
         x = NULL, y = expression(beta[S](t))) + theme_wh

  swp <- bind_rows(lapply(fits, function(f) bind_rows(f$lag_sweep) %>%
                            mutate(site = f$site, chosen = lag == f$surv_lag)))
  f4b <- ggplot(swp, aes(factor(lag), r2_insample, fill = chosen)) +
    geom_col(alpha = .85) +
    scale_fill_manual(values = c("FALSE" = PAL[["mute"]], "TRUE" = PAL[["green"]]),
                      guide = "none") +
    facet_wrap(~ site) +
    labs(title = "Figure 4b. Survival flow-signal lag sweep",
         subtitle = paste0("Lag 0 = conditions in the same year as the survival interval; lag 1 = the previous year\n",
                           "(overwinter). In-sample R2 shown; script 05 gates every lag out of sample and\n",
                           "Bonferroni-adjusts the winner for having looked at more than one."),
         x = "flow lag (years)", y = "in-sample R-squared") + theme_wh

  for (nm in c("f4a", "f4b"))
    ggsave(file.path(OUT, "figures", paste0("04_", nm, ".png")), get(nm),
           width = 9.5, height = 5, dpi = 150)

  saveRDS(list(fits = fits, k_beta = K_BETA, process = "survival", fitted = Sys.time()),
          file.path(OUT, "models", "beta_survival.rds"))
  write.csv(bt, file.path(OUT, "tables", "beta_survival.csv"), row.names = FALSE)

  message("\n  wrote output/models/beta_survival.rds")
  # `surv_lag`, not `lag`. vapply with an explicit template rather than sapply:
  # sapply silently returns a LIST when extraction yields NULL, and sprintf then
  # fails with "unsupported type" far from the real cause. vapply fails at the
  # extraction, naming the field.
  message("  lags chosen: ",
          paste(sprintf("%s=%d", names(fits),
                        vapply(fits, function(f) as.integer(f$surv_lag), integer(1))),
                collapse = "  "), "\n")
}
