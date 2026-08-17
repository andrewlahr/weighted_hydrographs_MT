# =============================================================================
# fn_fit_beta.R -- the only two custom fitting functions in the pipeline.
#
# Kept in one small file because scripts 03 (recruitment) and 04 (survival) both
# need them, and duplicating them would guarantee they drift apart.
#
# Sourced by 03, 04 and 05. Contains no analysis and runs nothing on source().
#
# TWO ESTIMATORS FOR beta(t), ONE RETURN STRUCTURE
# ------------------------------------------------
# You cannot estimate 365 numbers from ~40 annual observations without a
# constraint. These are two different constraints, and at this sample size the
# constraint does much of the work. Neither is correct a priori.
#
#   estimator = "penalized"  beta(t) must be SMOOTH. B-spline basis, second-
#                            difference roughness penalty, sp chosen by REML.
#
#   estimator = "fpc"        beta(t) must lie in the span of the leading modes of
#                            variation in the FLOW itself. FPCA on the
#                            hydrographs, keep the top K, regress on the scores,
#                            transform back. This is the old 'fpc' option.
#
# WHICH TO BELIEVE: run both. If they put the peak in the same place, the answer
# is robust to the prior and you can report it. If they disagree, the
# disagreement IS the result -- the daily structure is being supplied by the
# estimator rather than by the data, and no daily recommendation is defensible.
# =============================================================================

suppressPackageStartupMessages(library(mgcv))

# =============================================================================
# DISPATCHER -- everything downstream calls this, never the two fitters directly.
# =============================================================================
#' Fit beta(t) and return the curve WITH its full 365 x 365 covariance
#'
#' @param y          length-n response
#' @param Curves     [n x 365] standardized daily anomalies, water-year axis
#' @param estimator  "penalized" or "fpc"
#' @param k,sp       basis dimension and smoothing parameter (penalized only)
#' @param fpc_rule   how components are chosen (fpc only):
#'   "cumulative"  keep components until they JOINTLY reach fpc_target_var%
#'   "individual"  keep components that EACH reach fpc_min_var% on their own
#'   "both"        the stricter of the two
#' @param fpc_target_var  cumulative % of flow variance (used by "cumulative"/"both")
#' @param fpc_min_var     individual % of flow variance (used by "individual"/"both")
#' @param fpc_max         hard cap on the number of components
#' @param extra      optional matrix of scalar covariates (e.g. stock)
#'
#' The full covariance is not a luxury. Script 06 simulates curves from it to get
#' best-day intervals, and adjacent days are strongly correlated, so the
#' off-diagonals carry most of the information about whether a peak is real.
fit_beta_curve <- function(y, Curves, estimator = c("penalized", "fpc"),
                           k = 20L, sp = NULL,
                           fpc_rule = "cumulative", fpc_target_var = 90,
                           fpc_min_var = 0, fpc_max = 10L, extra = NULL) {
  estimator <- match.arg(estimator)
  if (estimator == "penalized")
    .fit_beta_penalized(y, Curves, k = k, sp = sp, extra = extra)
  else
    .fit_beta_fpc(y, Curves, rule = fpc_rule, target_var = fpc_target_var,
                  min_var = fpc_min_var, k_max = fpc_max, extra = extra)
}


