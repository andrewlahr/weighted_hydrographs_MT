# =============================================================================
# diag_fpc_truncation.R -- the three diagnostics that defuse the main FPC
# objections. Run these BEFORE submission, not during revision.
#
#     source("R/00_config.R"); source("R/diag_fpc_truncation.R")
#
# Writes output/tables/fpc_diagnostics_*.csv and output/figures/fpc_diag_*.png
#
# WHAT EACH ONE ANSWERS
#
#   1. DISCARDED-COMPONENT TEST
#      "Truncation ranks components by flow variance, then tests them against
#       recruitment. A low-variance mode could carry the signal and be deleted
#       before it was ever tested."
#      -> Regress the response on the components you THREW AWAY. If they carry no
#         predictive relationship, truncation was harmless in YOUR data, whatever
#         the general theory says. This converts a structural objection into a
#         settled empirical question, and it is the single highest-value check
#         here.
#
#   2. K SENSITIVITY SWEEP
#      "The truncation threshold is arbitrary and no sensitivity analysis is
#       presented."
#      -> Re-fit across K and across variance thresholds, and track where the
#         peak day lands. If the peak moves, you cannot make a daily claim -- and
#         you would much rather find that out yourself.
#
#   3. CROSS-SITE BASIS COMPARABILITY
#      "FPCA is run per site, so eigenfunctions differ between sites; comparing
#       beta(t) across sites compares functions estimated in different bases."
#      -> Report the pairwise alignment of sites' leading eigenfunctions. If they
#         are near-identical the objection is defused; if they are not, switch to
#         a pooled common basis (this script builds one).
#
# See docs/notes/FPC_reviewer_critiques.md for the full argument behind each.
# =============================================================================

source(here::here("R", "00_config.R"))
source(here::here("R", "fn_fit_beta.R"))
suppressPackageStartupMessages({ library(tidyr); library(purrr) })

BR <- readRDS(file.path(OUT, "models", "beta_recruitment.rds"))
if (is.null(BR$fits)) stop("Run R/03_fit_beta_recruitment.R first.")

DIAG <- list()

# =============================================================================
# 1. DISCARDED-COMPONENT TEST
# -----------------------------------------------------------------------------
# For each site: fit the response to the RETAINED components, then ask whether
# the components that were dropped explain any of what is left over.
#
# The honest test is on the residuals. If the dropped components have real
# predictive content, they will correlate with the residuals from the retained
# ones. An F-test on the incremental fit is the standard framing and is what a
# reviewer will expect to see.
# =============================================================================
message("\n== 1. discarded-component test ==")

disc <- bind_rows(lapply(names(BR$fits), function(s) {
  f  <- BR$fits[[s]]
  y  <- colMeans(f$Y)
  X  <- f$Curves
  n  <- length(y)

  pc   <- prcomp(X, center = TRUE)
  varprop <- pc$sdev^2 / sum(pc$sdev^2)
  cumv    <- cumsum(varprop) * 100
  # Mirror the rule in force, so the diagnostic tests the model you actually
  # fit rather than a hardcoded one. (This block used to duplicate the
  # cumulative rule inline, which would have silently diverged the moment
  # fpc_rule changed.)
  K_cum <- if (any(cumv >= FPC_VAR)) which(cumv >= FPC_VAR)[1] else length(cumv)
  K_ind <- sum(varprop * 100 >= FPC_MIN)
  K <- min(switch(FPC_RULE, cumulative = K_cum, individual = K_ind,
                  both = min(K_cum, K_ind)),
           FPC_MAX, n - 3L)

  # how many discarded components can we even test? keep it well under n
  K_extra <- min(10L, ncol(pc$x) - K, floor((n - K - 4L)))
  if (K_extra < 1L) return(NULL)

  Zin  <- pc$x[, seq_len(K), drop = FALSE]
  Zout <- pc$x[, K + seq_len(K_extra), drop = FALSE]
  colnames(Zin)  <- paste0("in", seq_len(K))
  colnames(Zout) <- paste0("out", seq_len(K_extra))

  m_in   <- lm(y ~ Zin + f$stock_z)
  m_both <- lm(y ~ Zin + Zout + f$stock_z)
  a      <- anova(m_in, m_both)

  # variance the discarded components carry, for context
  var_out <- sum(pc$sdev[K + seq_len(K_extra)]^2) / sum(pc$sdev^2) * 100

  data.frame(site = s, n_years = n, K_retained = K,
             var_retained = cumv[K], K_discarded_tested = K_extra,
             var_discarded_tested = var_out,
             delta_r2 = summary(m_both)$r.squared - summary(m_in)$r.squared,
             F_stat = a$F[2], p_value = a$`Pr(>F)`[2])
}))

