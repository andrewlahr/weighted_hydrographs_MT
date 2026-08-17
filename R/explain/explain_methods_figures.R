# =============================================================================
# explain_methods_figures.R
#
# EIGHT FIGURES THAT EXPLAIN THE STATISTICAL FRAMEWORK.
#
# This script needs NO DATA. It simulates a hydrograph record with a KNOWN
# flow-recruitment relationship, then shows what each step of the analysis does
# to it. Because the truth is known, you can see when a method recovers it and
# when it doesn't.
#
# Run the whole thing:
#     source("R/explain/explain_methods_figures.R")
# Figures are written to figures/explain/ and also returned in the list FIGS,
# so you can print one at a time:  print(FIGS$fig3_integral)
#
# Every figure is built with plain ggplot in-line. There are only two custom
# functions in the file and both are three lines long.
#
# Use these in talks and in the manuscript's SI. The simulated truth makes them
# honest teaching figures rather than post-hoc rationalisations of a result.
# =============================================================================

suppressPackageStartupMessages({
  library(ggplot2); library(dplyr); library(tidyr); library(mgcv)
})

dir.create("figures/explain", recursive = TRUE, showWarnings = FALSE)
FIGS <- list()

MONTH_BREAKS <- c(1, 32, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335)
theme_ex <- theme_classic(base_size = 11) +
  theme(plot.title    = element_text(face = "bold", size = 12),
        plot.subtitle = element_text(size = 9.5, colour = "grey35"),
        strip.background = element_rect(fill = "grey95", colour = NA),
        strip.text = element_text(face = "bold", size = 9))
x_month <- scale_x_continuous(breaks = MONTH_BREAKS, labels = month.abb)

# CUSTOM FUNCTION 1 of 2 -------------------------------------------------------
# Out-of-sample R-squared. Negative means "worse than just predicting the mean".
r2_oos <- function(observed, predicted) {
  1 - sum((observed - predicted)^2) / sum((observed - mean(observed))^2)
}

# CUSTOM FUNCTION 2 of 2 -------------------------------------------------------
# Fit beta(t) with a wiggliness penalty. Returns the curve on the daily grid.
# This is exactly what fit_penalized_beta() does in the real pipeline, minus the
# bookkeeping.
fit_beta_penalized <- function(y, X, k = 15, sp = NULL) {
  DOY <- matrix(1:365, nrow(X), 365, byrow = TRUE)
  m <- mgcv::gam(y ~ s(DOY, by = X, bs = "ps", k = k), method = "REML", sp = sp)
  pr <- predict(m, newdata = list(DOY = matrix(1:365, ncol = 1),
                                  X = matrix(1, nrow = 365, ncol = 1)),
                type = "terms", se.fit = TRUE)
  list(beta = as.numeric(pr$fit[, 1]), se = as.numeric(pr$se.fit[, 1]),
       edf = sum(m$edf), sp = m$sp, model = m)
}


# =============================================================================
# SIMULATE A WORLD WHERE WE KNOW THE ANSWER
# -----------------------------------------------------------------------------
# 43 years, a snowmelt hydrograph that varies between years in TWO ways:
#   magnitude (wet years vs dry years) and timing (early vs late peak).
# The true beta(t) says: summer base flow HELPS recruitment, and a big spring
# runoff HURTS it (fry displacement). Nothing else matters.
# =============================================================================

set.seed(42)
n_years <- 43
doy     <- 1:365
years   <- 1980:(1980 + n_years - 1)

magnitude <- rnorm(n_years, 0, 0.35)     # wet/dry
timing    <- rnorm(n_years, 0, 12)       # early/late snowmelt

Q_log <- t(vapply(seq_len(n_years), function(i) {
  4.0 +
    (1.20 + magnitude[i]) * exp(-((doy - (150 + timing[i]))^2) / (2 * 35^2)) +
    0.30 * exp(-((doy - 330)^2) / (2 * 40^2)) +
    rnorm(365, 0, 0.04)
}, numeric(365)))

