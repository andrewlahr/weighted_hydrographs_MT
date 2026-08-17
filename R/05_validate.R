# =============================================================================
# 05_validate.R  --  THE GATE, for both curves and both model forms.
#
#   in : output/models/beta_recruitment.rds, output/models/beta_survival.rds
#   out: output/models/gate.rds, output/tables/gate.csv, figures
#
# FOUR THINGS ARE TESTED, in increasing order of how much they matter:
#
#   1. In-sample R2            -- reported, NOT evidence. Any model fits its own data.
#   2. Leave-one-year-out R2   -- reported so you can SEE how much it flatters.
#   3. Blocked CV R2           -- the honest number. 5-year contiguous holdouts.
#   4. Permutation null        -- how good would this look by luck?
#
# WHY BLOCKED, NOT LEAVE-ONE-OUT. Flow is autocorrelated: drop one year and its
# neighbours stay in the training set looking almost identical, so the model
# interpolates rather than predicts. That is exactly how a functional model with
# 365 columns manufactures apparent skill.
#
# WHY A PERMUTATION NULL. The sampling distribution of cross-validated R2 under
# the null is neither centred at zero nor symmetric at n = 40. Sliding the
# response forward against flow and wrapping around preserves the autocorrelation
# of both series and breaks only their alignment. Shuffling randomly would destroy
# the autocorrelation and give p-values that are far too small.
#
# BOTH MODEL FORMS ARE GATED:
#   seasonal (4 df)   -- the powered confirmatory test: does flow matter at all?
#   beta(t) (3-15 df) -- can we resolve WHEN?
#
# The four possible outcomes all mean something:
#   both pass         -> report beta(t) with confidence
#   seasonal only     -> "flow matters, we cannot resolve when". Still useful:
#                        tells managers a season, not a week.
#   beta(t) only      -> unusual; treat with suspicion and check for overfitting
#   neither           -> report the null. It is publishable.
#
# Run:  source("R/00_config.R"); source("R/05_validate.R")
# =============================================================================

source(here::here("R", "00_config.R"))
source(here::here("R", "fn_fit_beta.R"))
suppressPackageStartupMessages({ library(tidyr); library(purrr) })

BR <- readRDS(file.path(OUT, "models", "beta_recruitment.rds"))
BS <- if (file.exists(file.path(OUT, "models", "beta_survival.rds")))
        readRDS(file.path(OUT, "models", "beta_survival.rds")) else NULL
BL <- CFG$fitting$block_len
K  <- BR$k_beta

r2 <- function(o, p) 1 - sum((o - p)^2) / sum((o - mean(o))^2)

