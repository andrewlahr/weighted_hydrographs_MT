# =============================================================================
# 10_rulecurve.R  --  equilibrium carrying capacity (K) and maximum surplus
#                     production (MS) under BoR summer-flow scenarios.
#
#   in : <SITE>_rulecurve_inputs.rds  (FishCast export: covarLagIn1Real, Flows,
#                                      Weight3/4, Survival, RecLag, posterior_file)
#        the FLOW-INFORMED IPM posterior named inside that export
#        <SITE>_BOR_future_flow_data.RDS
#   out: output/models/rulecurve.rds, output/tables/rulecurve_*.csv, figures
#
# Ported from RUN_norris_rulecurve_BoR.R. The K/MS mathematics is unchanged; what
# changed is that paths, sites and outputs now come from config.R like every other
# script, so adding a site is a config edit rather than a copy of this file.
#
# =============================================================================
# THIS ARM IS DELIBERATELY DIFFERENT FROM THE REST OF THE PIPELINE
# -----------------------------------------------------------------------------
# Scripts 01-09 ask WHEN water helps: beta(t) over 365 days, from the NULL IPM.
# This script asks WHERE THE POPULATION SETTLES if the summer MEAN flow shifts.
# Different question, different inputs, and two differences that must not be
# "tidied up":
#
# 1. IT READS THE FLOW-INFORMED IPM.
#    It needs b1r, b12r (recruitment) and b1S, b12S (survival) -- the IPM's own
#    fitted flow response. The null posterior has no such terms. There is no
#    circularity concern because this script does not ESTIMATE a flow effect; it
#    propagates the one the IPM already fitted to its equilibrium consequence.
#
# 2. IT USES ITS OWN STANDARDIZATION.
#    beta(t) integrates daily anomaly curves scaled per day-of-year. Here the
#    covariate is the z of the ANNUAL SUMMER MEAN, and it must sit on exactly the
#    scale the IPM was fitted with. GATE 1 below verifies that to 1e-10 and stops
#    if it cannot. Forcing this onto the script-02 constants would put la0, b and
#    b1r off-scale, and every K would be wrong while looking entirely plausible.
#
# Run:  source("R/00_config.R"); source("R/10_rulecurve.R")
# =============================================================================

source(here::here("R", "00_config.R"))
suppressPackageStartupMessages({ library(tidyr); library(purrr); library(lubridate) })

RC   <- CFG$rulecurve
site <- SITES[[1]]
hdr  <- function(x) message("\n", strrep("=", 72), "\n  ", x, "\n", strrep("=", 72))

if (length(SITES) > 1)
  message("NOTE: the rule-curve arm runs one site at a time; using ", site,
          ".\n  Re-run with CFG$sites$active set to another site for the rest.")


# =============================================================================
# 1. LOAD
# =============================================================================
hdr(paste("rule curve:", site))

exp_path <- path_of(rulecurve_export_path(site))
if (!file.exists(exp_path))
  stop("FishCast export not found:\n  ", exp_path,
       "\n  This arm needs covarLagIn1Real, Flows, Weight3/4, Survival and RecLag.",
       "\n  Produce it with the Part 0 block of BigStablePop, or point",
       "\n  rulecurve_export_path() in config.R at the right file.")

EX <- readRDS(exp_path)
message(sprintf("  export: season %s | global %s | RecLag %d | %d training years (%s-%s)",
                EX$Season, EX$global, EX$RecLag, length(EX$covarLagIn1Real),
                min(names(EX$covarLagIn1Real)), max(names(EX$covarLagIn1Real))))
message(sprintf("  W3 = %.3f  W4 = %.3f  Survival = %.4f", EX$Weight3, EX$Weight4, EX$Survival))

# --- the FLOW-INFORMED posterior, named by the export ------------------------
# The export names the file but not the folder. Search posterior_dir first (where
# fits normally live), then data_root (where some older exports expected them).
.cand <- c(file.path(path_of(CFG$paths$posterior_dir), EX$posterior_file),
           file.path(path_of(CFG$paths$data_root),     EX$posterior_file))