if (!is.null(disc) && nrow(disc)) {
  print(as.data.frame(disc), row.names = FALSE, digits = 3)
  write.csv(disc, file.path(OUT, "tables", "fpc_diagnostics_discarded.csv"), row.names = FALSE)

  worst <- min(disc$p_value, na.rm = TRUE)
  message("")
  if (worst > 0.10) {
    message("  VERDICT: the discarded components carry no detectable predictive")
    message("  content at any site (smallest p = ", sprintf("%.3f", worst), ").")
    message("  Truncation was harmless HERE. Report this in Methods -- it answers")
    message("  the standard PCR objection empirically rather than by argument.")
  } else {
    message("  VERDICT: at least one site has predictive signal in the DISCARDED")
    message("  components (smallest p = ", sprintf("%.3f", worst), ").")
    message("  This is the objection landing. Truncation is deleting signal.")
    message("  Options: raise fpc_target_var (or lower fpc_min_var), use the penalized")
    message("  arm, or move to functional PLS, which selects components by covariance")
    message("  with the response instead of by predictor variance.")
  }
}

# =============================================================================
# 2. K SENSITIVITY SWEEP
# -----------------------------------------------------------------------------
# Does the answer to "which day" survive a change in K? If not, there is no
# daily claim to make, whatever the fitted curve looks like at one value of K.
# =============================================================================
message("\n== 2. K sensitivity sweep ==")

sweep <- bind_rows(lapply(names(BR$fits), function(s) {
  f <- BR$fits[[s]]; y <- colMeans(f$Y); X <- f$Curves
  n <- length(y)
  Ks <- 3:min(FPC_MAX, n - 4L)
  bind_rows(lapply(Ks, function(K) {
    # Force exactly K: rule and thresholds are set so neither can bind, leaving
    # k_max as the only constraint. Stated explicitly so a future change to the
    # default rule cannot silently alter what this sweep measures.
    fit <- .fit_beta_fpc(y, X, rule = "cumulative", target_var = 100,
                         min_var = 0, k_max = K,
                         extra = cbind(S_z = f$stock_z))
    data.frame(site = s, K = K, peak_day = which.max(fit$beta),
               trough_day = which.min(fit$beta),
               peak_value = max(fit$beta), r2 = fit$r2)
  }))
}))

sweep$peak_date <- doy_date(sweep$peak_day)   # calendar axis; see R/00_config.R
print(as.data.frame(sweep), row.names = FALSE, digits = 3)
write.csv(sweep, file.path(OUT, "tables", "fpc_diagnostics_Ksweep.csv"), row.names = FALSE)

spread <- sweep %>% group_by(site) %>%
  summarise(peak_range_days = diff(range(peak_day)), .groups = "drop")
message("")
for (i in seq_len(nrow(spread))) {
  r <- spread$peak_range_days[i]
  message(sprintf("  %s: peak day moves %d days across K", spread$site[i], r))
  if (r > 45)
    message("     -> Too unstable to support a daily recommendation. The peak is",
            "\n        being set by K, not by the data.")
  else if (r > 14)
    message("     -> Moderate. Report the sweep in SI and widen the claimed window",
            "\n        to cover the full range.")
  else
    message("     -> Stable. Say so in Methods; it pre-empts the arbitrariness objection.")
}