# ONE custom function: cross-validate one model form on one response.
# `form` is either "beta" (functional) or "seasonal".
cv_one <- function(y, Curves, Win, stock_z = NULL, form, sp, block_len = BL,
                   est = ESTIMATOR) {
  n <- length(y); pred <- rep(NA_real_, n)

  # ---------------------------------------------------------------------------
  # WHY THIS GUARD EXISTS. Survival has no stock covariate -- density is already
  # removed when the process deviate is built -- so the caller used to pass a
  # column of zeros. A constant column is rank deficient: lm() returns an NA
  # coefficient for it, NA * 0 is NA in R, and that NA propagates into EVERY
  # prediction. All folds come back NA, is.finite() is all FALSE, and r2() is
  # handed two empty vectors and returns NaN. Nothing errors; the whole survival
  # arm just silently scores NaN.
  #
  # The fix is to drop the term rather than zero it.
  # ---------------------------------------------------------------------------
  use_stock <- !is.null(stock_z) && length(stock_z) == n &&
               is.finite(stats::sd(stock_z)) && stats::sd(stock_z) > 1e-10

  # An fpc fit returns sp = NA_real_. Handing that to gam() for the penalized
  # comparison arm is undefined; NULL means "estimate it", which is what we want.
  sp_use <- if (is.null(sp) || !is.finite(sp)) NULL else sp

  for (st in seq(1, n, by = block_len)) {
    te <- st:min(st + block_len - 1L, n); tr <- setdiff(seq_len(n), te)

    if (form == "beta") {
      # NOTE for the fpc arm: K is re-selected from the TRAINING years inside
      # every fold, so the fold scores the whole procedure including selection.
      # Fixing K once on the full record and reusing it here would leak.
      ex <- if (use_stock) cbind(S_z = stock_z[tr]) else NULL
      f <- try(fit_beta_curve(y[tr], Curves[tr, , drop = FALSE], k = K, sp = sp_use,
                              extra = ex, estimator = est,
                              fpc_rule = FPC_RULE, fpc_target_var = FPC_VAR,
                        fpc_min_var = FPC_MIN, fpc_max = FPC_MAX), silent = TRUE)
      if (inherits(f, "try-error")) next

      cf <- coef(f$model)
      cf[!is.finite(cf)] <- 0          # belt and braces against any other alias
      lin <- rep(unname(cf[["(Intercept)"]]), length(te))
      if (use_stock) lin <- lin + cf[["S_z"]] * stock_z[te]
      pred[te] <- lin + as.numeric(Curves[te, , drop = FALSE] %*% f$beta)

    } else {
      # standardization refit INSIDE the fold: computing it on all years is a
      # small but real leak, and it is the leak that inflates functional models
      ctr <- colMeans(Win[tr, , drop = FALSE]); scl <- apply(Win[tr, , drop = FALSE], 2, sd)
      if (any(!is.finite(scl)) || any(scl < 1e-10)) next
      Ztr <- sweep(sweep(Win[tr, , drop = FALSE], 2, ctr, "-"), 2, scl, "/")
      Zte <- sweep(sweep(Win[te, , drop = FALSE], 2, ctr, "-"), 2, scl, "/")

      Dtr <- if (use_stock) cbind(1, stock_z[tr], Ztr) else cbind(1, Ztr)
      Dte <- if (use_stock) cbind(1, stock_z[te], Zte) else cbind(1, Zte)
      fit <- lm.fit(Dtr, y[tr])
      cf  <- fit$coefficients; cf[!is.finite(cf)] <- 0
      pred[te] <- as.numeric(Dte %*% cf)
    }
  }

  ok <- is.finite(pred)
  # Do not return NaN silently. A fold set that produced nothing is a bug
  # upstream, and it should say so rather than propagate into the gate table.
  if (!any(ok)) {
    warning(sprintf("cv_one(): no fold produced a finite prediction (form = %s, est = %s).",
                    form, if (is.na(est)) "seasonal" else est), call. = FALSE)
    return(list(r2 = NA_real_, pred = pred, n_scored = 0L))
  }
  if (sum(ok) < 0.5 * n)
    warning(sprintf("cv_one(): only %d of %d years scored (form = %s).",
                    sum(ok), n, form), call. = FALSE)

  list(r2 = r2(y[ok], pred[ok]), pred = pred, n_scored = sum(ok))
}

rows <- list(); nulls <- list(); resol <- list()

# =============================================================================
# LOOP OVER PROCESSES AND SITES
# =============================================================================
jobs <- list()
for (s in names(BR$fits)) jobs[[length(jobs) + 1]] <- list(process = "recruitment", site = s)
if (!is.null(BS)) for (s in names(BS$fits)) jobs[[length(jobs) + 1]] <- list(process = "survival", site = s)