post_path <- .cand[file.exists(.cand)][1]
if (is.na(post_path))
  stop("Posterior not found in either location:\n  ", paste(.cand, collapse = "\n  "),
       "\n  Named by the export as `posterior_file`. This must be the FLOW-INFORMED",
       "\n  fit (it needs b1r/b12r/b1S/b12S), NOT the null fit used by scripts 01-09.")
modIN <- readRDS(post_path)$BUGSoutput$sims.list
message("  posterior: ", EX$posterior_file, "   (flow-informed)")

# --- node fallbacks, logged rather than silent -------------------------------
# --- flow terms: absent means model selection DROPPED them, not that the fit is
# --- broken. Setting a missing coefficient to zero is not a patch; it is exactly
# --- what "this term was not selected" means. Every substitution is logged and
# --- recorded, because it changes how the result must be read:
#
#   b12r / b12S absent -> the flow response is LINEAR in z for that process. It
#     has no interior optimum, so more flow monotonically helps or hurts. That
#     also makes extrapolation beyond the calibration range SAFER, not riskier:
#     a line cannot turn over the way a fitted quadratic can.
#
#   b1r / b1S absent as well -> that process has NO flow response at all. The
#     rule curve is then flat in flow for that pathway, and any change in K comes
#     entirely from the other one. That is a legitimate result and must be stated,
#     because "no effect" and "bug" look identical in the output.
FLOWTERM <- c("b1r", "b12r", "b1S", "b12S")
n_draws_total <- length(c(modIN$la0))
terms_present <- setNames(FLOWTERM %in% names(modIN), FLOWTERM)

for (nm in FLOWTERM[!terms_present]) {
  modIN[[nm]] <- rep(0, n_draws_total)
  message(sprintf("  NOTE: %s absent -> 0 (not selected by the IPM for this site).", nm))
}

if (!terms_present[["b1r"]] && !terms_present[["b12r"]])
  warning("No flow terms for RECRUITMENT at ", site, " (b1r and b12r both absent).\n",
          "  Recruitment does not respond to summer flow in this fit, so any change\n",
          "  in K comes entirely from the survival pathway. This is a result, not a\n",
          "  failure -- report it as one.", call. = FALSE)
if (!terms_present[["b1S"]] && !terms_present[["b12S"]])
  warning("No flow terms for SURVIVAL at ", site, " (b1S and b12S both absent).\n",
          "  Any change in K comes entirely from the recruitment pathway.",
          call. = FALSE)
if (!any(terms_present))
  stop("No flow terms at all in this posterior (b1r, b12r, b1S, b12S all absent).\n",
       "  Either this is the NULL fit rather than the flow-informed one, or the IPM\n",
       "  selected no flow effect anywhere. K cannot vary with flow either way, so\n",
       "  the rule-curve arm has nothing to compute.")
if (!"BAdults" %in% names(modIN)) {
  if (!all(c("B3", "B4") %in% names(modIN)))
    stop("BAdults absent and B3/B4 unavailable to synthesise it.")
  modIN$BAdults <- modIN$B3 + modIN$B4
  message("  NOTE: BAdults synthesised as B3 + B4 = STANDING adult biomass.")
}

# Structural nodes are required; the four flow terms are optional and were
# defaulted to zero above if the IPM did not select them.
NEED_CORE <- c("la0", "b", "sigmaR", "lSurv0", "b6S")
miss <- setdiff(NEED_CORE, names(modIN))
if (length(miss))
  stop("Missing structural node(s): ", paste(miss, collapse = ", "),
       "\n  Present: ", paste(head(names(modIN), 30), collapse = ", "),
       "\n  These are not optional -- the Ricker and the survival model need them.")
NEED <- c(NEED_CORE, FLOWTERM)

# deterministic thinning -- a grid, not a sample, so draws are common across
# scenarios and a scenario contrast reflects flow rather than resampling noise
M_total  <- length(c(modIN$la0))
draw_idx <- unique(round(seq(1, M_total, length.out = min(RC$n_draws, M_total))))
M <- length(draw_idx)
P <- setNames(lapply(NEED, function(n) c(modIN[[n]])[draw_idx]), NEED)
message(sprintf("  draws: %d -> %d (deterministic grid)", M_total, M))

Survival <- EX$Survival


