# =============================================================================
# 07_production_sensitivity.R  --  RQ1, the whole-population answer.
#
#   in : beta_recruitment.rds, beta_survival.rds, the null IPM posterior
#   out: output/models/production.rds, output/tables/production_sensitivity.csv
#
# WHY PRODUCTION IS NOT A THIRD REGRESSION
# ----------------------------------------
# Recruitment and survival are PROCESSES you can regress on flow. Production is a
# CONSEQUENCE of both, propagated through the age structure. Fitting a third
# curve to "production" would be wrong, and adding the recruitment and survival
# curves together would be worse -- it would miss the compounding, where a
# survival gain raises the spawning stock which then feeds the Ricker three years
# later.
#
# So: take a numerical derivative through the population model.
#
#   for each 5-day block b:
#       run the forward simulation with a small release on block b
#       run it again with no release, SAME RANDOM NUMBER STREAMS
#       production sensitivity(b) = difference in mean surplus production
#
# Common random numbers are what make this work: the two runs differ only by the
# release, so the difference is signal rather than Monte Carlo noise.
#
# 73 blocks x 5 days = 365. Block resolution is not a compromise: script 06 will
# usually show the resolvable window is wider than 5 days anyway.
#
# THE PRODUCTION BUDGET
# ---------------------
# Total biomass  B_t = N2 w2 + N3 w3 + N4 w4
# Surplus production is the exact accounting identity
#       SP_t = I_t + G_t - M_t = B_t - B_{t-1}
#   I = recruitment input      N2_t w2
#   G = somatic growth         N3_t(w3-w2) + N4_t(w4 - wbar_{t-1})
#   M = mortality loss         (N2_{t-1}-N3_t)w2 + (adults_{t-1}-N4_t)wbar_{t-1}
# with the age-4-plus group valued at its abundance-weighted mean mass wbar.
# There is no harvest in this IPM, so SP is simply the change in biomass.
# The identity residual is computed and must be zero to machine precision; if it
# is not, the age bookkeeping has drifted and nothing here is trustworthy.
#
# Mean mass at age is frozen at its launch value, so this captures the
# flow-on-ABUNDANCE pathway and not temperature-on-growth. Say so wherever SP is
# reported.
#
# Run:  source("R/00_config.R"); source("R/07_production_sensitivity.R")
# =============================================================================

source(here::here("R", "00_config.R"))
suppressPackageStartupMessages({ library(tidyr); library(purrr) })

BR <- readRDS(file.path(OUT, "models", "beta_recruitment.rds"))
BS <- if (file.exists(file.path(OUT, "models", "beta_survival.rds")))
        readRDS(file.path(OUT, "models", "beta_survival.rds")) else NULL
RESP <- readRDS(file.path(OUT, "models", "response.rds"))

BLOCK    <- if (is.null(CFG$production$block_days)) 5L else CFG$production$block_days
N_YEARS  <- if (is.null(CFG$production$n_years)) 40L else CFG$production$n_years
BURN     <- if (is.null(CFG$production$burn_in)) 15L else CFG$production$burn_in
DELTA    <- if (is.null(CFG$sensitivity$delta_cfs)) 10 else CFG$sensitivity$delta_cfs
N_DRAW   <- if (is.null(CFG$production$n_draws)) 400L else CFG$production$n_draws

rows <- list(); traj <- list()