# --- standardization, exactly as build_flow_cache.R does it ------------------
ch        <- colMeans(Q_log)                       # per-day climatology
anomaly   <- sweep(Q_log, 2, ch, "-")              # subtract it
global_sd <- sd(as.vector(anomaly))                # ONE global scale
X_std     <- anomaly / global_sd                   # [43 x 365]

# --- the TRUE beta(t) and the response ---------------------------------------
beta_true <- 0.0045 * exp(-((doy - 230)^2) / (2 * 30^2)) -   # summer helps
             0.0035 * exp(-((doy - 140)^2) / (2 * 25^2))     # runoff hurts
eta_true  <- as.numeric(X_std %*% beta_true)
y_obs     <- 0.5 + eta_true + rnorm(n_years, 0, 0.40)        # log(R/S)

cat(sprintf("Simulated: %d years | SD of true signal = %.3f | SD of noise = 0.40\n",
            n_years, sd(eta_true)))
cat(sprintf("So the true R-squared is about %.2f. This is a GENEROUS simulation --\n",
            var(eta_true) / (var(eta_true) + 0.40^2)))
cat("your real data almost certainly has a weaker signal than this.\n\n")


# =============================================================================
# FIGURE 1 — What "standardizing the hydrograph" means
# =============================================================================
d1 <- bind_rows(
  data.frame(doy = rep(doy, n_years), value = as.vector(t(Q_log)),
             year = rep(years, each = 365), step = "1. Raw log discharge"),
  data.frame(doy = rep(doy, n_years), value = as.vector(t(anomaly)),
             year = rep(years, each = 365), step = "2. Minus the day-of-year mean"),
  data.frame(doy = rep(doy, n_years), value = as.vector(t(X_std)),
             year = rep(years, each = 365), step = "3. Divided by one global SD")
) %>% mutate(step = factor(step, levels = unique(step)))

FIGS$fig1_standardize <- ggplot(d1, aes(doy, value, group = year)) +
  geom_line(alpha = 0.22, linewidth = 0.35, colour = "#2c6fa8") +
  geom_hline(data = filter(d1, step != "1. Raw log discharge"),
             aes(yintercept = 0), linetype = 2, colour = "#b5462f") +
  facet_wrap(~ step, scales = "free_y") +
  x_month +
  labs(title = "Figure 1. Standardizing the hydrograph",
       subtitle = paste0("Each line is one year. Step 2 removes the seasonal cycle so only the ANOMALY remains --\n",
                         "how unusual that day was. Step 3 puts every day on the same scale (one global SD = ",
                         round(global_sd, 3), ")."),
       x = NULL, y = NULL) +
  theme_ex

# NOTE ON STEP 3: the scale is ONE number for the whole year, not one per day.
# A per-day scale would make a quiet winter day's small wobble look as important
# as a big swing at the snowmelt peak. That is not what you want.


# =============================================================================
# FIGURE 2 — What FPCA does: PCA, but on curves
# =============================================================================
pca <- prcomp(X_std, center = TRUE)
varprop <- pca$sdev^2 / sum(pca$sdev^2)
mu_curve <- colMeans(X_std)

d2 <- bind_rows(lapply(1:2, function(k) {
  amp <- 2 * pca$sdev[k]
  data.frame(
    doy   = rep(doy, 3),
    value = c(mu_curve, mu_curve + amp * pca$rotation[, k],
              mu_curve - amp * pca$rotation[, k]),
    what  = rep(c("mean year", "mean + 2 SD of this mode",
                  "mean - 2 SD of this mode"), each = 365),
    mode  = sprintf("Mode %d  (%.0f%% of between-year variation)", k, 100 * varprop[k])
  )
})) %>% mutate(what = factor(what, levels = c("mean - 2 SD of this mode",
                                              "mean year",
                                              "mean + 2 SD of this mode")))

