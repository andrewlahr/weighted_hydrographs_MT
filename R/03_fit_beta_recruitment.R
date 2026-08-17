# =============================================================================
# 03_fit_beta_recruitment.R  --  the primary model: beta_R(t), a value per day.
#
#   in : output/models/response.rds, output/models/flow.rds
#   out: output/models/beta_recruitment.rds, output/tables/beta_recruitment.csv
#
# THE MODEL
# ---------
#     log(R_t / B_{t-3})  =  intercept + b*stock + SUM_t beta(t) x(t) + error
#
# beta(t) is a curve with a value for all 365 calendar-year days. It says: on this
# day, does a wetter-than-normal year mean better or worse recruitment?
#
# You cannot estimate 365 free numbers from ~40 years, so beta(t) is represented
# as a penalized spline: a smooth curve with a roughness penalty. The penalty
# strength (`sp`) is chosen by REML, and the resulting EFFECTIVE DEGREES OF
# FREEDOM (edf) tell you how much structure the data actually supported. edf near
# 3 means the curve is nearly a straight line; edf near 15 means real day-scale
# structure. **edf is a result, not a setting** -- report it.
#
# WHAT THIS SCRIPT SAVES THAT THE OLD PIPELINE DID NOT
# ----------------------------------------------------
# The FULL 365 x 365 covariance matrix of beta(t). Everything in script 06 --
# simultaneous bands, the distribution of the best day, "is August better than
# June", release-window optimisation -- needs the covariance between days, not
# just the pointwise standard errors. Adjacent days are strongly correlated, and
# ignoring that makes every comparison far too pessimistic.
#
# HOW THE POSTERIOR IS HANDLED
# ----------------------------
# Script 01 gave M draws of the response. We fit beta(t) once per draw. Two
# uncertainty sources are then combined by simulation in script 06:
#     BETWEEN draws -- the IPM's abundance uncertainty      -> cov(beta_draws)
#     WITHIN a draw -- the regression's own uncertainty     -> V_beta
# No Rubin pooling, no unbiasedness assumption.
#
# `sp` is estimated ONCE on the posterior-mean response and then held fixed
# across draws, so beta(t) means the same thing in every draw. Re-estimating it
# per draw would make each draw a slightly different estimand.
#
# THE SEASONAL ANCHOR
# -------------------
# The same data are also fitted with four pre-registered seasonal means. That is
# the confirmatory test -- 4 degrees of freedom, more power, and no tuning. Its
# job is to answer "does flow matter at all?"; beta(t) answers "when?". See
# docs/PROPOSAL_02_daily_estimand.md Part 4.
#
# Run:  source("R/00_config.R"); source("R/03_fit_beta_recruitment.R")
# =============================================================================

source(here::here("R", "00_config.R"))
suppressPackageStartupMessages({ library(tidyr); library(purrr) })

RESP <- readRDS(file.path(OUT, "models", "response.rds"))
FLOW <- readRDS(file.path(OUT, "models", "flow.rds"))
set.seed(CFG$fitting$seed)

K_BETA <- if (is.null(CFG$fitting$k_beta)) 20L else CFG$fitting$k_beta


# The two fitting functions live in R/fn_fit_beta.R so that script 04 (survival)
# uses exactly the same code. Read that file once; it is the only non-obvious
# code in the pipeline.
source(here::here("R", "fn_fit_beta.R"))


# =============================================================================
# FIT EVERY SITE
# =============================================================================
fits <- list()

