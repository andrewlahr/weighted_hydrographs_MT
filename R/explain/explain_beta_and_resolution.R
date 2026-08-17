# =============================================================================
# explain_beta_and_resolution.R
#
# FIVE FIGURES for the concepts that are new in the daily-scale workflow.
# NO DATA NEEDED -- it simulates a world where the true beta(t) is known, so you
# can see when a method recovers the truth and when it invents structure.
#
#     source("R/explain/explain_beta_and_resolution.R")
#
# Figures go to figures/explain/ and are also returned in the list EX.
#
# WHAT EACH ONE ANSWERS
#   E1  Why is the management curve a different shape from beta(t)?
#   E2  How precisely can I name the best day? (the argmax distribution)
#   E3  Why can I compare two days confidently when both CIs cross zero?
#   E4  Why are simultaneous bands wider, and when do I need them?
#   E5  What does effective df actually buy me in resolution?
# =============================================================================

suppressPackageStartupMessages({ library(ggplot2); library(dplyr); library(tidyr); library(mgcv) })
dir.create("figures/explain", recursive = TRUE, showWarnings = FALSE)
EX <- list()

MON_B <- c(1, 32, 62, 93, 124, 152, 183, 213, 244, 274, 305, 335)
MON_L <- c("Oct","Nov","Dec","Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep")
th <- theme_classic(base_size = 11) +
  theme(plot.title = element_text(face = "bold", size = 12),
        plot.subtitle = element_text(size = 9.5, colour = "grey35"))
xm <- scale_x_continuous(breaks = MON_B, labels = MON_L)

# =============================================================================
# SIMULATE A WORLD WHERE WE KNOW THE ANSWER
# -----------------------------------------------------------------------------
# Calendar-year axis: day 1 = Oct 1. Snowmelt peak in late May (~day 240), base flow
# in late summer (~day 300-365). 40 years.
# =============================================================================
set.seed(11)
n <- 40; d <- 1:365

# baseline discharge: big snowmelt peak, low autumn and summer base flow
Qbar <- 200 + 1800 * exp(-((d - 240)^2) / (2 * 40^2)) + 120 * exp(-((d - 60)^2) / (2 * 50^2))

mag  <- rnorm(n, 0, .35); tim <- rnorm(n, 0, 14)
Qlog <- t(vapply(seq_len(n), function(i)
  log(200 + (1800 * (1 + mag[i])) * exp(-((d - (240 + tim[i]))^2) / (2 * 40^2)) +
        120 * exp(-((d - 60)^2) / (2 * 50^2))) + rnorm(365, 0, .04), numeric(365)))

ch  <- colMeans(Qlog); anom <- sweep(Qlog, 2, ch, "-")
sig <- sd(as.vector(anom)); X <- anom / sig

# TRUTH: summer base flow helps a lot; big spring runoff hurts (fry displacement)
beta_true <- 0.0050 * exp(-((d - 310)^2) / (2 * 25^2)) -
             0.0035 * exp(-((d - 235)^2) / (2 * 22^2))
y <- 0.4 + as.numeric(X %*% beta_true) + rnorm(n, 0, .35)

# fit beta(t) and keep the FULL covariance
L <- matrix(1:365, n, 365, byrow = TRUE)
m <- gam(y ~ s(L, by = X, bs = "ps", k = 20), data = list(y = y, L = L, X = X), method = "REML")
Lp <- predict(m, newdata = list(L = matrix(1:365, 365, 365, byrow = TRUE), X = diag(365)),
              type = "lpmatrix")
ii <- m$smooth[[1]]$first.para:m$smooth[[1]]$last.para
Lp <- Lp[, ii, drop = FALSE]
b_hat <- as.numeric(Lp %*% coef(m)[ii])
Vb    <- Lp %*% vcov(m)[ii, ii] %*% t(Lp)
se    <- sqrt(diag(Vb))
edf   <- sum(m$edf[ii])
cat(sprintf("Simulated fit: edf = %.2f, heuristic resolution ~%.0f days\n\n", edf, 365 / edf))

# simulate whole curves from the full covariance -- everything below uses these
S <- 4000
Bsim <- matrix(b_hat, S, 365, byrow = TRUE) +
  matrix(rnorm(S * 365), S, 365) %*% chol(Vb + diag(1e-12, 365))

