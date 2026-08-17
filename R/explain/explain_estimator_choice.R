# =============================================================================
# explain_estimator_choice.R
#
# PENALIZED SPLINE vs FPC: what the two priors actually do to beta(t), and what
# that means for a DAILY release recommendation.
#
# Needs no data. Simulates hydrographs with a KNOWN beta(t), so you can see when
# each estimator recovers the truth and when it invents structure.
#
#     source("R/explain/explain_estimator_choice.R")
#
# THE QUESTION THIS ANSWERS
# -------------------------
# Both estimators solve the same impossible problem -- 365 unknowns from ~40
# observations -- by adding a constraint:
#
#   penalized : beta(t) must be SMOOTH
#   fpc       : beta(t) must be built from the leading modes of variation in FLOW
#
# For the "does flow matter at all" question they usually agree. For the "which
# DAY should I release water" question they can disagree sharply, and this script
# shows why.
# =============================================================================

suppressPackageStartupMessages({
  library(ggplot2); library(dplyr); library(tidyr); library(mgcv)
})
dir.create("output/figures/explain", recursive = TRUE, showWarnings = FALSE)
EST <- list()

MON_B <- c(1, 32, 62, 93, 124, 152, 183, 213, 244, 274, 305, 335)
MON_L <- c("Oct","Nov","Dec","Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep")
th <- theme_classic(base_size = 11) +
  theme(plot.title = element_text(face = "bold", size = 12),
        plot.subtitle = element_text(size = 9.5, colour = "grey35"),
        strip.background = element_rect(fill = "grey95", colour = NA),
        strip.text = element_text(face = "bold", size = 9))
xm <- scale_x_continuous(breaks = MON_B, labels = MON_L)

# =============================================================================
# SIMULATE A WATER YEAR RECORD WITH A KNOWN ANSWER
# -----------------------------------------------------------------------------
# 42 calendar years. Hydrographs vary in three ways, which is roughly what real
# snowmelt records do: overall wetness, snowmelt timing, and summer baseflow.
# =============================================================================
set.seed(11)
n <- 42; doy <- 1:365

wet    <- rnorm(n, 0, 0.35)     # wet vs dry years
timing <- rnorm(n, 0, 14)       # early vs late snowmelt
summer <- rnorm(n, 0, 0.30)     # independent summer baseflow variation

Xraw <- t(vapply(seq_len(n), function(i) {
  (1.10 + wet[i]) * exp(-((doy - (190 + timing[i]))^2) / (2 * 34^2)) +
  (0.55 + summer[i]) * exp(-((doy - 300)^2) / (2 * 45^2)) +
  0.25 * exp(-((doy - 40)^2) / (2 * 30^2)) +
  rnorm(365, 0, 0.03)
}, numeric(365)))
X <- scale(Xraw, center = TRUE, scale = FALSE) / sd(Xraw)

# --- the TRUE beta(t): one NARROW window that matters --------------------------
# A tight 3-week benefit in late summer. Deliberately narrow: this is exactly the
# kind of feature a daily release recommendation would hang on, and exactly the
# kind the two estimators treat differently.
beta_true <- 0.055 * exp(-((doy - 285)^2) / (2 * 11^2)) -
             0.020 * exp(-((doy - 195)^2) / (2 * 22^2))
eta  <- as.numeric(X %*% beta_true)
yobs <- 0.4 + eta + rnorm(n, 0, 0.42)

cat(sprintf("Simulated %d years. True beta peaks on day %d (%s).\n", n,
            which.max(beta_true),
            format(as.Date("2000-10-01") + which.max(beta_true) - 1, "%d %b")))
cat(sprintf("True R-squared about %.2f -- generous relative to real data.\n\n",
            var(eta) / (var(eta) + 0.42^2)))

# --- the two estimators, written out plainly ---------------------------------
fit_pen <- function(y, X, k = 20) {
  L <- matrix(1:365, nrow(X), 365, byrow = TRUE)
  m <- gam(y ~ s(L, by = X, bs = "ps", k = k), method = "REML",
           data = list(y = y, L = L, X = X))
  nd <- list(L = matrix(1:365, 365, 365, byrow = TRUE), X = diag(365))
  Lp <- predict(m, newdata = nd, type = "lpmatrix")
  ii <- m$smooth[[1]]$first.para:m$smooth[[1]]$last.para
  Lp <- Lp[, ii, drop = FALSE]
  list(beta = as.numeric(Lp %*% coef(m)[ii]),
       V = Lp %*% vcov(m)[ii, ii] %*% t(Lp), edf = sum(m$edf[ii]))
}
fit_fpc <- function(y, X, target = 90, kmax = 10) {
  pc <- prcomp(X, center = TRUE)
  cv <- cumsum(pc$sdev^2) / sum(pc$sdev^2) * 100
  K  <- min(which(cv >= target)[1], kmax, length(y) - 3)
  Z  <- pc$x[, 1:K, drop = FALSE]
  m  <- lm(y ~ Z)
  Phi <- pc$rotation[, 1:K, drop = FALSE]
  b   <- coef(m)[-1]; Vb <- vcov(m)[-1, -1, drop = FALSE]
  list(beta = as.numeric(Phi %*% b), V = Phi %*% Vb %*% t(Phi),
       edf = K, Phi = Phi, cumvar = cv)
}
P <- fit_pen(yobs, X); F <- fit_fpc(yobs, X)