for (site in names(RESP$sites)) {

  L  <- RESP$sites[[site]]
  FS <- FLOW$sites[[site]]
  if (is.null(FS)) { warning("no flow curves for ", site); next }

  # --- align: recruit year t pairs with the calendar year its parents spawned in --
  # HIGHEST-RISK ASSUMPTION IN THE ANALYSIS. A one-year error shifts the whole
  # curve by a year and is invisible -- it still produces a plausible beta(t).
  # Check against the JAGS indexing.
  # Calendar year chosen by flow_year() in config.R, which honours the IPM's
  # per-site flow-lag selection. See the diagnostic printed by script 01.
  idx  <- match(L$flow_year, FS$years)
  keep <- which(!is.na(idx))
  if (length(keep) < CFG$qc$min_years) {
    warning(site, ": only ", length(keep), " aligned years. Skipped."); next }

  Y      <- L$logRS[, keep, drop = FALSE]              # [M draws x n years]
  Curves <- FS$curves[idx[keep], , drop = FALSE]       # [n years x 365]
  stock  <- apply(L$S[, keep, drop = FALSE], 2, median)
  stock_z <- as.numeric(scale(stock))
  y_bar  <- colMeans(Y)
  n      <- length(y_bar)

  message("\n== ", site, " ==")
  message("  ", n, " years x ", nrow(Y), " draws")

  # --- 1. estimate sp ONCE on the posterior-mean response --------------------
  ref <- fit_beta_curve(y_bar, Curves, k = K_BETA, extra = cbind(S_z = stock_z),
                        estimator = ESTIMATOR, fpc_rule = FPC_RULE, fpc_target_var = FPC_VAR,
                        fpc_min_var = FPC_MIN, fpc_max = FPC_MAX)
  message(sprintf("  sp = %.4g   effective df of beta(t) = %.2f   in-sample R2 = %.3f",
                  ref$sp, ref$edf, ref$r2))
  message(sprintf("  -> effective resolution is roughly 365/%.1f = %.0f days.",
                  ref$edf, 365 / max(ref$edf, 1)))
  message("     Do not report features finer than that. Script 06 measures it properly.")

  # --- 2. refit per draw with sp FIXED --------------------------------------
  M <- nrow(Y)
  beta_draws <- matrix(NA_real_, M, 365)
  scale_draws <- numeric(M)
  # fpc only: the component coefficients per draw. The eigenfunctions do NOT
  # change across draws -- FPCA runs on the hydrographs, which are data, not a
  # posterior quantity -- so only the coefficients move. Capturing them is what
  # lets figure 3e report the posterior direction of each mode.
  fpc_coef <- if (identical(ESTIMATOR, "fpc") && !is.null(ref$n_fpc))
    matrix(NA_real_, M, ref$n_fpc,
           dimnames = list(NULL, paste0("fpc", seq_len(ref$n_fpc)))) else NULL
  pb <- utils::txtProgressBar(min = 0, max = M, style = 3, width = 40)
  for (m in seq_len(M)) {
    f <- fit_beta_curve(Y[m, ], Curves, k = K_BETA, sp = ref$sp,
                        extra = cbind(S_z = stock_z), estimator = ESTIMATOR, fpc_rule = FPC_RULE, fpc_target_var = FPC_VAR,
                        fpc_min_var = FPC_MIN, fpc_max = FPC_MAX)
    beta_draws[m, ] <- f$beta
    scale_draws[m]  <- f$scale
    if (!is.null(fpc_coef) && !is.null(f$n_fpc) && f$n_fpc == ncol(fpc_coef)) {
      cf <- stats::coef(f$model)
      fpc_coef[m, ] <- cf[paste0("fpc", seq_len(ncol(fpc_coef)))]
    }
    utils::setTxtProgressBar(pb, m)
  }
  close(pb)

  # --- 3. the seasonal confirmatory anchor ----------------------------------
  seas_coef <- matrix(NA_real_, M, length(ZWIN) + 2,
                      dimnames = list(NULL, c("(Intercept)", "S_z", ZWIN)))
  seas_se <- seas_coef
  Win <- FS$windows[idx[keep], , drop = FALSE]
  for (m in seq_len(M)) {
    s <- fit_seasonal(Y[m, ], Win, stock_z, ZWIN)
    seas_coef[m, ] <- s$coef; seas_se[m, ] <- s$se
  }
  seas_ref <- fit_seasonal(y_bar, Win, stock_z, ZWIN)
  message(sprintf("  seasonal anchor: in-sample R2 = %.3f (4 flow parameters)", seas_ref$r2))


  if (isTRUE(ref$K_capped))
    warning(site, ": fpc_max (", FPC_MAX, ") is binding, not the variance rule. ",
            "K is set by the cap, so changing fpc_target_var / fpc_min_var will ",
            "have no effect until you raise fpc_max.", call. = FALSE)
  if (isTRUE(ref$K_unstable))
    warning(site, ": a component sits within 0.5% of fpc_min_var. It will drop ",
            "in and out between CV folds. Move the threshold.", call. = FALSE)

  fits[[site]] <- list(
    site = site,
    # functional
    beta_draws = beta_draws,            # [M x 365]  between-draw uncertainty
    Vbeta = ref$Vbeta,                  # [365x365]  within-draw uncertainty
    scale_draws = scale_draws,          # per-draw residual variance, to rescale Vbeta
    scale_ref = ref$scale, edf = ref$edf, sp = ref$sp, r2_insample = ref$r2,
    # --- estimator provenance --------------------------------------------------
    # Which estimator produced this fit, and for fpc, exactly how K was chosen.
    # Without this you cannot tell six months later whether a saved curve came
    # from a smoothness prior or a rank-4 truncation -- and those are different
    # claims about the world. NULL for the penalized arm.
    estimator = ref$estimator,
    fpc_rule = ref$fpc_rule, n_fpc = ref$n_fpc,
    fpc_var_explained = ref$var_explained,
    fpc_var_individual = ref$var_individual,
    fpc_K_cumulative = ref$K_cumulative, fpc_K_individual = ref$K_individual,
    fpc_K_capped = ref$K_capped, fpc_K_unstable = ref$K_unstable,
    fpc_eigenfun = ref$eigenfun,        # [365 x K] the modes themselves
    fpc_scores = ref$scores,            # [n x K]   one score per year per mode
    fpc_coef = fpc_coef,                # [M x K]   per-draw coefficients
    # seasonal anchor
    seasonal_coef = seas_coef, seasonal_se = seas_se,
    seasonal_center = seas_ref$center, seasonal_scale = seas_ref$scale,
    seasonal_r2 = seas_ref$r2,
    # data kept for validation and sensitivity
    Y = Y, Curves = Curves, Win = Win, stock = stock, stock_z = stock_z,
    recruit_years = L$recruit_years[keep], years = FS$years[idx[keep]],
    flow_lag = L$flow_lag,
    Qbar = FS$Qbar, global_sd = FS$global_sd, n_years = n)
}