# =============================================================================
# GATE 1. THE STANDARDIZATION CONTRACT   (must pass)
# -----------------------------------------------------------------------------
# The z fed to b1r/b12r must be the same z the IPM was fitted with. If this fails,
# the flow coefficients are evaluated off-scale and every K below is wrong.
# =============================================================================
hdr("GATE 1  standardization contract")

qobs <- EX$covarLagIn1Real
mu_o <- mean(log(qobs), na.rm = TRUE); sd_o <- sd(log(qobs), na.rm = TRUE)
mu_q <- mean(log(EX$Flows));           sd_q <- sd(log(EX$Flows))

Z_OF <- function(q, ref = RC$zscore_ref)
  if (ref == "observed") (log(q) - mu_o) / sd_o else (log(q) - mu_q) / sd_q

d1 <- max(abs(Z_OF(qobs, "observed") - EX$covarLagIn1), na.rm = TRUE)
message(sprintf("  reproduce the IPM covariate: max|diff| = %.3e  [%s]",
                d1, if (d1 < 1e-10) "PASS" else "FAIL"))
if (d1 >= 1e-10)
  stop("Cannot reproduce the IPM's own covariate. Everything downstream is off-scale.")

message(sprintf("  sd(log summer mean) = %.5f [IPM]   sd(log Flows) = %.5f [FishCast]",
                sd_o, sd_q))
message(sprintf("  ratio %.4f -> FishCast z inflated by %.1f%%",
                sd_q / sd_o, 100 * (sd_o / sd_q - 1)))
z_train <- range(Z_OF(qobs), na.rm = TRUE)
message(sprintf("  training z range [%+.3f, %+.3f]  (ref = '%s')",
                z_train[1], z_train[2], RC$zscore_ref))


# =============================================================================
# 2. GEOMETRY, AND GATE 2: DOES IT SIT ON THE IPM'S SCALE?
# -----------------------------------------------------------------------------
# The rule curve asserts a stable-age mapping Stock -> (NALL, SSB). The posterior
# holds NALL[t] and BAdults[t] for every observed year. If the geometry is right,
# the posterior cloud lies ON the parametric curve. If it does not, la0/b/b6S are
# being evaluated somewhere the data never was.
# =============================================================================
Stock_grid <- seq(0, RC$stock_max, length.out = RC$stock_n)

geom_NALL <- function(Stock) switch(RC$axis_mode,
  # R = Stock/s ; NALL = R/(1-s). x and y are then both standing abundance,
  # which is what makes the 1:1 line a genuine replacement line.
  "NALL"     = Stock / (Survival * (1 - Survival)),
  "fishcast" = Stock / Survival)

geom_SSB <- function(Stock) switch(RC$ssb_mode,
  # standing spawning biomass: N3*W3 + N4plus*W4, with N4+ = Stock*s/(1-s)
  "standing" = Stock * (EX$Weight3 + (Survival / (1 - Survival)) * EX$Weight4),
  # as FishCast codes it -- weights DEATHS rather than standing stock
  "fishcast" = Stock * ((1 - Survival) * EX$Weight3 + Survival * EX$Weight4))

hdr("GATE 2  scale consistency (geometry vs posterior)")
scale_ok <- NA
if (all(c("NALL", "BAdults") %in% names(modIN)) &&
    is.matrix(modIN$NALL) && is.matrix(modIN$BAdults)) {
  ny <- min(ncol(modIN$NALL), ncol(modIN$BAdults))
  nall_post <- colMeans(modIN$NALL[, seq_len(ny), drop = FALSE])
  ssb_post  <- colMeans(modIN$BAdults[, seq_len(ny), drop = FALSE])
  # invert the geometry: what Stock would produce the observed NALL?
  stock_from_nall <- nall_post * (Survival * (1 - Survival))
  ratio <- ssb_post / geom_SSB(stock_from_nall)
  scale_ok <- median(ratio, na.rm = TRUE)
  message(sprintf("  ssb_mode = '%s': median(posterior SSB / geometry SSB) = %.3f",
                  RC$ssb_mode, scale_ok))
  # Compute the alternative WITHOUT mutating RC. An earlier draft used `<<-` to
  # flip the mode and flip it back; that is the same silent-global-mutation
  # pattern this project has already been bitten by once, and it leaves RC
  # corrupted if the line in between errors.
  ssb_alt <- function(Stock, mode) switch(mode,
    "standing" = Stock * (EX$Weight3 + (Survival / (1 - Survival)) * EX$Weight4),
    "fishcast" = Stock * ((1 - Survival) * EX$Weight3 + Survival * EX$Weight4))
  other <- setdiff(c("standing", "fishcast"), RC$ssb_mode)
  alt <- median(ssb_post / ssb_alt(stock_from_nall, other), na.rm = TRUE)
  message(sprintf("  the other mode would give %.3f", alt))
  if (abs(scale_ok - 1) > abs(alt - 1))
    warning("ssb_mode = '", RC$ssb_mode, "' is FURTHER from 1.00 than '", other,
            "'. Set CFG$rulecurve$ssb_mode to '", other, "' in config.R. ",
            "Choose by this number, not by taste.", call. = FALSE)
} else {
  message("  SKIPPED: NALL / BAdults are not per-year matrices in this posterior.")
  message("  This check is not optional -- K cannot be validated without it.")
}