# =============================================================================
# E1 -- beta(t) is not the management curve
# =============================================================================
lever <- log1p(10 / Qbar) / sig                 # effect of +10 cfs, day by day
EX$E1 <- data.frame(d = d,
    `baseline discharge (cfs)` = Qbar,
    `beta(t): ecological sensitivity` = b_hat / max(abs(b_hat)),
    `s(t): benefit of +10 cfs` = (b_hat * lever) / max(abs(b_hat * lever)),
    check.names = FALSE) %>%
  pivot_longer(-d) %>%
  mutate(name = factor(name, levels = c("baseline discharge (cfs)",
                                        "beta(t): ecological sensitivity",
                                        "s(t): benefit of +10 cfs"))) %>%
  ggplot(aes(d, value)) +
  geom_hline(data = ~ filter(., name != "baseline discharge (cfs)"),
             aes(yintercept = 0), linetype = 2, colour = "grey60") +
  geom_line(linewidth = 1, colour = "#2c6fa8") +
  facet_wrap(~ name, ncol = 1, scales = "free_y") + xm +
  labs(title = "E1. Why the management curve is a different shape",
       subtitle = paste0("Middle: beta(t), the effect of a one-SD anomaly. Bottom: the effect of TEN ACTUAL CFS.\n",
                         "They differ because the same water is a large proportional change at base flow and a tiny\n",
                         "one at the snowmelt peak. Note the spring negative shrinks and the summer positive grows.\n",
                         "Read the middle panel for ecology, the bottom panel to advise a water manager."),
       x = NULL, y = NULL) + th

# =============================================================================
# E2 -- how precisely can we name the best day?
# =============================================================================
Ssens <- sweep(Bsim, 2, lever, "*")
best <- apply(Ssens, 1, which.max)
q80 <- quantile(best, c(.1, .9), names = FALSE)

EX$E2 <- ggplot(data.frame(best = best), aes(best)) +
  geom_histogram(bins = 73, fill = "#2c6fa8", alpha = .75, colour = NA) +
  geom_vline(xintercept = which.max(beta_true * lever), colour = "grey20",
             linewidth = 1, linetype = "longdash") +
  annotate("rect", xmin = q80[1], xmax = q80[2], ymin = -Inf, ymax = Inf,
           fill = NA, colour = "#b5462f", linetype = 3) +
  annotate("text", x = q80[2], y = Inf, hjust = -.05, vjust = 2,
           label = sprintf("80%% interval:\n%.0f days wide", q80[2] - q80[1]),
           colour = "#b5462f", size = 3.3) +
  xm + coord_cartesian(xlim = c(1, 365)) +
  labs(title = "E2. The distribution of the best day IS the answer",
       subtitle = paste0("Each of 4,000 simulated curves votes for the day where a release does most good.\n",
                         "Dashed line = the truth (known, because this is a simulation). Dotted box = 80% interval.\n",
                         "Report the BOX, not the peak of the fitted curve. A box narrower than ~90 days is real\n",
                         "timing guidance; a box spanning the year means the honest answer is a season."),
       x = NULL, y = "simulations") + th

# =============================================================================
# E3 -- contrasts beat overlapping intervals
# =============================================================================
t1 <- 310; t2 <- 235
diff_sim <- Bsim[, t1] - Bsim[, t2]
sd_ind <- sqrt(se[t1]^2 + se[t2]^2)                     # WRONG: assumes independence
sd_true <- sd(diff_sim)                                 # RIGHT: uses the covariance

EX$E3 <- data.frame(x = c(diff_sim, rnorm(S, mean(diff_sim), sd_ind)),
                    what = rep(c(sprintf("correct: uses the covariance (SD %.4f)", sd_true),
                                 sprintf("wrong: assumes independence (SD %.4f)", sd_ind)),
                               each = S)) %>%
  ggplot(aes(x, fill = what)) +
  geom_vline(xintercept = 0, linetype = 2, colour = "#b5462f", linewidth = .9) +
  geom_density(alpha = .5, colour = NA) +
  scale_fill_manual(values = c("#2c6fa8", "grey65"), name = NULL) +
  labs(title = "E3. Comparing two days: why overlapping intervals mislead",
       subtitle = paste0("Distribution of beta(day ", t1, ") - beta(day ", t2, ").\n",
                         "Adjacent and seasonally-linked days are CORRELATED, so the difference is estimated far\n",
                         "more precisely than the two pointwise intervals suggest. P(day ", t1, " > day ", t2, ") = ",
                         sprintf("%.3f", mean(diff_sim > 0)),
                         ".\nThis is why script 03 saves the full 365x365 covariance rather than just standard errors."),
       x = "difference in beta", y = "density") + th + theme(legend.position = "bottom")

# =============================================================================
# E4 -- simultaneous vs pointwise bands
# =============================================================================
c_sim <- quantile(apply(abs(sweep(Bsim, 2, b_hat, "-")) / rep(se, each = S), 1, max),
                  .95, names = FALSE)