if (!length(fits)) stop("No site produced a fit. Check the alignment in script 01.")


# =============================================================================
# FIGURES
# =============================================================================
# Pointwise bands here; SIMULTANEOUS bands and the argmax analysis are script 06.
bt <- bind_rows(lapply(fits, function(f) {
  se_tot <- sqrt(diag(f$Vbeta) + apply(f$beta_draws, 2, var))
  data.frame(site = f$site, doy = 1:365, beta = colMeans(f$beta_draws),
             lo = colMeans(f$beta_draws) - 1.96 * se_tot,
             hi = colMeans(f$beta_draws) + 1.96 * se_tot,
             p_pos = colMeans(f$beta_draws > 0),
             edf = f$edf)
}))

f3a <- ggplot(bt, aes(doy, beta)) +
  geom_hline(yintercept = 0, linetype = 2, colour = PAL[["mute"]]) +
  geom_ribbon(aes(ymin = lo, ymax = hi), fill = PAL[["blue"]], alpha = .2) +
  geom_line(colour = "#08306b", linewidth = 1) +
  facet_wrap(~ site, scales = "free_y") +
  scale_x_continuous(breaks = MON_B, labels = MON_L) +
  labs(title = expression(paste("Figure 3a. ", beta[R], "(t) -- the ecological curve")),
       subtitle = paste0("Effect on log(recruits per unit stock) of a one-SD wetter-than-normal day.\n",
                         "Positive = wetter helps. Bands are POINTWISE 95%, combining IPM and regression uncertainty.\n",
                         "Pointwise bands are the wrong tool for locating a peak -- script 06 does that properly.\n",
                         "This is NOT the management curve; see Figure 6a."),
       x = NULL, y = expression(beta[R](t))) + theme_wh