# =============================================================================
# 3. THE RULE-CURVE ENGINE  (closed form)
# -----------------------------------------------------------------------------
#   SSB   = geom_SSB(Stock)                              linear in Stock
#   X     = geom_NALL(Stock)                             x-axis AND the DD covariate
#   lSurv = lSurv0 + b1S*z + b12S*z^2 + b6S*(X/100)
#   Si    = plogis(lSurv)                                independent of R
#   mu    = la0 + log(SSB) - b*SSB + b1r*z + b12r*z^2    [- sigmaR^2/2 if median]
#   Y     = exp(mu) / (1 - Si)
#
# Closed form because Si does not depend on R. Validated in the original against
# a 500-draw Monte Carlo to 0.1-0.3%.
# =============================================================================
rule_curve_matrix <- function(z, Stock = Stock_grid) {
  SSB <- geom_SSB(Stock); X <- geom_NALL(Stock); nS <- length(Stock)
  lS  <- outer(X / 100, P$b6S) + rep(P$lSurv0 + P$b1S * z + P$b12S * z^2, each = nS)
  Si  <- 1 / (1 + exp(-lS))
  mu  <- outer(log(SSB), rep(1, M)) - outer(SSB, P$b) +
         rep(P$la0 + P$b1r * z + P$b12r * z^2, each = nS)
  if (RC$recruit_stat == "median") mu <- mu - rep(P$sigmaR^2 / 2, each = nS)
  Y <- exp(mu) / (1 - Si); Y[!is.finite(Y)] <- NA_real_
  list(X = X, Y = Y)
}

# K  = descending crossing of the 1:1 line, by linear interpolation
# MS = max(Y - X), refined parabolically; S_MSY refit per draw
K_and_MS <- function(z) {
  Stock <- Stock_grid; rc <- rule_curve_matrix(z, Stock)
  for (attempt in 1:4) {
    D  <- rc$Y - rc$X
    ok <- apply(D, 2, function(d) any(d[-1] > 0, na.rm = TRUE) && any(d < 0, na.rm = TRUE))
    if (mean(ok, na.rm = TRUE) > 0.98) break
    # the curve has not turned over inside the grid: extend rather than report NA
    Stock <- seq(0, max(Stock) * 2, length.out = RC$stock_n)
    rc <- rule_curve_matrix(z, Stock)
  }
  X <- rc$X; D <- rc$Y - rc$X
  data.frame(
    draw = seq_len(M),
    K = apply(D, 2, function(d) {
      i <- which(d[-length(d)] > 0 & d[-1] <= 0); if (!length(i)) return(NA_real_)
      i <- i[length(i)]; X[i] + (X[i+1] - X[i]) * d[i] / (d[i] - d[i+1])
    }),
    MS = apply(D, 2, function(d) {
      j <- which.max(d); if (!length(j) || !is.finite(d[j])) return(NA_real_)
      if (j > 1 && j < length(d)) {
        y1 <- d[j-1]; y2 <- d[j]; y3 <- d[j+1]; den <- y1 - 2*y2 + y3
        if (is.finite(den) && den != 0) return(y2 - (y3 - y1)^2 / (8 * den))
      }
      d[j]
    }),
    S_MSY = apply(D, 2, function(d) { j <- which.max(d); if (length(j)) X[j] else NA_real_ }))
}