# =============================================================================
# FIGURE 1 — the eigenfunctions are GLOBAL, and that is the whole story
# =============================================================================
EST$e1_eigenfunctions <- data.frame(
  doy = rep(doy, 4),
  value = as.vector(F$Phi[, 1:4]),
  comp = rep(sprintf("phi %d  (%.0f%% of flow variance)", 1:4,
                     diff(c(0, F$cumvar[1:4]))), each = 365)) %>%
  ggplot(aes(doy, value)) +
  geom_hline(yintercept = 0, linetype = 2, colour = "grey60") +
  geom_line(colour = "#2c6fa8", linewidth = 0.8) +
  facet_wrap(~ comp) + xm +
  labs(title = "Figure 1. The FPC building blocks span the whole year",
       subtitle = paste0("beta(t) from the fpc estimator must be a weighted sum of these shapes.\n",
                         "Notice that phi 2 onward OSCILLATE across all 12 months. They are not local.\n",
                         "So a coefficient fitted because of a real August effect will also move beta(t) in\n",
                         "December, March and June -- not because anything happens then, but because that is\n",
                         "what the shape does."),
       x = NULL, y = NULL) + th


# =============================================================================
# FIGURE 2 — both estimators against a known truth
# =============================================================================
EST$e2_recovery <- bind_rows(
  data.frame(doy, beta = beta_true, what = "TRUTH (simulated)"),
  data.frame(doy, beta = P$beta,
             what = sprintf("penalized  (edf = %.1f)", P$edf)),
  data.frame(doy, beta = F$beta,
             what = sprintf("fpc  (K = %d, %.0f%% of flow variance)", F$edf, F$cumvar[F$edf]))
) %>% mutate(what = factor(what, levels = unique(what))) %>%
  ggplot(aes(doy, beta, colour = what, linewidth = what)) +
  geom_hline(yintercept = 0, linetype = 2, colour = "grey60") +
  geom_vline(xintercept = which.max(beta_true), linetype = 3, colour = "#b5462f") +
  geom_line() + xm +
  scale_colour_manual(values = c("grey20", "#2c6fa8", "#b5462f"), name = NULL) +
  scale_linewidth_manual(values = c(1.6, 0.9, 0.9), guide = "none") +
  labs(title = "Figure 2. Recovering a narrow late-summer benefit",
       subtitle = paste0("Dotted red line = where the truth actually peaks.\n",
                         "Both estimators find late summer. Look at what each does OUTSIDE that window:\n",
                         "the smoothness prior flattens toward zero, the FPC prior leaves ripples that are\n",
                         "eigenfunction geometry, not signal."),
       x = NULL, y = expression(beta(t))) +
  th + theme(legend.position = "bottom", legend.direction = "vertical")


# =============================================================================
# FIGURE 3 — THE ONE THAT MATTERS FOR YOUR DELIVERABLE
# -----------------------------------------------------------------------------
# Simulate curves from each estimator's covariance, take the argmax of each, and
# look at where the "best day to release" lands.
#
# The FPC distribution will typically be TIGHTER. That is not better precision --
# it is a rank-K covariance. Truncation uncertainty is missing, so the simulated
# curves can only take shapes the K retained components can make, and the spread
# understates what you actually know.
# =============================================================================
set.seed(2)
sim_argmax <- function(fit, nsim = 3000) {
  V <- (fit$V + t(fit$V)) / 2
  ev <- eigen(V, symmetric = TRUE)
  keep <- ev$values > max(ev$values) * 1e-10
  A <- ev$vectors[, keep, drop = FALSE] %*% diag(sqrt(ev$values[keep]), sum(keep))
  Z <- matrix(rnorm(nsim * ncol(A)), ncol(A), nsim)
  curves <- fit$beta + A %*% Z
  apply(curves, 2, which.max)
}
am <- bind_rows(
  data.frame(day = sim_argmax(P), estimator = "penalized"),
  data.frame(day = sim_argmax(F), estimator = "fpc"))

hdi <- am %>% group_by(estimator) %>%
  summarise(lo = quantile(day, .10), hi = quantile(day, .90), .groups = "drop")

EST$e3_bestday <- ggplot(am, aes(day)) +
  geom_histogram(bins = 73, fill = "grey78", colour = "white") +
  geom_vline(xintercept = which.max(beta_true), colour = "#b5462f", linewidth = 1.1) +
  geom_segment(data = hdi, aes(x = lo, xend = hi, y = -Inf, yend = -Inf),
               colour = "#2c6fa8", linewidth = 2.5) +
  facet_wrap(~ estimator, ncol = 1, scales = "free_y") + xm +
  labs(title = "Figure 3. Where is the best day to release? Two estimators, same data",
       subtitle = paste0("Each histogram is the day-of-peak across 3,000 curves drawn from that estimator's own\n",
                         "uncertainty. Red line = the truth. Blue bar = the 80% interval.\n\n",
                         "The fpc interval is usually NARROWER -- and that narrowness is an artefact. Its covariance\n",
                         "has rank K, so simulated curves can only take shapes the K retained components can make.\n",
                         "Truncation uncertainty is simply absent. Do not read it as better precision."),
       x = NULL, y = NULL) + th