FIGS$fig2_fpca <- ggplot(d2, aes(doy, value, colour = what, linewidth = what)) +
  geom_hline(yintercept = 0, linetype = 3, colour = "grey70") +
  geom_line() +
  facet_wrap(~ mode) +
  scale_colour_manual(values = c("mean - 2 SD of this mode" = "#b5462f",
                                 "mean year" = "grey25",
                                 "mean + 2 SD of this mode" = "#2c6fa8"), name = NULL) +
  scale_linewidth_manual(values = c(0.8, 1.3, 0.8), guide = "none") +
  x_month +
  labs(title = "Figure 2. FPCA = principal components, but the data are curves",
       subtitle = paste0("Each 'mode' is a SHAPE that years differ along. Mode 1 here is mostly wet-vs-dry;\n",
                         "Mode 2 is mostly early-vs-late snowmelt. Every year gets a SCORE on each mode,\n",
                         "so 43 curves of 365 points become 43 rows of a few numbers."),
       x = NULL, y = "standardized anomaly") +
  theme_ex + theme(legend.position = "bottom")


# =============================================================================
# FIGURE 3 — THE KEY FIGURE. What beta(t) is and what the integral means.
# =============================================================================
show_year <- which.max(abs(eta_true))          # the most extreme year
d3 <- data.frame(
  doy   = rep(doy, 3),
  value = c(beta_true, X_std[show_year, ], beta_true * X_std[show_year, ]),
  panel = rep(c("A.  beta(t) -- the effect of one unit of flow on each day",
                sprintf("B.  x(t) -- the standardized hydrograph for %d", years[show_year]),
                "C.  beta(t) x x(t) -- the product, day by day"), each = 365)
) %>% mutate(panel = factor(panel, levels = unique(panel)))

eta_this <- sum(beta_true * X_std[show_year, ])

FIGS$fig3_integral <- ggplot(d3, aes(doy, value)) +
  geom_hline(yintercept = 0, colour = "grey55", linetype = 2) +
  geom_ribbon(data = filter(d3, grepl("^C", panel)),
              aes(ymin = pmin(value, 0), ymax = pmax(value, 0),
                  fill = value > 0), alpha = 0.55) +
  geom_line(linewidth = 0.85, colour = "grey15") +
  scale_fill_manual(values = c("TRUE" = "#2c6fa8", "FALSE" = "#b5462f"), guide = "none") +
  facet_wrap(~ panel, ncol = 1, scales = "free_y") +
  x_month +
  labs(title = "Figure 3. What the functional regression actually computes",
       subtitle = paste0("Panel C is Panel A times Panel B. ADD UP the shaded area and you get ONE NUMBER for the year:\n",
                         "eta = ", round(eta_this, 3), ".  Blue area pushes recruitment up, red pushes it down.\n",
                         "That single number is what every BoR scenario comparison is ultimately about."),
       x = NULL, y = NULL) +
  theme_ex

# IN WORDS: eta = sum over days of beta(t) * x(t). Where beta is positive, a
# wetter-than-normal day helps. Where beta is negative, a wetter-than-normal day
# hurts. The recruitment multiplier reported to BoR is exp(eta - mean(eta)).


# =============================================================================
# FIGURE 4 — "penalized" vs "fpc": two different assumptions, not right vs wrong
# =============================================================================
# fpc estimator: keep the top K modes, regress on their scores, convert back
K <- 8
scores  <- pca$x[, 1:K, drop = FALSE]
fit_fpc <- lm(y_obs ~ scores)
beta_fpc <- as.numeric(pca$rotation[, 1:K, drop = FALSE] %*% coef(fit_fpc)[-1])

# penalized estimator
pen <- fit_beta_penalized(y_obs, X_std)

d4 <- data.frame(
  doy   = rep(doy, 3),
  beta  = c(beta_true, beta_fpc, pen$beta),
  what  = rep(c("TRUTH (known, because we simulated it)",
                sprintf("fpc: top %d modes + least squares (%d parameters)", K, K + 1),
                sprintf("penalized: smooth spline (%.1f effective parameters)", pen$edf)),
              each = 365)
) %>% mutate(what = factor(what, levels = unique(what)))