# =============================================================================
# 4. BoR SCENARIOS -> SUMMER MEAN -> z
# =============================================================================
hdr("BoR scenarios")

bor_path <- path_of(rulecurve_bor_path(site))
if (!file.exists(bor_path))
  stop("BoR flow file not found:\n  ", bor_path,
       "\n  Adjust rulecurve_bor_path() in config.R.")

bor <- readRDS(bor_path)
flow_col <- intersect(c("Flow_cfs", "Discharge", "flow"), names(bor))[1]
if (is.na(flow_col)) stop("No recognisable flow column in the BoR file.")

summer <- bor %>%
  mutate(Date = ymd(Date), Year = year(Date), DOY = yday(Date)) %>%
  filter(DOY >= RC$summer_doy[["start"]], DOY <= RC$summer_doy[["end"]]) %>%
  group_by(across(any_of(c("Scenario", "Period", "Type"))), Year) %>%
  summarise(n_days = sum(!is.na(.data[[flow_col]])),
            Q = mean(.data[[flow_col]], na.rm = TRUE), .groups = "drop") %>%
  filter(n_days > 40)

summer$z_raw <- Z_OF(summer$Q)
summer$outside <- summer$z_raw < z_train[1] | summer$z_raw > z_train[2]
summer$z <- if (RC$clamp_z) pmin(pmax(summer$z_raw, z_train[1]), z_train[2]) else summer$z_raw

message(sprintf("  %d scenario-years | %.1f%% outside the training z range",
                nrow(summer), 100 * mean(summer$outside)))
if (mean(summer$outside) > 0.2)
  quad <- names(which(terms_present[c("b12r", "b12S")]))
  if (length(quad)) {
    message("  Scenario flows leave the calibration range and ",
            paste(quad, collapse = " / "), " are EXTRAPOLATING.\n",
            "  A quadratic fitted inside the range can turn over sharply outside it.")
  } else {
    message("  Scenario flows leave the calibration range, but the flow response is\n",
            "  LINEAR here (no quadratic terms selected), so it cannot turn over.\n",
            "  Extrapolation is safer than with a quadratic, though still extrapolation.")
  }

# --- where does the quadratic turn over? -------------------------------------
vert <- function(b1, b2) ifelse(abs(b2) < 1e-12, NA_real_, -b1 / (2 * b2))
vtx <- data.frame(
  process = c("recruitment", "survival"),
  vertex_z = c(median(vert(P$b1r, P$b12r), na.rm = TRUE),
               median(vert(P$b1S, P$b12S), na.rm = TRUE)),
  curvature = c(median(P$b12r), median(P$b12S)))
vtx$quadratic_fitted <- c(terms_present[["b12r"]], terms_present[["b12S"]])
vtx$inside_training <- vtx$vertex_z >= z_train[1] & vtx$vertex_z <= z_train[2]
# A process with no quadratic term has no vertex -- that is "linear response",
# not "missing value", and the two must not read the same in a table.
vtx$note <- ifelse(!vtx$quadratic_fitted, "linear in z (no quadratic selected)",
             ifelse(is.na(vtx$vertex_z), "vertex undefined",
              ifelse(vtx$inside_training, "turns over INSIDE the calibrated range",
                     "turns over outside the calibrated range")))
message("\n  flow response shape by process:")
print(as.data.frame(vtx), row.names = FALSE, digits = 3)
if (any(vtx$inside_training & vtx$curvature < 0, na.rm = TRUE))
  message("  A downward vertex sits INSIDE the training range: the fitted response\n",
          "  already peaks there, so more flow is predicted to reduce the rate.")


# =============================================================================
# 5. K AND MS PER SCENARIO-YEAR
# =============================================================================
hdr("K and MS")

uz <- sort(unique(round(summer$z, 4)))
message(sprintf("  evaluating %d unique z values across %d draws ...", length(uz), M))
by_z <- setNames(lapply(uz, K_and_MS), as.character(uz))