num_sites<-bt$site%>%unique()%>%length()
f3b <- ggplot(bt, aes(doy, p_pos)) +
  geom_hline(yintercept = c(.1, .5, .9), linetype =rep(c(3, 2, 3),num_sites),
             colour = rep(c(PAL[["mute"]], PAL[["mute"]], PAL[["mute"]]),num_sites)) +
  geom_line(colour = PAL[["blue"]], linewidth = .9) +
  facet_wrap(~ site) +
  scale_x_continuous(breaks = MON_B, labels = MON_L) +
  scale_y_continuous(limits = c(0, 1)) +
  labs(title = "Figure 3b. Probability that more water on this day helps",
       subtitle = paste0("Fraction of posterior draws with beta(t) > 0. Above 0.9 or below 0.1 is a consistent sign.\n",
                         "A readable summary for a non-technical audience, and it needs no interval at all."),
       x = NULL, y = "P(beta(t) > 0)") + theme_wh

f3c <- bind_rows(lapply(fits, function(f) data.frame(
  site = f$site, doy = 1:365,
  `within-draw (regression)` = diag(f$Vbeta),
  `between-draw (IPM abundance)` = apply(f$beta_draws, 2, var),
  check.names = FALSE))) %>%
  pivot_longer(-c(site, doy), names_to = "source", values_to = "variance") %>%
  ggplot(aes(doy, variance, fill = source)) +
  geom_area(position = "stack", alpha = .8) +
  scale_fill_manual(values = c(PAL[["gold"]], PAL[["blue"]]), name = NULL) +
  facet_wrap(~ site, scales = "free_y") +
  scale_x_continuous(breaks = MON_B, labels = MON_L) +
  labs(title = expression(paste("Figure 3c. Where does the uncertainty in ", beta, "(t) come from?")),
       subtitle = paste0("If gold dominates, the IPM's abundance uncertainty is the bottleneck and a better flow\n",
                         "model will not help. If blue dominates, more years of flow data would."),
       x = NULL, y = "variance") + theme_wh + theme(legend.position = "bottom")

f3d <- bind_rows(lapply(fits, function(f) data.frame(
  site = f$site, term = sub("^z_", "", ZWIN),
  est = colMeans(f$seasonal_coef[, ZWIN, drop = FALSE]),
  lo = apply(f$seasonal_coef[, ZWIN, drop = FALSE], 2, quantile, .025),
  hi = apply(f$seasonal_coef[, ZWIN, drop = FALSE], 2, quantile, .975)))) %>%
  mutate(term = factor(term, levels = rev(WIN))) %>%
  ggplot(aes(est, term, colour = site)) +
  geom_vline(xintercept = 0, linetype = 2, colour = PAL[["mute"]]) +
  geom_linerange(aes(xmin = lo, xmax = hi), position = position_dodge(.4), linewidth = .8) +
  geom_point(position = position_dodge(.4), size = 2.8) +
  labs(title = "Figure 3d. The seasonal confirmatory anchor",
       subtitle = paste0("Four pre-registered windows, 4 degrees of freedom. This is the POWERED test of whether\n",
                         "flow matters at all. beta(t) then says WHEN, at whatever resolution the data support."),
       x = "effect on log(R/S) per one-SD seasonal flow", y = NULL) +
  theme_wh + theme(legend.position = if (length(fits) > 1) "bottom" else "none")