for (J in jobs) {

  f <- if (J$process == "recruitment") BR$fits[[J$site]] else BS$fits[[J$site]]
  y  <- if (J$process == "recruitment") colMeans(f$Y) else colMeans(f$E)
  Cu <- f$Curves
  # survival has no stock covariate (density is already removed from the deviate)
  # NULL, not zeros: see the guard at the top of cv_one(). Passing a constant
  # column silently NaNs the entire survival arm.
  sz <- if (J$process == "recruitment") f$stock_z else NULL
  Wn <- if (J$process == "recruitment") f$Win else
    vapply(WINDOWS, function(w) rowMeans(Cu[, w[1]:w[2], drop = FALSE]), numeric(nrow(Cu)))
  n  <- length(y)

  message("\n== ", J$process, " | ", J$site, " (", n, " years) ==")

  # Which arms to score. The primary beta estimator always runs; the other one
  # runs too when compare_estimators is on, because agreement between two
  # different priors is the strongest available evidence that a daily peak is in
  # the data rather than in the estimator.
  arms <- list(list(form = "beta", est = ESTIMATOR),
               list(form = "seasonal", est = NA_character_))
  if (COMPARE) {
    other <- setdiff(c("penalized", "fpc"), ESTIMATOR)
    arms <- append(arms, list(list(form = "beta", est = other)), after = 1L)
  }

  for (arm in arms) {
    form <- arm$form; est <- arm$est
    label <- if (form == "seasonal") "seasonal" else paste0("beta:", est)

    cvb <- cv_one(y, Cu, Wn, sz, form, sp = f$sp, est = est)
    loo <- cv_one(y, Cu, Wn, sz, form, sp = f$sp, block_len = 1L, est = est)

    # permutation null: circular shift
    shifts <- seq_len(n - 1L)
    if (!is.null(CFG$fitting$n_permutations) && CFG$fitting$n_permutations < length(shifts))
      shifts <- round(seq(1, n - 1L, length.out = CFG$fitting$n_permutations))
    nr <- vapply(shifts, function(k) {
      ord <- c((k + 1):n, 1:k)
      tryCatch(suppressWarnings(cv_one(y[ord], Cu, Wn, sz, form, sp = f$sp, est = est)$r2),
               error = function(e) NA_real_)
    }, numeric(1))
    nr <- nr[is.finite(nr)]
    pv <- (1 + sum(nr >= cvb$r2)) / (1 + length(nr))

    # Any field that is absent from the fit object arrives as NULL, which has
    # length 0, and data.frame() then fails with the unhelpful message
    # "arguments imply differing number of rows: 1, 0" without naming the
    # culprit. .one() converts a missing or wrong-length field into NA and says
    # which one it was.
    .one <- function(x, what) {
      if (is.null(x) || length(x) != 1L) {
        warning(sprintf("field '%s' was %s for %s/%s -- recorded as NA. ",
                        what, if (is.null(x)) "NULL" else paste0("length ", length(x)),
                        J$process, J$site),
                "Re-run the script that builds that fit object.", call. = FALSE)
        return(NA_real_)
      }
      as.numeric(x)
    }

    rows[[length(rows) + 1]] <- data.frame(
      process = J$process, site = J$site, form = label,
      estimator = if (is.null(est) || !length(est)) NA_character_ else as.character(est),
      n_years = n,
      edf = if (form == "beta") .one(f$edf, "edf") else 4,
      r2_insample = if (form == "beta") .one(f$r2_insample, "r2_insample") else NA_real_,
      r2_loo = .one(loo$r2, "r2_loo"),
      r2_blocked = .one(cvb$r2, "r2_blocked"),
      p_value = pv,
      finest_p = 1 / (1 + length(nr)),
      passes = isTRUE(cvb$r2 > CFG$fitting$gate_cv_r2 && pv <= CFG$fitting$gate_perm_p),
      stringsAsFactors = FALSE)
    # THIS is where the failure actually surfaced. If every permutation replicate
    # returned NaN, nr is filtered to numeric(0), and data.frame() with a
    # zero-length column against length-1 columns throws
    #   "arguments imply differing number of rows: 1, 0"
    # -- naming the data.frame call but not the empty column, which is why the
    # message was so hard to read. The root cause was upstream in cv_one().
    if (length(nr)) {
      nulls[[length(nulls) + 1]] <- data.frame(process = J$process, site = J$site,
                                               form = label, null_r2 = nr)
    } else {
      warning(sprintf("no permutation replicate scored for %s/%s/%s -- null distribution empty.",
                      J$process, J$site, label), call. = FALSE)
    }
    message(sprintf("  %-16s blocked R2 = %+.3f   LOO = %+.3f   p = %.3f   %s",
                    label, cvb$r2, loo$r2, pv, ifelse(tail(rows, 1)[[1]]$passes, "PASS", "fail")))
  }

  # ===========================================================================
  # THE RESOLUTION DIAGNOSTIC
  # ---------------------------------------------------------------------------
  # A penalized spline with `edf` effective degrees of freedom over 365 days
  # carries roughly 365/edf days of resolution. With edf = 4 that is ~90 days --
  # you cannot read a date off such a curve, no matter how sharp its peak looks.
  #
  # This is a HEURISTIC. Script 06 measures the resolution properly, by
  # simulating the curve and asking how much the location of the best day moves.
  # Report that, not this. This is here so the number is visible early.
  # ===========================================================================
  resol[[length(resol) + 1]] <- data.frame(
    process = J$process, site = J$site, edf = f$edf,
    heuristic_resolution_days = 365 / max(f$edf, 1))
  message(sprintf("  edf = %.2f  ->  heuristic resolution ~%.0f days (script 06 measures it properly)",
                  f$edf, 365 / max(f$edf, 1)))
}

gate  <- bind_rows(rows)
nulls <- bind_rows(nulls)
resol <- bind_rows(resol)