# baseline: z at the geometric mean of observed summer flow
z0 <- Z_OF(exp(mu_o))
base <- K_and_MS(z0)
message(sprintf("  baseline (z = %+.3f): K = %.0f  MS = %.0f",
                z0, median(base$K, na.rm = TRUE), median(base$MS, na.rm = TRUE)))

grp <- intersect(c("Scenario", "Period", "Type"), names(summer))
res <- bind_rows(lapply(seq_len(nrow(summer)), function(i) {
  d <- by_z[[as.character(round(summer$z[i], 4))]]
  # deltaK is per-draw against the SAME draw's baseline: common random numbers,
  # so the contrast is the flow effect and not draw-to-draw variation in K.
  data.frame(summer[i, c(grp, "Year", "Q", "z", "outside")],
             K = median(d$K, na.rm = TRUE),
             K_lo = quantile(d$K, .025, na.rm = TRUE, names = FALSE),
             K_hi = quantile(d$K, .975, na.rm = TRUE, names = FALSE),
             MS = median(d$MS, na.rm = TRUE),
             S_MSY = median(d$S_MSY, na.rm = TRUE),
             dK_pct = 100 * median((d$K - base$K) / base$K, na.rm = TRUE),
             dK_pct_lo = 100 * quantile((d$K - base$K) / base$K, .025, na.rm = TRUE, names = FALSE),
             dK_pct_hi = 100 * quantile((d$K - base$K) / base$K, .975, na.rm = TRUE, names = FALSE),
             dMS_pct = 100 * median((d$MS - base$MS) / base$MS, na.rm = TRUE),
             p_K_finite = mean(is.finite(d$K)))
}))

summary_tbl <- res %>%
  group_by(across(all_of(grp))) %>%
  summarise(n_years = dplyr::n(), mean_Q = mean(Q), mean_z = mean(z),
            K = median(K), dK_pct = median(dK_pct),
            MS = median(MS), dMS_pct = median(dMS_pct),
            frac_extrapolating = mean(outside),
            frac_K_finite = mean(p_K_finite), .groups = "drop") %>%
  arrange(dK_pct)

message("\n== equilibrium change by scenario ==")
print(as.data.frame(summary_tbl), row.names = FALSE, digits = 3)

if (any(summary_tbl$frac_K_finite < 0.9))
  warning("Some scenarios have K undefined in >10% of draws -- the replacement ",
          "curve does not cross the 1:1 line there. Those K values are not ",
          "trustworthy; deltaK may still be, see the note in the results.",
          call. = FALSE)


# =============================================================================
# 6. FIGURES
# =============================================================================
# --- the rule curve itself, at three flows -----------------------------------
z_show <- c(low = quantile(summer$z, .1, names = FALSE), base = z0,
            high = quantile(summer$z, .9, names = FALSE))
curve_df <- bind_rows(lapply(names(z_show), function(nm) {
  rc <- rule_curve_matrix(z_show[[nm]])
  data.frame(level = nm, z = z_show[[nm]], X = rc$X, Y = rowMeans(rc$Y, na.rm = TRUE))
})) %>% filter(is.finite(Y), X > 0, X < RC$stock_max)

f10a <- ggplot(curve_df, aes(X, Y, colour = level)) +
  geom_abline(slope = 1, intercept = 0, linetype = 2, colour = PAL[["mute"]]) +
  geom_line(linewidth = 1) +
  scale_colour_manual(values = c(low = PAL[["red"]], base = PAL[["ink"]], high = PAL[["blue"]]),
                      labels = sprintf("%s (z = %+.2f)", names(z_show), z_show), name = NULL) +
  coord_cartesian(xlim = c(0, max(res$K, na.rm = TRUE) * 1.6),
                  ylim = c(0, max(res$K, na.rm = TRUE) * 1.6)) +
  labs(title = paste0("Figure 10a. The rule curve at three summer flows — ", site),
       subtitle = paste0("Dashed = the 1:1 replacement line. K is where a curve crosses it going down;\n",
                         "MS is the largest vertical gap between the curve and the line.\n",
                         "A curve that never crosses has no equilibrium inside the plotted range."),
       x = "abundance this generation", y = "abundance next generation") +
  theme_wh