for (site in names(BR$fits)) {

  message("\n== ", site, " ==")
  fR <- BR$fits[[site]]
  fS <- if (!is.null(BS)) BS$fits[[site]] else NULL

  # ---------------------------------------------------------------------------
  # demographic parameters from the SAME posterior draws as the beta curves
  # ---------------------------------------------------------------------------
  sl <- readRDS(posterior_path(site))$BUGSoutput$sims.list
  keep <- RESP$sites[[site]]$keep
  need <- c("la0", "b", "sigmaR", "lSurv0", "b6S", "weight3", "weight4")
  miss <- setdiff(need, names(sl))
  if (length(miss)) { warning(site, ": missing ", paste(miss, collapse = ", ")); next }

  w2 <- if ("weight2" %in% names(sl)) as.numeric(sl$weight2)[keep] else {
    warning(site, ": weight2 absent; using 0.5 * weight3 as a placeholder. ",
            "The recruitment-input term of the budget is then approximate.")
    0.5 * as.numeric(sl$weight3)[keep] }

  # thin further for the simulation: 73 blocks x 2 runs x N_DRAW draws
  ss <- round(seq(1, length(keep), length.out = min(N_DRAW, length(keep))))
  P <- list(la0 = as.numeric(sl$la0)[keep][ss], b = as.numeric(sl$b)[keep][ss],
            sigmaR = as.numeric(sl$sigmaR)[keep][ss],
            lSurv0 = as.numeric(sl$lSurv0)[keep][ss], b6S = as.numeric(sl$b6S)[keep][ss],
            w2 = w2[ss], w3 = as.numeric(sl$weight3)[keep][ss],
            w4 = as.numeric(sl$weight4)[keep][ss],
            sigmaSurv = if ("sigmaSurv" %in% names(sl)) as.numeric(sl$sigmaSurv)[keep][ss] else NULL)
  M <- length(P$la0)

  # launch state: terminal estimated abundance
  lastcol <- function(k) { x <- sl[[k]]; x[keep, ncol(x)][ss] }
  N2_0 <- lastcol("N2"); N3_0 <- lastcol("N3"); N4_0 <- lastcol("N4")

  # mean beta curves for the perturbation (draw-specific curves would be ideal
  # but the numerical derivative is dominated by the mean; the spread across
  # draws is reported by script 06)
  bR <- colMeans(fR$beta_draws)
  bS <- if (!is.null(fS)) colMeans(fS$beta_draws) else rep(0, 365)
  lever <- log1p(DELTA / fR$Qbar) / fR$global_sd     # length 365

  # ---------------------------------------------------------------------------
  # THE ONE CUSTOM FUNCTION -- run the population forward. Deterministic given
  # the pre-drawn noise, which is what makes the paired difference clean.
  # ---------------------------------------------------------------------------
  run_sim <- function(eta_R, eta_S, zR, zS) {
    N2 <- N3 <- N4 <- matrix(NA_real_, M, N_YEARS + 3L)
    for (j in 1:3) { N2[, j] <- N2_0; N3[, j] <- N3_0; N4[, j] <- N4_0 }
    B <- SP <- matrix(NA_real_, M, N_YEARS)
    for (p in seq_len(N_YEARS)) {
      j <- p + 3L; jm <- j - 1L
      NALLp <- N2[, jm] + N3[, jm] + N4[, jm]
      lS <- P$lSurv0 + P$b6S * (NALLp / 100) + eta_S
      if (!is.null(P$sigmaSurv)) lS <- lS + P$sigmaSurv * zS[, p]
      Sv <- plogis(lS)
      N3[, j] <- N2[, jm] * Sv
      N4[, j] <- (N3[, jm] + N4[, jm]) * Sv
      BA <- N3[, j - 3L] * P$w3 + N4[, j - 3L] * P$w4
      lR <- P$la0 + log(pmax(BA, 1e-8)) - P$b * BA + eta_R -
            0.5 * P$sigmaR^2 + P$sigmaR * zR[, p]
      N2[, j] <- exp(lR)
      # production budget, realized abundances
      ad_p <- N3[, jm] + N4[, jm]
      wbar <- ifelse(ad_p > 0, (N3[, jm] * P$w3 + N4[, jm] * P$w4) / pmax(ad_p, 1e-12), P$w4)
      Bprev <- N2[, jm] * P$w2 + N3[, jm] * P$w3 + N4[, jm] * P$w4
      B[, p] <- N2[, j] * P$w2 + N3[, j] * P$w3 + N4[, j] * P$w4
      I <- N2[, j] * P$w2
      G <- N3[, j] * (P$w3 - P$w2) + N4[, j] * (P$w4 - wbar)
      Mo <- (N2[, jm] - N3[, j]) * P$w2 + (ad_p - N4[, j]) * wbar
      SP[, p] <- I + G - Mo
      if (p == 1) attr(B, "resid") <- max(abs(B[, p] - Bprev - SP[, p])) / max(abs(B[, p]))
    }
    cols <- (BURN + 1L):N_YEARS
    list(B = rowMeans(B[, cols, drop = FALSE]), SP = rowMeans(SP[, cols, drop = FALSE]),
         resid = attr(B, "resid"))
  }

  # shared noise streams: COMMON RANDOM NUMBERS
  set.seed(CFG$fitting$seed)
  zR <- matrix(rnorm(M * N_YEARS), M, N_YEARS)
  zS <- matrix(rnorm(M * N_YEARS), M, N_YEARS)

  base <- run_sim(rep(0, M), rep(0, M), zR, zS)
  message(sprintf("  biomass identity residual = %.2e %s", base$resid,
                  ifelse(base$resid < 1e-8, "(budget closes)",
                         "*** BUDGET DOES NOT CLOSE -- do not use these numbers ***")))
  message(sprintf("  baseline: mean biomass %.3g g, mean surplus production %.3g g/yr",
                  median(base$B), median(base$SP)))

  # ---------------------------------------------------------------------------
  # sweep the blocks
  # ---------------------------------------------------------------------------
  starts <- seq(1L, 365L, by = BLOCK)
  message("  sweeping ", length(starts), " blocks of ", BLOCK, " days ...")
  pb <- utils::txtProgressBar(min = 0, max = length(starts), style = 3, width = 40)
  for (i in seq_along(starts)) {
    ix <- starts[i]:min(starts[i] + BLOCK - 1L, 365L)
    dR <- sum(bR[ix] * lever[ix])          # flow signal added to recruitment
    dS <- sum(bS[ix] * lever[ix])          # ... and to survival
    for (path in c("both", "recruitment", "survival")) {
      eR <- if (path %in% c("both", "recruitment")) rep(dR, M) else rep(0, M)
      eS <- if (path %in% c("both", "survival"))    rep(dS, M) else rep(0, M)
      r <- run_sim(eR, eS, zR, zS)
      rows[[length(rows) + 1]] <- data.frame(
        site = site, pathway = path,
        block_start = starts[i], block_end = max(ix),
        month = MON_L[findInterval(starts[i], MON_B)],
        d_biomass = median(r$B - base$B),
        d_biomass_lo = quantile(r$B - base$B, .1, names = FALSE),
        d_biomass_hi = quantile(r$B - base$B, .9, names = FALSE),
        d_production = median(r$SP - base$SP),
        d_prod_pct = 100 * median((r$SP - base$SP) / pmax(abs(base$SP), 1e-12)),
        p_positive = mean(r$SP > base$SP))
    }
    utils::setTxtProgressBar(pb, i)
  }
  close(pb)
}