FIGS$fig4_estimators <- ggplot(d4, aes(doy, beta, colour = what, linewidth = what)) +
  geom_hline(yintercept = 0, linetype = 2, colour = "grey55") +
  geom_line() +
  scale_colour_manual(values = c("grey15", "#b5462f", "#2c6fa8"), name = NULL) +
  scale_linewidth_manual(values = c(1.5, 0.85, 0.85), guide = "none") +
  x_month +
  labs(title = "Figure 4. Two ways to estimate beta(t) from only 43 years",
       subtitle = paste0("You cannot estimate 365 numbers from 43 observations, so both methods impose a constraint.\n",
                         "fpc says: 'beta must be built from the shapes flow varies in.'  ",
                         "penalized says: 'beta must be smooth.'\n",
                         "Neither is correct a priori. At n = 43 the ASSUMPTION does most of the work."),
       x = NULL, y = expression(beta(t))) +
  theme_ex + theme(legend.position = "bottom", legend.direction = "vertical")


# =============================================================================
# FIGURE 5 — What the smoothing parameter "sp" does
# =============================================================================
sp_vals <- c(1e-4, pen$sp, 1e3)
sp_lab  <- c("sp tiny -- chases noise", "sp chosen by REML", "sp huge -- flattens everything")
d5 <- bind_rows(lapply(seq_along(sp_vals), function(i) {
  f <- fit_beta_penalized(y_obs, X_std, sp = sp_vals[i])
  data.frame(doy = doy, beta = f$beta,
             what = sprintf("%s\n(sp = %.3g, %.1f effective params)", sp_lab[i], sp_vals[i], f$edf))
})) %>% mutate(what = factor(what, levels = unique(what)))

FIGS$fig5_smoothing <- ggplot(d5, aes(doy, beta)) +
  geom_hline(yintercept = 0, linetype = 2, colour = "grey55") +
  geom_line(data = data.frame(doy = doy, beta = beta_true),
            colour = "grey60", linewidth = 1.4) +
  geom_line(colour = "#2c6fa8", linewidth = 0.95) +
  facet_wrap(~ what) +
  x_month +
  labs(title = "Figure 5. The smoothing parameter 'sp' is a dial, not a setting",
       subtitle = "Grey = the truth. Blue = the estimate. REML picks sp automatically; sp_mode controls whether it is picked once or once per posterior draw.",
       x = NULL, y = expression(beta(t))) +
  theme_ex


# =============================================================================
# FIGURE 6 — Why there are 20,000 beta curves, and how they get combined
# =============================================================================
# Each posterior draw of abundance gives a different log(R/S) series, hence a
# different beta(t). Simulated here with 60 draws for speed.
M <- 60
beta_draws <- matrix(NA_real_, M, 365)
var_draws  <- matrix(NA_real_, M, 365)
for (m in seq_len(M)) {
  y_m <- y_obs + rnorm(n_years, 0, 0.22)      # abundance uncertainty moves the response
  f_m <- fit_beta_penalized(y_m, X_std, sp = pen$sp)
  beta_draws[m, ] <- f_m$beta
  var_draws[m, ]  <- f_m$se^2
}

set.seed(1)
beta_star <- beta_draws + sqrt(var_draws) * matrix(rnorm(M * 365), M, 365)
pooled <- data.frame(
  doy  = doy,
  mid  = colMeans(beta_draws),
  lo95 = apply(beta_star, 2, quantile, 0.025),
  hi95 = apply(beta_star, 2, quantile, 0.975),
  lo50 = apply(beta_star, 2, quantile, 0.25),
  hi50 = apply(beta_star, 2, quantile, 0.75)
)
draws_long <- data.frame(doy = rep(doy, M), beta = as.vector(t(beta_draws)),
                         draw = rep(seq_len(M), each = 365))