# ---------------------------------------------------------------------------
# 3e. THE FLOW MODES THEMSELVES (fpc arm only)
# ---------------------------------------------------------------------------
# beta(t) from the fpc estimator is a weighted sum of eigenfunctions. This plots
# the modes that carry the signal, so a reader can see WHAT SHAPE of hydrograph
# variation the model is responding to -- which beta(t) alone does not show.
#
# TWO CHOICES THAT MAKE IT READABLE
#
# 1. SIGN. prcomp eigenvector signs are arbitrary: flip phi_k and negate b_k and
#    beta(t) is unchanged. So each mode is flipped here to make its coefficient
#    POSITIVE. Every panel then reads the same way: blue means a year with MORE
#    water than average on those days recruits BETTER, red means worse. Without
#    this the colours mean opposite things in different panels and the figure is
#    actively misleading.
#
# 2. TWO VARIANCES. "flow var." is how much of the between-year hydrograph
#    variation the mode carries -- it is what SELECTED the mode. "recruit var."
#    is how much of log(R/S) it explains -- it is what makes the mode
#    interesting. They are different questions, and a mode can score high on one
#    and low on the other. Showing both is the honest version of the figure.
#
# READ THE CAVEAT IN THE SUBTITLE. Components were chosen by flow variance and
# then tested against recruitment, so the recruit-variance percentages are
# in-sample and optimistic. Script 05 is what decides whether any of it predicts.
# ---------------------------------------------------------------------------
f3e <- NULL
fpc_fits <- Filter(function(f) !is.null(f$fpc_eigenfun) && !is.null(f$fpc_coef), fits)

if (length(fpc_fits)) {
  modes <- bind_rows(lapply(fpc_fits, function(f) {
    K   <- ncol(f$fpc_coef)
    bbar <- colMeans(f$fpc_coef)                      # posterior mean coefficient
    # share of response variance carried by each mode. The scores are mutually
    # orthogonal, so b_k^2 * var(Z_k) / var(y) is the marginal contribution;
    # it is approximate only because the stock covariate is not orthogonal to
    # the scores.
    ybar <- colMeans(f$Y)
    rvar <- vapply(seq_len(K), function(k)
      100 * (bbar[k]^2 * stats::var(f$fpc_scores[, k])) / stats::var(ybar), numeric(1))
    p_dir <- vapply(seq_len(K), function(k)
      max(mean(f$fpc_coef[, k] > 0), mean(f$fpc_coef[, k] < 0)), numeric(1))

    bind_rows(lapply(seq_len(K), function(k) {
      flip <- if (bbar[k] < 0) -1 else 1             # make the coefficient positive
      data.frame(site = f$site, k = k,
                 doy = 1:365, loading = f$fpc_eigenfun[, k] * flip,
                 flow_var = f$fpc_var_individual[k], recruit_var = rvar[k],
                 p_dir = p_dir[k], coef = bbar[k])
    }))
  }))

  # Order panels by RESPONSE relevance, not by flow variance. The mode explaining
  # the most hydrograph variation is often not the one explaining recruitment,
  # and ordering by flow variance buries that.
  modes <- modes %>%
    mutate(lab = sprintf("FPC%d  (%.1f%% flow var. | %.1f%% recruit var.)",
                         k, flow_var, recruit_var),
           lab = factor(lab, levels = unique(lab[order(-recruit_var)])))

  n_consistent <- modes %>% distinct(site, k, p_dir) %>% filter(p_dir >= 0.90) %>% nrow()

  f3e <- ggplot(modes, aes(doy, loading)) +
    geom_hline(yintercept = 0, linetype = 2, colour = PAL[["mute"]]) +
    geom_ribbon(aes(ymin = pmin(loading, 0), ymax = pmax(loading, 0),
                    fill = loading > 0), alpha = 0.45) +
    geom_line(colour = PAL[["ink"]], linewidth = 0.7) +
    scale_fill_manual(values = c("TRUE" = PAL[["blue"]], "FALSE" = PAL[["red"]]),
                      guide = "none") +
    scale_x_continuous(breaks = MON_B, labels = MON_L) +
    facet_wrap(~ lab, scales = "free_y") +
    labs(title = sprintf("Figure 3e. The flow modes beta(t) is built from (%d retained, %d with a consistent sign)",
                         nrow(distinct(modes, site, k)), n_consistent),
         subtitle = paste0(
           "Each mode is oriented so its regression coefficient is POSITIVE, so the colours read the same way\n",
           "in every panel: BLUE = more water than average on those days goes with BETTER recruitment; RED = worse.\n",
           "'flow var.' is what selected the mode; 'recruit var.' is what makes it interesting -- these are different\n",
           "questions and a mode can score high on one and low on the other. Recruit variance is IN-SAMPLE and\n",
           "optimistic, because components were chosen on flow variance and then tested against recruitment."),
         x = NULL, y = "harmonic loading") +
    theme_wh

  # The scores figure: which YEARS load high on each mode. Turns an abstract
  # shape into "1997 and 2011 looked like this", which is how a reader checks it
  # against what they remember of the hydrology.
  f3f <- bind_rows(lapply(fpc_fits, function(f) {
    K <- ncol(f$fpc_coef); bbar <- colMeans(f$fpc_coef)
    bind_rows(lapply(seq_len(K), function(k) data.frame(
      site = f$site, k = k, year = f$years,
      score = f$fpc_scores[, k] * if (bbar[k] < 0) -1 else 1)))
  })) %>%
    mutate(lab = paste0("FPC", k)) %>%
    ggplot(aes(year, score, fill = score > 0)) +
    geom_hline(yintercept = 0, colour = PAL[["mute"]]) +
    geom_col() +
    scale_fill_manual(values = c("TRUE" = PAL[["blue"]], "FALSE" = PAL[["red"]]),
                      guide = "none") +
    facet_grid(lab ~ site, scales = "free_y") +
    labs(title = "Figure 3f. Which years load high on each flow mode",
         subtitle = paste0("Same orientation as Figure 3e, so blue years are the ones the model expects to recruit well.\n",
                           "Check a few against what you know of the hydrology -- if the blue years are not the ones you\n",
                           "would call wet or early or late in the way the mode suggests, something is wrong upstream."),
         x = "hydrograph year", y = "score") +
    theme_wh
} else {
  f3f <- NULL
}