#' Fit beta(t) once and return the curve WITH its full covariance
#'
#' @param y       length-n response
#' @param Curves  [n x 365] standardized daily anomalies, water-year axis
#' @param k       spline basis dimension (upper bound on flexibility)
#' @param sp      smoothing parameter. NULL = estimate by REML.
#' @param extra   optional matrix of scalar covariates (e.g. stock)
#' @return list(beta [365], Vbeta [365x365], edf, sp, scale, r2, model)
#'
#' HOW IT WORKS. mgcv's summation convention: with L and X both [n x 365]
#' matrices, s(L, by = X) computes SUM_j f(L[i,j]) * X[i,j], which is exactly
#' SUM_t beta(t) x_i(t) with one-day quadrature weights. Wood (2017) GAMs 2nd
#' ed., section 7.10.
#'
#' To recover beta(t) at every day WITH covariances between days, predict on a
#' design whose row t carries a signal that is 1 on day t and 0 elsewhere -- i.e.
#' an identity matrix. The smooth's contribution to row t is then beta(t), and
#' Lp %*% V %*% t(Lp) is the full 365 x 365 covariance. The pointwise standard
#' errors are its diagonal; everything in script 06 needs the off-diagonals.
.fit_beta_penalized <- function(y, Curves, k = 20L, sp = NULL, extra = NULL) {
  n <- length(y)
  stopifnot(nrow(Curves) == n, ncol(Curves) == 365L)

  L   <- matrix(1:365, n, 365, byrow = TRUE)
  dat <- list(y = y, L = L, X = Curves)
  rhs <- "s(L, by = X, bs = 'ps', k = k)"
  if (!is.null(extra)) {
    ex  <- as.data.frame(extra)
    dat <- c(dat, as.list(ex))
    rhs <- paste(rhs, "+", paste(names(ex), collapse = " + "))
  }

  m <- mgcv::gam(as.formula(paste("y ~", rhs)), data = dat, method = "REML", sp = sp)

  nd <- list(L = matrix(1:365, 365, 365, byrow = TRUE), X = diag(365))
  if (!is.null(extra))
    nd <- c(nd, lapply(as.data.frame(extra), function(v) rep(0, 365)))
  Lp <- predict(m, newdata = nd, type = "lpmatrix")

  ii <- m$smooth[[1]]$first.para:m$smooth[[1]]$last.para
  Lp <- Lp[, ii, drop = FALSE]

  list(beta   = as.numeric(Lp %*% coef(m)[ii]),
       Vbeta  = Lp %*% vcov(m)[ii, ii, drop = FALSE] %*% t(Lp),
       edf    = sum(m$edf[ii]),
       sp     = m$sp[1],
       scale  = m$scale,
       fitted = as.numeric(fitted(m)),
       r2     = 1 - sum(residuals(m)^2) / sum((y - mean(y))^2),
       estimator = "penalized",
       n_basis   = length(ii),
       model  = m)
}