FIGS$fig6_pooling <- ggplot() +
  geom_hline(yintercept = 0, linetype = 2, colour = "grey55") +
  geom_line(data = draws_long, aes(doy, beta, group = draw),
            colour = "grey72", alpha = 0.35, linewidth = 0.3) +
  geom_ribbon(data = pooled, aes(doy, ymin = lo95, ymax = hi95),
              fill = "#2c6fa8", alpha = 0.16) +
  geom_ribbon(data = pooled, aes(doy, ymin = lo50, ymax = hi50),
              fill = "#2c6fa8", alpha = 0.38) +
  geom_line(data = pooled, aes(doy, mid), colour = "#08306b", linewidth = 1.1) +
  geom_line(data = data.frame(doy = doy, beta = beta_true),
            aes(doy, beta), colour = "#b5462f", linewidth = 1.1, linetype = "longdash") +
  x_month +
  labs(title = "Figure 6. Combining one beta(t) per posterior draw",
       subtitle = paste0("Grey = one beta(t) per draw of abundance (", M, " shown). Dark blue = the average.\n",
                         "Bands = 50% and 95%, obtained by sampling once from each draw's own uncertainty and taking quantiles.\n",
                         "Red dashed = truth. TWO sources of uncertainty are combined: how well each draw is fitted (within),\n",
                         "and how much the answer moves as abundance moves (between). That is all Rubin pooling ever meant."),
       x = NULL, y = expression(beta(t))) +
  theme_ex

# Variance split — the diagnostic worth reporting
d6b <- data.frame(
  doy = rep(doy, 2),
  variance = c(colMeans(var_draws), apply(beta_draws, 2, var)),
  source = rep(c("within-draw (how precisely each fit is estimated)",
                 "between-draw (how much abundance uncertainty moves it)"), each = 365)
)
FIGS$fig6b_variance <- ggplot(d6b, aes(doy, variance, fill = source)) +
  geom_area(position = "stack", alpha = 0.8) +
  scale_fill_manual(values = c("#2c6fa8", "#c9a227"), name = NULL) +
  x_month +
  labs(title = "Figure 6b. Where the uncertainty in beta(t) comes from",
       subtitle = "If the gold band dominates, abundance uncertainty is the limiting factor and a better hydrograph model will not help.",
       x = NULL, y = "variance") +
  theme_ex + theme(legend.position = "bottom", legend.direction = "vertical")


# =============================================================================
# FIGURE 7 — Leave-one-out flatters the model; blocked CV does not
# =============================================================================
pred_loo <- numeric(n_years)
for (i in seq_len(n_years)) {
  f <- fit_beta_penalized(y_obs[-i], X_std[-i, , drop = FALSE], sp = pen$sp)
  pred_loo[i] <- sum(f$beta * X_std[i, ]) +
    mean(y_obs[-i] - as.numeric(X_std[-i, ] %*% f$beta))
}
block_len <- 5
pred_blk <- numeric(n_years)
for (s in seq(1, n_years, by = block_len)) {
  idx <- s:min(s + block_len - 1, n_years)
  f <- fit_beta_penalized(y_obs[-idx], X_std[-idx, , drop = FALSE], sp = pen$sp)
  pred_blk[idx] <- as.numeric(X_std[idx, , drop = FALSE] %*% f$beta) +
    mean(y_obs[-idx] - as.numeric(X_std[-idx, ] %*% f$beta))
}
r2_loo <- r2_oos(y_obs, pred_loo); r2_blk <- r2_oos(y_obs, pred_blk)

d7 <- bind_rows(
  data.frame(observed = y_obs, predicted = pred_loo,
             what = sprintf("Leave-one-year-out   R2 = %+.3f", r2_loo)),
  data.frame(observed = y_obs, predicted = pred_blk,
             what = sprintf("Blocked (%d-year)   R2 = %+.3f", block_len, r2_blk))
)

