# =============================================================================
# explain_partial_pooling.R
#
# WHAT PARTIAL POOLING DOES, shown on simulated data where the truth is known.
#
# This is the one genuinely new statistical idea in Suggestion 1, so it gets its
# own script. No data needed. Run it and look at the two figures.
#
#     source("R/explain/explain_partial_pooling.R")
#
# THE SITUATION: you have 14 sites. Each has its own flow effect. Each site's
# estimate is noisy, and some sites are much noisier than others (fewer years,
# wider mark-recapture intervals). What is the best estimate for each site?
#
# THREE ANSWERS:
#   1. NO POOLING       -- fit each site alone. Uses only that site's data.
#   2. COMPLETE POOLING -- one number for all sites. Ignores real differences.
#   3. PARTIAL POOLING  -- each site keeps its own estimate, but is pulled toward
#                          the group average by an amount that depends on how
#                          noisy that site is.
#
# Option 3 is the hierarchical model. This script shows that it beats both
# extremes, and shows WHY.
# =============================================================================

suppressPackageStartupMessages({ library(ggplot2); library(dplyr); library(tidyr) })
dir.create("figures/explain", recursive = TRUE, showWarnings = FALSE)
POOL_FIGS <- list()

theme_ex <- theme_classic(base_size = 11) +
  theme(plot.title = element_text(face = "bold", size = 12),
        plot.subtitle = element_text(size = 9.5, colour = "grey35"))

# =============================================================================
# SIMULATE 14 SITES WITH A KNOWN TRUTH
# -----------------------------------------------------------------------------
# The true summer base-flow effect is 0.30 ON AVERAGE across sites, with real
# site-to-site variation of 0.12. Sites differ in how many years they have, so
# they differ in how noisy their individual estimates are.
# =============================================================================

set.seed(7)
n_sites   <- 14
GAMMA     <- 0.30      # true across-site mean effect (what you want to publish)
SIGMA     <- 0.12      # true site-to-site variation
site_name <- sprintf("Site %02d", 1:n_sites)

gamma_true <- rnorm(n_sites, GAMMA, SIGMA)             # each site's TRUE effect
n_years    <- sample(16:44, n_sites, replace = TRUE)   # data availability varies
se_site    <- 0.9 / sqrt(n_years)                      # noisier where fewer years

# What a separate per-site regression would give you:
gamma_hat  <- rnorm(n_sites, gamma_true, se_site)

# --- COMPLETE POOLING: one number, inverse-variance weighted -----------------
w_cp    <- 1 / se_site^2
pooled_all <- sum(w_cp * gamma_hat) / sum(w_cp)

# --- PARTIAL POOLING ---------------------------------------------------------
# The classic shrinkage result. For each site:
#
#     gamma_partial  =  lambda * gamma_hat  +  (1 - lambda) * Gamma
#     lambda         =  sigma^2 / (sigma^2 + se^2)
#
# lambda is the SHRINKAGE WEIGHT. Read it directly:
#   se small (lots of data)  -> lambda near 1 -> keep your own estimate
#   se large (little data)   -> lambda near 0 -> borrow the group average
#
# A full Bayesian fit estimates Gamma and sigma jointly; here we use a simple
# method-of-moments estimate so the arithmetic is visible.
grand      <- sum(w_cp * gamma_hat) / sum(w_cp)
sigma2_hat <- max(0, var(gamma_hat) - mean(se_site^2))   # observed spread minus noise
lambda     <- sigma2_hat / (sigma2_hat + se_site^2)
gamma_pp   <- lambda * gamma_hat + (1 - lambda) * grand

err <- function(x) sqrt(mean((x - gamma_true)^2))
cat(sprintf("Root-mean-square error against the TRUE site effects:\n"))
cat(sprintf("  no pooling       %.4f\n", err(gamma_hat)))
cat(sprintf("  complete pooling %.4f\n", err(rep(pooled_all, n_sites))))
cat(sprintf("  PARTIAL pooling  %.4f   <- best\n\n", err(gamma_pp)))
cat(sprintf("Estimated across-site mean = %.3f (truth %.2f)\n", grand, GAMMA))
cat(sprintf("Estimated site-to-site SD  = %.3f (truth %.2f)\n\n", sqrt(sigma2_hat), SIGMA))