# =============================================================================
# 2. FUNCTIONAL PRINCIPAL COMPONENTS  (the old 'fpc' option)
# -----------------------------------------------------------------------------
#   1. FPCA on the hydrograph curves -> eigenfunctions phi_1(t), phi_2(t), ...
#      and one score per year per component.
#   2. Regress y on the first K scores by ordinary least squares.
#   3. Transform back:  beta(t) = SUM_k b_k phi_k(t).
#
# THREE THINGS TO KNOW BEFORE TRUSTING IT
#
# (a) TRUNCATION SELECTS ON THE WRONG CRITERION. Components are ranked by how
#     much the FLOW varies in them, then tested against RECRUITMENT. Those are
#     different questions. A mode with little flow variance can still be the one
#     fish respond to, and truncation does not shrink it -- it DELETES it. This
#     is the standard objection to principal component regression
#     (Jolliffe 1982, Applied Statistics 31:300-303).
#
# (b) THE COVARIANCE CONDITIONS ON K. Vbeta has rank K, not 365, so simulated
#     curves can only take shapes the retained eigenfunctions can make.
#     Truncation uncertainty is absent, so best-day intervals from this estimator
#     are TOO NARROW. Do not read an FPC best-day interval as calibrated.
#
# (c) EIGENFUNCTIONS ARE GLOBAL, NOT LOCAL. phi_2 and beyond oscillate across the
#     whole year, so beta(t) inherits wiggles everywhere -- including seasons
#     with no biological reason for structure. For a DAILY release
#     recommendation this matters: an apparent optimum can sit on an
#     eigenfunction artefact rather than on signal.
#     See R/explain/explain_estimator_choice.R.
#
# K IS RE-SELECTED FROM WHATEVER DATA IS PASSED IN. Deliberate: called inside a
# cross-validation fold it re-selects from the training years only, so the fold
# measures the whole procedure including selection. Choosing K once on the full
# record and reusing it inside folds leaks and inflates apparent skill -- which
# is one explanation for the old pipeline's fpc arm scoring cv_R2 = +0.126 under
# leave-one-out and collapsing under blocked CV.
# =============================================================================
.fit_beta_fpc <- function(y, Curves, rule = c("cumulative", "individual", "both"),
                          target_var = 90, min_var = 5, k_max = 10L, extra = NULL) {
  # y<-y_bar
  # rule<-'both'
  # rule <- match.arg(rule)
  n <- length(y)
  stopifnot(nrow(Curves) == n, ncol(Curves) == 365L)

  pc      <- stats::prcomp(Curves, center = TRUE, scale. = FALSE)
  varprop <- pc$sdev^2 / sum(pc$sdev^2)
  cumv    <- cumsum(varprop) * 100

  # ---------------------------------------------------------------------------
  # HOW MANY COMPONENTS TO KEEP -- two rules, and they answer different questions.
  #
  #   "cumulative"  keep going until the retained set JOINTLY explains
  #                 target_var% of flow variation. Asks: "can I reconstruct the
  #                 hydrographs well enough?"
  #
  #   "individual"  keep only components that EACH explain at least min_var% on
  #                 their own. Asks: "is this component big enough to be
  #                 distinguishable from noise?" -- a scree/Kaiser-type
  #                 criterion. Because prcomp sorts eigenvalues descending, the
  #                 retained set is still contiguous (PC1..PCk, no gaps).
  #
  #   "both"        the stricter of the two.
  #
  # NEITHER RULE LOOKS AT THE RESPONSE. Components are ranked by variance in the
  # PREDICTOR and then tested against recruitment, so a low-variance flow mode
  # carrying real signal is deleted before it is ever tested (Jolliffe 1982,
  # Applied Statistics 31:300-303). Changing the threshold swaps one arbitrary
  # number for another; it does not address that. R/diag_fpc_truncation.R tests
  # it empirically for YOUR data.
  #
  # SCALE NOTE for min_var: with 365 days, an equal spread of variance would give
  # every component 1/365 = 0.27%. Hydrographs are so autocorrelated that the
  # effective dimension is more like 15-25, putting the mean eigenvalue near
  # 4-7%. So min_var = 5 is roughly a Kaiser criterion in effective-dimension
  # terms -- which is the defensible way to describe it in Methods.
  # ---------------------------------------------------------------------------
  K_cum <- if (any(cumv >= target_var)) which(cumv >= target_var)[1] else length(cumv)
  K_ind <- sum(varprop * 100 >= min_var)

  K_rule <- switch(rule,
                   cumulative = K_cum,
                   individual = K_ind,
                   both       = min(K_cum, K_ind))

  n_extra <- if (is.null(extra)) 0L else ncol(as.data.frame(extra))
  K <- min(K_rule, k_max, ncol(pc$rotation), n - n_extra - 2L)

  if (K < 1L) {
    if (rule != "cumulative" && K_ind < 1L)
      stop("No component explains at least ", min_var, "% of flow variance on its ",
           "own (the largest is ", sprintf("%.1f%%", 100 * varprop[1]),
           "). Lower fitting$fpc_min_var in config.R.")
    stop("Not enough years to retain even one component.")
  }

  # A threshold rule creates a discontinuity: a component sitting near the line
  # can drop in and out between cross-validation folds, which makes CV noisier
  # than it looks. Flag it so the instability is visible rather than inferred.
  near <- abs(varprop * 100 - min_var) < 0.5
  if (rule != "cumulative" && any(near[seq_len(min(K + 1L, length(near)))]))
    attr(K, "unstable") <- TRUE

  Z <- pc$x[, seq_len(K), drop = FALSE]
  colnames(Z) <- paste0("fpc", seq_len(K))

  d <- data.frame(y = y, Z, check.names = FALSE)
  if (!is.null(extra)) d <- cbind(d, as.data.frame(extra))
  m <- stats::lm(y ~ ., data = d)

  m_sum<-summary(m)
  m_coef<-m_sum$coefficients
  good_coef<-names(which(m_coef[,4]<0.1))[-1]
  
  d2<-d[which(colnames(d)%in%c(good_coef,'y'))]
  m2 <- stats::lm(y ~ ., data = d2)
  summary(m2)
  ii  <- match(colnames(Z), names(stats::coef(m)))
  Phi <- pc$rotation[, seq_len(K), drop = FALSE]        # [365 x K] eigenfunctions
  b   <- stats::coef(m)[ii]
  Vb  <- stats::vcov(m)[ii, ii, drop = FALSE]

  if (anyNA(b)) {                                        # rank-deficient drop
    ok  <- !is.na(b)
    Phi <- Phi[, ok, drop = FALSE]; b <- b[ok]
    Vb  <- Vb[ok, ok, drop = FALSE]; K <- sum(ok)
  }

  list(beta      = as.numeric(Phi %*% b),
       Vbeta     = Phi %*% Vb %*% t(Phi),                # rank K -- see note (b)
       edf       = as.numeric(K),                        # exact, not effective
       sp        = NA_real_,
       scale     = summary(m)$sigma^2,
       fitted    = as.numeric(stats::fitted(m)),
       r2        = summary(m)$r.squared,
       estimator = "fpc",
       n_fpc     = K,
       var_explained = cumv[K],
       var_individual = varprop[seq_len(K)] * 100,
       fpc_rule  = rule,
       K_cumulative = K_cum, K_individual = K_ind,
       K_capped  = K < K_rule,          # TRUE when k_max or n bound instead
       K_unstable = isTRUE(attr(K, "unstable")),
       eigenfun  = Phi,
       scores    = Z,
       model     = m)
}