# =============================================================================
# THE VERDICT
# =============================================================================
message("\n", strrep("=", 68))
for (pr in unique(gate$process)) for (st in unique(gate$site[gate$process == pr])) {
  g <- gate %>% filter(process == pr, site == st)
  pb <- g$passes[grepl("^beta", g$form)]; ps <- g$passes[g$form == "seasonal"]
  message(sprintf("  %s | %s", pr, st))
  if (isTRUE(ps) && isTRUE(pb)) {
    message("     BOTH PASS. Report beta(t) with confidence; use script 06 for timing.")
  } else if (isTRUE(ps) && !isTRUE(pb)) {
    message("     SEASONAL PASSES, beta(t) DOES NOT.")
    message("     Flow matters, but the timing cannot be resolved at daily scale.")
    message("     That is a real, reportable finding: advise a SEASON, not a week.")
  } else if (!isTRUE(ps) && isTRUE(pb)) {
    message("     beta(t) PASSES but the 4-parameter seasonal model does not.")
    message("     Treat with suspicion -- a more flexible model beating a simpler one")
    message("     out of sample is possible but uncommon. Check for a leak in the folds.")
  } else {
    message("     NEITHER PASSES. Report the null.")
    message("     The curves in scripts 03/04 are correct arithmetic on a relationship")
    message("     that is not detectable in this record. Do not project from them.")
  }
}
message(strrep("=", 68))


# =============================================================================
# FIGURES
# =============================================================================
f5a <- gate %>%
  select(process, site, form, `in-sample` = r2_insample,
         `leave-one-out` = r2_loo, `blocked` = r2_blocked) %>%
  pivot_longer(-c(process, site, form), names_to = "test", values_to = "r2") %>%
  filter(!is.na(r2)) %>%
  mutate(test = factor(test, levels = c("in-sample", "leave-one-out", "blocked"))) %>%
  ggplot(aes(test, r2, colour = form, group = interaction(site, form))) +
  geom_hline(yintercept = 0, linetype = 2, colour = PAL[["red"]]) +
  geom_line(alpha = .6) + geom_point(size = 3) +
  scale_colour_manual(values = c(beta = PAL[["blue"]], seasonal = PAL[["gold"]]), name = NULL) +
  facet_grid(process ~ site) +
  labs(title = "Figure 5a. The same data, judged three ways",
       subtitle = paste0("Each test left to right is harder and more honest. Below the red line the model is worse\n",
                         "than predicting the long-run average. The drop from left to right is the optimism you\n",
                         "would otherwise have published."),
       x = NULL, y = "R-squared") + theme_wh + theme(legend.position = "bottom")

f5b <- ggplot(nulls, aes(null_r2, fill = form)) +
  geom_histogram(bins = 20, alpha = .6, colour = "white", position = "identity") +
  geom_vline(data = gate, aes(xintercept = r2_blocked, colour = form), linewidth = 1) +
  scale_fill_manual(values = c(beta = PAL[["blue"]], seasonal = PAL[["gold"]]), name = NULL) +
  scale_colour_manual(values = c(beta = PAL[["blue"]], seasonal = PAL[["gold"]]), guide = "none") +
  facet_grid(process ~ site, scales = "free") +
  labs(title = "Figure 5b. Permutation nulls",
       subtitle = paste0("Histograms = scores from deliberately mismatched alignments. Vertical lines = the real one.\n",
                         "The nulls are NOT centred on zero. That is why a positive cross-validated R-squared is not,\n",
                         "on its own, evidence of anything."),
       x = "blocked-CV R-squared under a shifted alignment", y = "count") +
  theme_wh + theme(legend.position = "bottom")

f5c <- ggplot(resol, aes(edf, heuristic_resolution_days, colour = process)) +
  geom_point(size = 4) +
  geom_text(aes(label = site), hjust = -0.12, size = 3, show.legend = FALSE) +
  scale_colour_manual(values = c(recruitment = PAL[["blue"]], survival = PAL[["green"]]),
                      name = NULL) +
  scale_x_continuous(expand = expansion(mult = .25)) +
  labs(title = "Figure 5c. How finely can you speak?",
       subtitle = paste0("Effective degrees of freedom against the implied resolution (365/edf days).\n",
                         "edf near 3 means the curve is nearly a straight line and 'the best day' is meaningless.\n",
                         "This is a heuristic -- script 06 measures resolution directly by simulation."),
       x = "effective degrees of freedom", y = "implied resolution (days)") +
  theme_wh + theme(legend.position = "bottom")

for (nm in c("f5a", "f5b", "f5c"))
  ggsave(file.path(OUT, "figures", paste0("05_", nm, ".png")), get(nm),
         width = 9.5, height = 5.2, dpi = 150)

saveRDS(list(gate = gate, nulls = nulls, resolution = resol, block_len = BL,
             run = Sys.time()), file.path(OUT, "models", "gate.rds"))
write.csv(gate, file.path(OUT, "tables", "gate.csv"), row.names = FALSE)
message("\n  wrote output/models/gate.rds and output/tables/gate.csv\n")