# =============================================================================
# FIGURE 4 — when FPC fails outright: signal in a low-variance mode
# -----------------------------------------------------------------------------
# FPC ranks components by how much FLOW varies in them, then tests them against
# RECRUITMENT. Those are different questions. Here the true beta(t) is aligned
# with a component carrying little flow variance -- so truncation DELETES it.
# Deletion, not shrinkage: no amount of signal can bring it back.
# =============================================================================
pc_all    <- prcomp(X, center = TRUE)
low_comp  <- 12                                   # a genuinely minor flow mode
beta_hid  <- pc_all$rotation[, low_comp] * 0.5
eta_h     <- as.numeric(X %*% beta_hid)
y_hid     <- 0.4 + eta_h + rnorm(n, 0, 0.25)
Ph <- fit_pen(y_hid, X); Fh <- fit_fpc(y_hid, X)

EST$e4_lowvariance <- bind_rows(
  data.frame(doy, beta = beta_hid, what = "TRUTH (a low-variance flow mode)"),
  data.frame(doy, beta = Ph$beta, what = sprintf("penalized (edf = %.1f)", Ph$edf)),
  data.frame(doy, beta = Fh$beta, what = sprintf("fpc (K = %d -- mode %d never entered)",
                                                  Fh$edf, low_comp))
) %>% mutate(what = factor(what, levels = unique(what))) %>%
  ggplot(aes(doy, beta, colour = what, linewidth = what)) +
  geom_hline(yintercept = 0, linetype = 2, colour = "grey60") +
  geom_line() + xm +
  scale_colour_manual(values = c("grey20", "#2c6fa8", "#b5462f"), name = NULL) +
  scale_linewidth_manual(values = c(1.6, 0.9, 0.9), guide = "none") +
  labs(title = "Figure 4. The failure mode of truncation",
       subtitle = paste0("Here the real effect lives in flow mode ", low_comp,
                         ", which carries little flow variance, so the fpc arm drops it before\n",
                         "ever testing it against recruitment. The red curve is flat because the signal was DELETED,\n",
                         "not shrunk -- and no amount of signal strength can bring it back.\n",
                         "This is the classic objection to principal component regression (Jolliffe 1982)."),
       x = NULL, y = expression(beta(t))) +
  th + theme(legend.position = "bottom", legend.direction = "vertical")


# =============================================================================
# FIGURE 5 — agreement between estimators is the evidence worth having
# =============================================================================
EST$e5_agreement <- data.frame(
  doy, penalized = P$beta / sd(P$beta), fpc = F$beta / sd(F$beta)) %>%
  pivot_longer(-doy, names_to = "estimator", values_to = "beta_z") %>%
  ggplot(aes(doy, beta_z, colour = estimator)) +
  geom_hline(yintercept = 0, linetype = 2, colour = "grey60") +
  geom_line(linewidth = 0.9) + xm +
  scale_colour_manual(values = c(penalized = "#2c6fa8", fpc = "#b5462f"), name = NULL) +
  labs(title = "Figure 5. Where the two priors agree, the data are talking",
       subtitle = paste0("Both curves scaled to unit SD, so this compares SHAPE.\n",
                         sprintf("Correlation across the year: r = %.2f.\n", cor(P$beta, F$beta)),
                         "Days where both agree on sign and both put weight are days where the answer does NOT\n",
                         "depend on which prior you chose. That is the defensible basis for a release window --\n",
                         "stronger than either estimator's own confidence interval, because it survives a change\n",
                         "of assumption rather than assuming one."),
       x = NULL, y = "beta(t), scaled") + th


# =============================================================================
for (nm in names(EST))
  ggsave(file.path("output/figures/explain", paste0(nm, ".png")), EST[[nm]],
         width = 9.5, height = if (nm == "e3_bestday") 6.4 else 5.2, dpi = 160)

cat("Wrote", length(EST), "figures to output/figures/explain/\n\n")
cat("SUMMARY OF THE TRADE-OFF\n")
cat("------------------------\n")
cat(sprintf("  penalized : edf = %.1f, smooth prior, full-rank covariance\n", P$edf))
cat(sprintf("  fpc       : K = %d components, %.0f%% of flow variance, rank-%d covariance\n",
            F$edf, F$cumvar[F$edf], F$edf))
cat(sprintf("  shape correlation between them: r = %.2f\n\n", cor(P$beta, F$beta)))
cat("For 'does flow matter at all', either is fine -- and the seasonal anchor is\n")
cat("better than both, because it has more power.\n\n")
cat("For 'WHICH DAY should I release', prefer the penalized fit as primary, and\n")
cat("report the fpc fit alongside. Where they agree, you have a result that does\n")
cat("not depend on the prior. Where they disagree, the daily structure is coming\n")
cat("from the estimator, and no daily recommendation is defensible.\n")