FIGS$fig7_cv <- ggplot(d7, aes(predicted, observed)) +
  geom_abline(slope = 1, intercept = 0, linetype = 2, colour = "grey55") +
  geom_hline(aes(yintercept = mean(y_obs)), linetype = 3, colour = "#b5462f") +
  geom_point(size = 2.6, alpha = 0.8, colour = "#2c6fa8") +
  facet_wrap(~ what) +
  labs(title = "Figure 7. Why leave-one-out is too easy for a flow time series",
       subtitle = paste0("Held out one year, its neighbours stay in the training set -- and neighbouring hydrographs look alike,\n",
                         "so the model INTERPOLATES rather than predicts. Holding out 5-year blocks removes that crutch.\n",
                         "Red dotted line = predicting the series mean. Anything not beating that line has R2 below zero."),
       x = "predicted log(R/S)", y = "observed log(R/S)") +
  theme_ex


# =============================================================================
# FIGURE 8 — The permutation null: how good would this look by luck?
# =============================================================================
null_r2 <- vapply(seq_len(n_years - 1), function(s) {
  y_shift <- y_obs[c((s + 1):n_years, 1:s)]     # circular shift, wraps around
  p <- numeric(n_years)
  for (st in seq(1, n_years, by = block_len)) {
    idx <- st:min(st + block_len - 1, n_years)
    f <- fit_beta_penalized(y_shift[-idx], X_std[-idx, , drop = FALSE], sp = pen$sp)
    p[idx] <- as.numeric(X_std[idx, , drop = FALSE] %*% f$beta) +
      mean(y_shift[-idx] - as.numeric(X_std[-idx, ] %*% f$beta))
  }
  r2_oos(y_shift, p)
}, numeric(1))

p_val <- (1 + sum(null_r2 >= r2_blk)) / (1 + length(null_r2))

FIGS$fig8_permutation <- ggplot(data.frame(r2 = null_r2), aes(r2)) +
  geom_histogram(bins = 22, fill = "grey78", colour = "white") +
  geom_vline(xintercept = r2_blk, colour = "#b5462f", linewidth = 1.2) +
  annotate("text", x = r2_blk, y = Inf, hjust = -0.05, vjust = 1.8,
           label = sprintf("observed = %+.3f\np = %.3f", r2_blk, p_val),
           colour = "#b5462f", size = 3.5) +
  labs(title = "Figure 8. The permutation null",
       subtitle = paste0("Each grey bar is a blocked-CV R2 obtained after sliding recruitment forward against flow and wrapping around.\n",
                         "Flow and recruitment each keep their own year-to-year structure; only their ALIGNMENT is broken.\n",
                         "With ", n_years, " years there are only ", n_years - 1,
                         " shifts, so the smallest p-value achievable is ",
                         sprintf("%.3f", 1 / n_years), ". That is a limit of the data, not the method."),
       x = "blocked-CV R2 under a shifted alignment", y = "count") +
  theme_ex


# =============================================================================
# SAVE
# =============================================================================
sizes <- list(
  fig1_standardize = c(11, 3.8), fig2_fpca = c(10, 4.2),
  fig3_integral = c(8.5, 8),     fig4_estimators = c(9, 5.6),
  fig5_smoothing = c(11, 4.2),   fig6_pooling = c(9.5, 6),
  fig6b_variance = c(9, 4.4),    fig7_cv = c(9.5, 4.6),
  fig8_permutation = c(9, 4.6)
)
for (nm in names(FIGS)) {
  wh <- sizes[[nm]]
  ggsave(file.path("figures/explain", paste0(nm, ".png")), FIGS[[nm]],
         width = wh[1], height = wh[2], dpi = 160)
}

cat("\n--- Wrote", length(FIGS), "figures to figures/explain/ ---\n\n")
cat(sprintf("In this SIMULATION, where a real signal exists by construction:\n"))
cat(sprintf("  leave-one-out R2   = %+.3f   <- flattering\n", r2_loo))
cat(sprintf("  blocked CV R2      = %+.3f   <- honest\n", r2_blk))
cat(sprintf("  permutation p      =  %.3f\n\n", p_val))
cat("Compare those to what Norris gives you. If the gap between LOO and blocked\n")
cat("is larger in your real data than it is here, autocorrelation is doing more\n")
cat("of the work in your result than signal is.\n")