fig_h <- c(f3a = 5.2, f3b = 5.2, f3c = 5.2, f3d = 5.2, f3e = 4.6, f3f = 6.0)
for (nm in names(fig_h))
  if (exists(nm) && !is.null(get(nm)))
    ggsave(file.path(OUT, "figures", paste0("03_", nm, ".png")), get(nm),
           width = 10, height = fig_h[[nm]], dpi = 150)

saveRDS(list(fits = fits, k_beta = K_BETA, process = "recruitment",
             fitted = Sys.time()),
        file.path(OUT, "models", "beta_recruitment.rds"))
write.csv(bt, file.path(OUT, "tables", "beta_recruitment.csv"), row.names = FALSE)

# Mode summary: one row per retained component. The figure is for reading; this
# is for quoting, and it carries p_direction so nobody has to eyeball the panels
# to decide which modes the data actually support.
if (length(fpc_fits)) {
  mode_tab <- modes %>%
    distinct(site, k, flow_var, recruit_var, p_dir, coef) %>%
    arrange(site, desc(recruit_var)) %>%
    mutate(consistent_sign = p_dir >= 0.90)
  write.csv(mode_tab, file.path(OUT, "tables", "fpc_modes.csv"), row.names = FALSE)
  message("\n  flow modes retained:")
  print(as.data.frame(mode_tab), row.names = FALSE, digits = 3)
  message("  'recruit_var' is IN-SAMPLE. Script 05 decides whether any of it predicts.")
}

message("\n  wrote output/models/beta_recruitment.rds")
message("  effective df by site: ",
        # vapply, not sapply: sapply silently returns a LIST when extraction
        # yields NULL after a rename, and sprintf then fails with "unsupported
        # type" far from the cause. vapply fails at the extraction.
        paste(sprintf("%s=%.1f", names(fits),
                      vapply(fits, function(f) as.numeric(f$edf), numeric(1))),
              collapse = "  "))
message("  NEXT: 04_fit_beta_survival.R, then 05_validate.R. Do not read a peak off")
message("  Figure 3a -- script 06 tells you whether the peak is resolvable.\n")