DIAG$k_sweep <- ggplot(sweep, aes(K, peak_day)) +
  geom_line(colour = PAL[["mute"]]) +
  geom_point(aes(colour = r2), size = 3) +
  scale_colour_gradient(low = PAL[["gold"]], high = PAL[["blue"]], name = "in-sample R2") +
  scale_y_continuous(breaks = MON_B, labels = MON_L, limits = c(1, 365)) +
  facet_wrap(~ site) +
  labs(title = "Does the peak day survive a change in K?",
       subtitle = paste0("Day of maximum beta(t) as the number of retained components varies.\n",
                         "A flat line means the timing is data-driven. A staircase means it is K-driven,\n",
                         "and no daily recommendation is defensible."),
       x = "components retained (K)", y = "day of peak beta(t)") +
  theme_wh

# =============================================================================
# 2b. WHERE THE TWO RULES LAND
# -----------------------------------------------------------------------------
# The scree plot with both thresholds drawn on it. This is the figure that makes
# the choice concrete: you can see how many components clear an individual bar,
# how many the cumulative rule wants, and whether any component sits close enough
# to the individual threshold to flip in and out between CV folds.
# =============================================================================
message("\n== 2b. component spectrum and where each rule lands ==")

scree <- bind_rows(lapply(names(BR$fits), function(s) {
  pc <- prcomp(BR$fits[[s]]$Curves, center = TRUE)
  vp <- pc$sdev^2 / sum(pc$sdev^2) * 100
  k  <- min(20L, length(vp))
  data.frame(site = s, comp = seq_len(k), var_individual = vp[seq_len(k)],
             var_cumulative = cumsum(vp)[seq_len(k)])
}))

rule_k <- scree %>% group_by(site) %>%
  summarise(K_cumulative = if (any(var_cumulative >= FPC_VAR))
                             which(var_cumulative >= FPC_VAR)[1] else NA_integer_,
            K_individual = sum(var_individual >= FPC_MIN),
            nearest_to_threshold = min(abs(var_individual - FPC_MIN)),
            .groups = "drop") %>%
  mutate(K_in_force = pmin(switch(FPC_RULE, cumulative = K_cumulative,
                                  individual = K_individual,
                                  both = pmin(K_cumulative, K_individual)), FPC_MAX),
         capped = K_in_force == FPC_MAX,
         fold_unstable = nearest_to_threshold < 0.5)

print(as.data.frame(rule_k), row.names = FALSE, digits = 3)
write.csv(rule_k, file.path(OUT, "tables", "fpc_diagnostics_rules.csv"), row.names = FALSE)

if (any(rule_k$capped, na.rm = TRUE))
  message("\n  NOTE: at least one site is CAPPED at fpc_max = ", FPC_MAX,
          ".\n  The rule wanted more components than the cap allows, so fpc_max --",
          "\n  not the variance rule -- is what is setting K there.")
if (any(rule_k$fold_unstable, na.rm = TRUE))
  message("\n  WARNING: a component sits within 0.5%% of fpc_min_var at some site.",
          "\n  It will drop in and out between CV folds, making cross-validation",
          "\n  noisier than it appears. Move the threshold away from that value.")

DIAG$scree <- ggplot(scree, aes(comp, var_individual)) +
  geom_col(fill = PAL[["blue"]], alpha = 0.8) +
  geom_hline(yintercept = FPC_MIN, colour = PAL[["red"]], linetype = 2) +
  geom_vline(data = rule_k, aes(xintercept = K_cumulative + 0.5),
             colour = PAL[["gold"]], linewidth = 0.9) +
  facet_wrap(~ site) +
  scale_x_continuous(breaks = seq(2, 20, 2)) +
  labs(title = "Where each truncation rule lands",
       subtitle = paste0("Bars = individual % of flow variance. Red dashed = fpc_min_var (",
                         FPC_MIN, "%): components above it clear the INDIVIDUAL rule.\n",
                         "Gold line = where the CUMULATIVE rule (", FPC_VAR,
                         "%) stops. A bar sitting on the red line will flip in and out\n",
                         "between CV folds -- move the threshold if so."),
       x = "component", y = "% of flow variance") +
  theme_wh