#' The seasonal confirmatory anchor: four pre-registered windows, plain OLS
#'
#' Four degrees of freedom instead of 3-15, no basis choice, no smoothing
#' parameter. Its job is the powered test of whether flow matters at all;
#' beta(t) then says when.
fit_seasonal <- function(y, Win, stock_z, zwin = paste0("z_", colnames(Win))) {
  d <- as.data.frame(scale(Win)); names(d) <- zwin
  d$S_z <- stock_z; d$y <- y
  m <- lm(as.formula(paste("y ~ S_z +", paste(zwin, collapse = " + "))), data = d)
  list(coef = coef(m), se = summary(m)$coefficients[, 2], r2 = summary(m)$r.squared,
       center = colMeans(Win), scale = apply(Win, 2, sd), model = m)
}


# =============================================================================
# 4. SIMULATING beta(t) FROM ITS FULL UNCERTAINTY
# -----------------------------------------------------------------------------
# Used by scripts 06 and 06b. Combines the TWO sources of uncertainty:
#   between draws -- resample a posterior draw of the response (abundance)
#   within a draw -- add a multivariate normal deviate with covariance Vbeta
# The result is a set of plausible whole curves, which is what any statement
# about WHERE the curve peaks has to be built from. Adjacent days are strongly
# correlated, so the off-diagonals of Vbeta carry most of that information --
# simulating pointwise would give badly wrong answers about location.
# =============================================================================
simulate_beta <- function(f, n_sim = 4000L) {
  M <- nrow(f$beta_draws)
  # Cholesky of the within-draw covariance, done once. The fallback guards the
  # numerically singular case a heavily penalized (or rank-K fpc) fit produces.
  Lc <- tryCatch(chol(f$Vbeta),
                 error = function(e)
                   chol(f$Vbeta + diag(1e-10 * mean(diag(f$Vbeta)), 365)))
  ms  <- sample.int(M, n_sim, replace = TRUE)            # abundance uncertainty
  Z   <- matrix(rnorm(n_sim * 365), n_sim, 365)
  scl <- sqrt(f$scale_draws[ms] / f$scale_ref)           # per-draw variance rescale
  f$beta_draws[ms, , drop = FALSE] + (Z %*% Lc) * scl    # [n_sim x 365]
}