# =============================================================================
# FIGURE P1 — the shrinkage, site by site
# =============================================================================
dp <- data.frame(site = site_name, n_years, se = se_site,
                 truth = gamma_true, no_pool = gamma_hat,
                 partial = gamma_pp, lambda = lambda) %>%
  arrange(n_years) %>% mutate(site = factor(site, levels = site))

POOL_FIGS$p1_shrinkage <- ggplot(dp) +
  geom_hline(aes(yintercept = grand), colour = "#c9a227", linewidth = 1) +
  annotate("text", x = 0.7, y = grand, label = "  group average", hjust = 0,
           vjust = -0.7, colour = "#c9a227", size = 3.2) +
  geom_segment(aes(x = site, xend = site, y = no_pool, yend = partial),
               colour = "grey60", linewidth = 0.5,
               arrow = arrow(length = unit(0.14, "cm"), type = "closed")) +
  geom_point(aes(site, no_pool, colour = "no pooling (site alone)"), size = 2.6) +
  geom_point(aes(site, partial, colour = "partial pooling"), size = 2.6) +
  geom_point(aes(site, truth, colour = "the truth"), shape = 4, size = 3, stroke = 1.1) +
  scale_colour_manual(values = c("no pooling (site alone)" = "#b5462f",
                                 "partial pooling" = "#2c6fa8",
                                 "the truth" = "grey15"), name = NULL) +
  coord_flip() +
  labs(title = "Figure P1. Partial pooling pulls noisy sites toward the group",
       subtitle = paste0("Sites ordered by how many years of data they have (fewest at the bottom).\n",
                         "Arrows show how far each site's estimate moves. Sites with little data move a long way;\n",
                         "sites with lots of data barely move. Blue lands closer to the X marks than red does."),
       x = NULL, y = "summer base-flow effect") +
  theme_ex + theme(legend.position = "bottom")


# =============================================================================
# FIGURE P2 — the shrinkage weight, and why it is not arbitrary
# =============================================================================
POOL_FIGS$p2_weight <- ggplot(dp, aes(n_years, lambda)) +
  geom_line(colour = "grey65", linewidth = 0.6) +
  geom_point(size = 3, colour = "#2c6fa8") +
  geom_hline(yintercept = c(0, 1), linetype = 3, colour = "grey60") +
  annotate("text", x = max(dp$n_years), y = 0.97, hjust = 1,
           label = "lambda = 1: keep your own estimate entirely", size = 3.2, colour = "grey30") +
  annotate("text", x = min(dp$n_years), y = 0.03, hjust = 0,
           label = "lambda = 0: use the group average entirely", size = 3.2, colour = "grey30") +
  scale_y_continuous(limits = c(0, 1)) +
  labs(title = "Figure P2. How much each site keeps of its own estimate",
       subtitle = expression(paste("shrinkage weight  ", lambda, " = ", sigma^2, " / (", sigma^2, " + SE"^2, ")   -- the data set this, not the analyst")),
       x = "years of data at that site", y = expression(lambda)) +
  theme_ex

# THE POINT: no one chooses how much to pool. sigma is ESTIMATED. If the sites
# genuinely differ, sigma comes out large, lambda goes to 1, and partial pooling
# reduces to no pooling. If they don't differ, sigma goes to 0 and it reduces to
# complete pooling. The method cannot force a conclusion.

for (nm in names(POOL_FIGS))
  ggsave(file.path("figures/explain", paste0(nm, ".png")), POOL_FIGS[[nm]],
         width = 9, height = if (nm == "p1_shrinkage") 6.2 else 4.4, dpi = 160)

cat("Wrote", length(POOL_FIGS), "figures to figures/explain/\n\n")
cat("WHY THIS MATTERS FOR YOUR MANUSCRIPT:\n")
cat("Testing 14 sites separately at alpha = 0.05 gives you roughly one significant\n")
cat("result by chance even if flow does nothing anywhere. Reporting the sites that\n")
cat("came out significant is a selection problem a reviewer will find. The\n")
cat("hierarchical model has no selection step: it reports the across-site effect\n")
cat("AND every site's estimate, all from one fit.\n")