# =============================================================================
# 3. CROSS-SITE BASIS COMPARABILITY  (+ a pooled common basis if you need one)
# -----------------------------------------------------------------------------
# Per-site FPCA gives each site its own eigenfunctions, so beta(t) curves live in
# different spaces and cross-site comparison is confounded with basis similarity.
# This measures how bad that is, and builds the fix.
# =============================================================================
if (length(BR$fits) >= 2) {
  message("\n== 3. cross-site basis comparability ==")

  phis <- lapply(BR$fits, function(f) prcomp(f$Curves, center = TRUE)$rotation[, 1:3, drop = FALSE])
  sites <- names(phis)

  # |inner product| between leading eigenfunctions; sign is arbitrary, so abs()
  cmp <- expand.grid(a = sites, b = sites, comp = 1:3, stringsAsFactors = FALSE) %>%
    filter(a < b) %>%
    mutate(alignment = mapply(function(A, B, k)
      abs(sum(phis[[A]][, k] * phis[[B]][, k])), a, b, comp))

  print(as.data.frame(cmp), row.names = FALSE, digits = 3)
  write.csv(cmp, file.path(OUT, "tables", "fpc_diagnostics_basis.csv"), row.names = FALSE)

  worst_pc1 <- min(cmp$alignment[cmp$comp == 1])
  message("")
  message(sprintf("  Lowest alignment on the leading component: %.3f", worst_pc1))
  if (worst_pc1 > 0.95)
    message("  Bases are near-identical across sites. Cross-site comparison of beta(t)\n",
            "  is safe; report this table in SI and the objection is defused.")
  else
    message("  Bases DIFFER across sites. Comparing beta(t) between them confounds\n",
            "  biology with basis. Use the pooled common basis written below, or\n",
            "  use the penalized arm for the among-site synthesis.")

  DIAG$basis <- ggplot(cmp, aes(paste(a, b, sep = "\nvs "), alignment, fill = factor(comp))) +
    geom_col(position = "dodge") +
    geom_hline(yintercept = 0.95, linetype = 2, colour = PAL[["red"]]) +
    scale_y_continuous(limits = c(0, 1)) +
    scale_fill_brewer(palette = "Blues", name = "component") +
    labs(title = "Do sites share the same eigenfunctions?",
         subtitle = paste0("Absolute inner product between sites' components. 1 = identical shape.\n",
                           "Below the red line, beta(t) curves are not directly comparable across sites."),
         x = NULL, y = "alignment") +
    theme_wh

  # --- the fix: one basis for every site -------------------------------------
  # Pool all sites' standardized curves, run FPCA once, and use those shared
  # eigenfunctions everywhere. Site-specific scores, common Phi. beta(t) curves
  # then live in one space and are directly comparable.
  # Guard the extraction. If `Curves` were ever renamed, `[[` yields NULL, rbind
  # silently produces NULL, and the failure appears later as a prcomp error on a
  # NULL matrix. Checking here names the actual problem.
  stopifnot(all(vapply(BR$fits, function(f) !is.null(f$Curves), logical(1))))
  pooled <- do.call(rbind, lapply(BR$fits, function(f) f$Curves))
  pc_pool <- prcomp(pooled, center = TRUE)
  saveRDS(list(rotation = pc_pool$rotation, center = pc_pool$center,
               sdev = pc_pool$sdev, n_curves = nrow(pooled),
               note = paste("Common eigenfunction basis across all sites. To use:",
                            "project each site's curves onto rotation[, 1:K] to get",
                            "scores, regress, and map back with the SAME rotation.")),
          file.path(OUT, "models", "fpc_common_basis.rds"))
  message("\n  wrote output/models/fpc_common_basis.rds (", nrow(pooled),
          " curves pooled across ", length(BR$fits), " sites)")
}

for (nm in names(DIAG))
  ggsave(file.path(OUT, "figures", paste0("fpc_diag_", nm, ".png")), DIAG[[nm]],
         width = 9.5, height = 5, dpi = 150)

message("\n  Diagnostics written. See docs/notes/FPC_reviewer_critiques.md for how to")
message("  report each one, and what to do if a check comes back badly.\n")