EX$E4 <- data.frame(d = d, b = b_hat, se = se, truth = beta_true) %>%
  ggplot(aes(d)) +
  geom_hline(yintercept = 0, linetype = 2, colour = "grey60") +
  geom_ribbon(aes(ymin = b - c_sim * se, ymax = b + c_sim * se,
                  fill = sprintf("simultaneous 95%% (critical value %.2f)", c_sim)), alpha = .3) +
  geom_ribbon(aes(ymin = b - 1.96 * se, ymax = b + 1.96 * se,
                  fill = "pointwise 95% (critical value 1.96)"), alpha = .45) +
  geom_line(aes(y = b), colour = "#08306b", linewidth = 1) +
  geom_line(aes(y = truth), colour = "#b5462f", linewidth = 1, linetype = "longdash") +
  scale_fill_manual(values = c("grey70", "#9ecae1"), name = NULL) + xm +
  labs(title = "E4. Pointwise bands are the wrong tool for locating a peak",
       subtitle = paste0("Red dashed = truth. A pointwise band covers EACH DAY at 95% but the WHOLE CURVE at much\n",
                         "less, so 'the highest point is significant' is not a valid reading of it. For any claim\n",
                         "about WHERE the curve is high, use the simultaneous band -- typically 2.7-3.2 SEs, not 1.96."),
       x = NULL, y = expression(beta(t))) + th + theme(legend.position = "bottom")

# =============================================================================
# E5 -- what effective df buys you
# =============================================================================
res <- bind_rows(lapply(c(1e-2, 1e-4, 1e-6), function(sp) {
  mm <- gam(y ~ s(L, by = X, bs = "ps", k = 20), data = list(y = y, L = L, X = X), sp = sp)
  LL <- predict(mm, newdata = list(L = matrix(1:365, 365, 365, byrow = TRUE), X = diag(365)),
                type = "lpmatrix")
  jj <- mm$smooth[[1]]$first.para:mm$smooth[[1]]$last.para
  LL <- LL[, jj, drop = FALSE]
  bb <- as.numeric(LL %*% coef(mm)[jj]); VV <- LL %*% vcov(mm)[jj, jj] %*% t(LL)
  e <- sum(mm$edf[jj])
  BB <- matrix(bb, 1500, 365, byrow = TRUE) +
    matrix(rnorm(1500 * 365), 1500, 365) %*% chol(VV + diag(1e-12, 365))
  bw <- diff(quantile(apply(sweep(BB, 2, lever, "*"), 1, which.max), c(.1, .9), names = FALSE))
  data.frame(d = d, beta = bb,
             lab = sprintf("edf = %.1f  ->  best-day window %.0f days wide", e, bw))
}))

EX$E5 <- ggplot(res, aes(d, beta)) +
  geom_hline(yintercept = 0, linetype = 2, colour = "grey60") +
  geom_line(data = data.frame(d = d, beta = beta_true), colour = "grey65", linewidth = 1.3) +
  geom_line(colour = "#2c6fa8", linewidth = .95) +
  facet_wrap(~ lab, ncol = 1) + xm +
  labs(title = "E5. Flexibility and resolution are the same trade-off",
       subtitle = paste0("Grey = truth. Blue = the estimate at three penalty strengths.\n",
                         "A stiffer curve (low edf) is stable but cannot locate a day; a wiggly one (high edf)\n",
                         "chases noise and its best day moves everywhere under resampling. The REML choice sits\n",
                         "between, and the resulting best-day window is the honest resolution of your answer."),
       x = NULL, y = expression(beta(t))) + th

for (nm in names(EX))
  ggsave(file.path("figures/explain", paste0("explain_", nm, ".png")), EX[[nm]],
         width = 9.5, height = if (nm %in% c("E1", "E5")) 7 else 5, dpi = 160)

cat("Wrote", length(EX), "figures to figures/explain/\n\n")
cat(sprintf("In this simulation, where a real signal exists by construction:\n"))
cat(sprintf("  effective df                 %.2f\n", edf))
cat(sprintf("  simultaneous critical value  %.2f  (pointwise uses 1.96)\n", c_sim))
cat(sprintf("  80%% best-day window          %.0f days wide\n", q80[2] - q80[1]))
cat(sprintf("  true best day                %d;  posterior median %d\n\n",
            which.max(beta_true * lever), round(median(best))))
cat("Compare these to your real output in output/tables/best_day_intervals.csv.\n")
cat("If your window is much wider than this one, the record cannot support daily\n")
cat("guidance and the honest deliverable is a seasonal recommendation.\n")