# --- delta K by scenario ------------------------------------------------------
f10b <- ggplot(summary_tbl, aes(dK_pct,
                                reorder(do.call(paste, c(summary_tbl[grp], sep = " / ")), dK_pct))) +
  geom_vline(xintercept = 0, linetype = 2, colour = PAL[["red"]]) +
  geom_point(aes(colour = frac_extrapolating), size = 3.4) +
  scale_colour_gradient(low = PAL[["blue"]], high = PAL[["red"]],
                        name = "fraction of years\noutside training range") +
  labs(title = "Figure 10b. Change in equilibrium carrying capacity",
       subtitle = paste0("Percentage change in K relative to the historical geometric-mean summer flow.\n",
                         # Do not assert quadratics: at a site where model selection
                         # dropped them the response is linear and extrapolation,
                         # while still extrapolation, cannot turn over unexpectedly.
                         if (any(terms_present[c("b12r", "b12S")]))
                           "Red points are extrapolating: the quadratic flow terms are being evaluated\nwhere no data constrained them."
                         else
                           "Red points are extrapolating. The flow response is LINEAR here (no quadratic\nterm was selected), so the curve cannot turn over outside the calibrated range."),
       x = "% change in K", y = NULL) +
  theme_wh

# --- K against summer flow, the dose-response --------------------------------
f10c <- ggplot(res, aes(Q, K)) +
  geom_hline(yintercept = median(base$K, na.rm = TRUE), linetype = 2, colour = PAL[["mute"]]) +
  geom_point(aes(colour = outside), size = 1.8, alpha = .8) +
  scale_colour_manual(values = c(`FALSE` = PAL[["blue"]], `TRUE` = PAL[["red"]]),
                      labels = c("within training range", "extrapolating"), name = NULL) +
  labs(title = "Figure 10c. Equilibrium carrying capacity against summer mean flow",
       subtitle = paste0("Each point is one scenario-year. Dashed = K at the historical geometric mean.\n",
                         "This is the dose-response a manager asks for: how much does K move per cfs of\n",
                         "summer flow? Curvature here is the b12r / b12S quadratic, not an artefact."),
       x = "summer mean discharge (cfs)", y = "equilibrium K") +
  theme_wh

for (nm in c("f10a", "f10b", "f10c"))
  ggsave(file.path(OUT, "figures", paste0("10_", sub("^f10", "", nm), ".png")),
         get(nm), width = 9.5, height = 5.4, dpi = 150)


# =============================================================================
# 7. SAVE
# =============================================================================
saveRDS(list(site = site, settings = RC, export = EX[c("Season","global","RecLag",
                                                       "Weight3","Weight4","Survival")],
             posterior_file = EX$posterior_file,
             baseline = base, baseline_z = z0, z_train = z_train,
             by_year = res, summary = summary_tbl, vertex = vtx,
             terms_present = terms_present,   # which flow terms the IPM selected

             scale_check = scale_ok, n_draws = M, run = Sys.time()),
        file.path(OUT, "models", "rulecurve.rds"))
write.csv(res,         file.path(OUT, "tables", "rulecurve_by_year.csv"), row.names = FALSE)
write.csv(summary_tbl, file.path(OUT, "tables", "rulecurve_summary.csv"), row.names = FALSE)

message("\n  wrote rulecurve.rds + 2 tables + 3 figures")
message("\n  READ BEFORE QUOTING:")
message("  * K is an EQUILIBRIUM under a sustained shift in summer mean flow.")
message("    It is not a 30-year projection and not comparable to script 07's")
message("    short-run production sensitivity -- different question, different units.")
message("  * Extrapolating scenario-years evaluate the quadratic flow terms outside")
message("    the calibration range. Check frac_extrapolating before briefing a number.")
message("  * This arm uses the FLOW-INFORMED IPM. Scripts 01-09 use the null fit.")
message(sprintf("  * Flow terms selected by the IPM here: %s",
                paste(names(which(terms_present)), collapse = ", ")))
if (!all(terms_present)) {
  message(sprintf("    Absent (set to 0): %s -- a model-selection result, not a gap.\n",
                  paste(names(which(!terms_present)), collapse = ", ")))
} else {
  message("")
}