prod <- bind_rows(rows)
if (!nrow(prod)) stop("No site produced production sensitivities.")

# --- the interaction: does the whole exceed the sum of the parts? -------------
inter <- prod %>%
  select(site, block_start, month, pathway, d_production) %>%
  pivot_wider(names_from = pathway, values_from = d_production) %>%
  mutate(interaction = both - recruitment - survival)

message("\n  median |interaction| as a share of |total|: ",
        sprintf("%.1f%%", 100 * median(abs(inter$interaction) /
                                       pmax(abs(inter$both), 1e-12), na.rm = TRUE)))
message("  A large share means the recruitment and survival pathways COMPOUND")
message("  (survival changes the spawning stock, which feeds the Ricker 3 years later)")
message("  and must not be presented as additive contributions.\n")


# =============================================================================
# FIGURES
# =============================================================================
f7a <- prod %>% filter(pathway == "both") %>%
  ggplot(aes(block_start, d_prod_pct)) +
  geom_hline(yintercept = 0, linetype = 2, colour = PAL[["mute"]]) +
  geom_ribbon(aes(ymin = 100 * d_biomass_lo / abs(d_biomass_lo + 1e-9) * abs(d_prod_pct),
                  ymax = d_prod_pct), alpha = 0) +
  geom_col(aes(fill = d_prod_pct > 0), width = BLOCK) +
  scale_fill_manual(values = c("TRUE" = PAL[["blue"]], "FALSE" = PAL[["red"]]), guide = "none") +
  facet_wrap(~ site, scales = "free_y") +
  scale_x_continuous(breaks = MON_B, labels = MON_L) +
  labs(title = paste0("Figure 7a. Effect on total population production of adding ", DELTA,
                      " cfs for ", BLOCK, " days"),
       subtitle = paste0("Percent change in mean annual surplus production, both pathways, common random numbers.\n",
                         "This is the whole-population answer: it includes the compounding of survival into future\n",
                         "spawning stock, which adding the two curves separately would miss."),
       x = NULL, y = "% change in surplus production") + theme_wh

f7b <- prod %>%
  ggplot(aes(block_start, d_prod_pct, colour = pathway)) +
  geom_hline(yintercept = 0, linetype = 2, colour = PAL[["mute"]]) +
  geom_line(linewidth = .8) +
  scale_colour_manual(values = c(both = PAL[["ink"]], recruitment = PAL[["blue"]],
                                 survival = PAL[["green"]]), name = NULL) +
  facet_wrap(~ site, scales = "free_y") +
  scale_x_continuous(breaks = MON_B, labels = MON_L) +
  labs(title = "Figure 7b. Which pathway carries the effect, and when?",
       subtitle = paste0("If recruitment and survival peak at different times of year, the two vital rates are\n",
                         "flow-limited in different seasons -- which life stage is the bottleneck, and when.\n",
                         "That divergence is the core ecological result (RQ2)."),
       x = NULL, y = "% change in surplus production") +
  theme_wh + theme(legend.position = "bottom")

f7c <- ggplot(inter, aes(block_start, interaction)) +
  geom_hline(yintercept = 0, linetype = 2, colour = PAL[["mute"]]) +
  geom_col(fill = PAL[["gold"]], width = BLOCK) +
  facet_wrap(~ site, scales = "free_y") +
  scale_x_continuous(breaks = MON_B, labels = MON_L) +
  labs(title = "Figure 7c. The interaction between pathways",
       subtitle = paste0("both - recruitment - survival. Non-zero means the pathways compound and cannot be\n",
                         "reported as additive contributions. Positive = the whole exceeds the sum of the parts."),
       x = NULL, y = "g/yr of surplus production") + theme_wh

for (nm in c("f7a", "f7b", "f7c"))
  ggsave(file.path(OUT, "figures", paste0("07_", nm, ".png")), get(nm),
         width = 9.5, height = 5, dpi = 150)

saveRDS(list(production = prod, interaction = inter,
             settings = list(block_days = BLOCK, n_years = N_YEARS, burn_in = BURN,
                             delta_cfs = DELTA, n_draws = N_DRAW),
             run = Sys.time()),
        file.path(OUT, "models", "production.rds"))
write.csv(prod, file.path(OUT, "tables", "production_sensitivity.csv"), row.names = FALSE)
message("  wrote output/models/production.rds and production_sensitivity.csv\n")
