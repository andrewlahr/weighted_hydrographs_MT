# =============================================================================
# config.R -- every setting and every path for WH_BOR_Trout.
#
# THIS IS THE ONLY FILE YOU EDIT WHEN ADDING A SITE OR MOVING A FOLDER.
# It is plain R, so your editor checks the syntax, autocomplete works, and an
# error points at a line number. It replaces the old config.yml, which had
# none of those properties and whose whitespace rules caused a duplicate-key
# failure that took an hour to find.
#
# Sourced by R/00_config.R, which derives the shorthands and runs the startup
# checks. Nothing here runs an analysis or touches a file.
#
# TWO PARTS:
#   1. CFG      -- a nested list of settings
#   2. functions -- how to build a file path for a given site
#
# The second part is where site-specific quirks live. They are ordinary
# switch() and if() statements, which is what they were in your original code
# and what they should have stayed.
# =============================================================================


# =============================================================================
# 1. SETTINGS
# =============================================================================
CFG <- list(

  # ---- folders. These are the lines that change between machines ------------
  #
  # Relative to the PROJECT ROOT (the folder holding this file). This project
  # lives INSIDE DroughtTrout:
  #
  #   DroughtTrout/
  #   |-- LL/                 <- data, posteriors, imputed flow
  #   |-- Jefferson/
  #   `-- WH_BOR_Trout/       <- you are here, so ".." IS DroughtTrout
  #
  # So the prefix is "../LL/", NOT "../DroughtTrout/LL/" -- the latter would
  # resolve to DroughtTrout/DroughtTrout/LL and silently find nothing.
  #
  # If you ever move this project up one level, change these five lines and the
  # paths inside params_path() at the foot of this file together.
  paths = list(
    data_root     = "../LL/Data",
    posterior_dir = "../LL/JAGS_PVA/ModelFits",
    flow_dir      = "../WeightedHydrograph/BOR_Weighted/imputed_output",
    bor_flow      = "../LL/Data/Madison_Norris_BOR_future_flow_data.rds",
    output        = "output"
  ),

  # ---- which sites to run ---------------------------------------------------
  # Move names from `all` into `active` as you roll the framework out. The
  # scripts already loop, and the among-site synthesis switches itself on once
  # there is more than one site. No code changes needed.
  sites = list(
    active = c("BigHole.Melrose"),
    
    all    = c("Madison.Norris", 'Missouri.Cascade','Missouri.Craig', "BigHole.Melrose", "Beaverhead.FishAndGame","Beaverhead.Hildreth")
    # all    = c("Madison.Norris", "Missouri.Craig",'Missouri.Cascade', "BigHole.Melrose",
    #            "Ruby.Vigilante", "Beaverhead.FishAndGame")
  ),
  

  # ---- which JAGS nodes carry the response ---------------------------------
  posterior = list(
    recruit_node = "R",

    # *** THE ONE THAT MATTERS ***
    # "BAdults" is ADULT BIOMASS in grams, which is what the IPM's own Ricker
    # uses:  lRm = la0 + log(BAdults) - b*BAdults
    # The old WorkingFPCA_robust.R pulled "NAdults" (adult NUMBERS) while its
    # comment said BAdults, so log(R/S) was built against one stock definition
    # and projected with another. Set to "NAdults" ONLY to reproduce that.
    stock_node = "BAdults",

    # If BAdults was not monitored, rebuild it as B3 + B4.
    stock_fallback = c("B3", "B4"),

    # Fallback only. Used when the params CSV for a site cannot be read, which
    # produces a loud warning rather than a silent substitution. Real years come
    # from params_path() / params_filter() below.
    first_year = 1980,

    # Thin to this many posterior draws. The design matrix does not change
    # across draws, so 2000 is ample; more just costs time.
    max_draws = 2000
  ),

  biology = list(
    recruit_lag = 3     # years from spawning to being counted
  ),

  # ---- seasonal windows, on CALENDAR day-of-year (1 = 1 Jan) ----------------
  # PRE-REGISTERED. Fix them now; do not tune them after seeing a result.
  #
  # Calendar quarters, so every window is contiguous and needs no explanation to
  # a non-specialist. Each reads differently depending on the site's flow lag,
  # and both readings are coherent:
  #
  #   window   flow_lag = 3 (spawning year)      flow_lag = 2 (age-0 rearing year)
  #   winter   pre-spawn winter conditions        late incubation
  #   runoff   snowmelt, pre-spawn adult habitat  emergence, fry displacement
  #   summer   adult condition before spawning    first-summer rearing, thermal stress
  #   autumn   SPAWNING and early incubation      first autumn, early overwinter
  windows = list(
    winter = c(1, 90),      # Jan 1  - Mar 31
    runoff = c(91, 181),    # Apr 1  - Jun 30
    summer = c(182, 273),   # Jul 1  - Sep 30
    autumn = c(274, 365)    # Oct 1  - Dec 31
  ),

  fitting = list(
    block_len      = 5,          # years held out per cross-validation fold
    n_permutations = NULL,       # NULL = every circular shift (exact)
    gate_cv_r2     = 0,          # blocked CV R2 must exceed this
    gate_perm_p    = 0.10,       # permutation p must be at or below this
    seed           = 20260729,
    k_beta         = 20,         # spline basis dimension for beta(t)

    # How beta(t) is estimated: "penalized" (smoothness prior) or "fpc"
    # (beta(t) built from the leading modes of variation in the flow itself).
    # See R/fn_fit_beta.R and R/explain/explain_estimator_choice.R.
    estimator          = "fpc",
    compare_estimators = FALSE,   # fit and gate the other arm too. Cheap, and
                                 # agreement across priors is the best evidence
                                 # that a daily peak is real.
    # How many FPCs to keep. Two rules, answering different questions:
    #   "cumulative"  keep going until they JOINTLY reach fpc_target_var%
    #                 -- "can I reconstruct the hydrographs well enough?"
    #   "individual"  keep only components EACH reaching fpc_min_var%
    #                 -- "is this component distinguishable from noise?"
    #   "both"        the stricter of the two
    #
    # Neither looks at the response, so neither fixes the objection that a
    # low-variance flow mode could carry the signal. Run
    # R/diag_fpc_truncation.R to test that empirically for your data.
    fpc_rule       = "both",
    fpc_target_var = 90,         # cumulative %, used by "cumulative" and "both"
    fpc_min_var    = 1,          # individual %, used by "individual" and "both"
    fpc_max        = 10,         # hard cap, whichever rule is in force

    survival_lags = c(0, 1)      # candidate lags for the survival arm
  ),

  sensitivity = list(
    n_sim          = 10000,                 # simulated beta(t) curves
    delta_cfs      = 25,                   # the "add this much water" unit
    volumes_af     = c(200, 1000, 5000),   # leased volumes to schedule
    window_lengths = c(7, 14, 30, 60),     # release durations to consider
    cred_level     = 0.80                  # for the "best day" interval
  ),

  # ---- the season when water can actually be released (script 06b) ----------
  # Month-day. On a calendar axis May-October is a CONTIGUOUS block (day 121-304),
  # so 06b needs no boundary-wrapping logic at all -- one of the several pieces
  # of machinery the calendar axis removed.
  decision_window = list(
    start = "05-01",
    end   = "10-31",
    label = "irrigation and allocation season"
  ),

  production = list(
    block_days = 30,     # width of each perturbation block in the IPM sweep
    n_years    = 40,
    burn_in    = 15,
    n_draws    = 400
  ),

  qc = list(
    min_years = 10      # skip a site with fewer usable recruit-years
  )
)


# =============================================================================
# 2. WHERE EACH SITE'S FILES LIVE
# -----------------------------------------------------------------------------
# Plain functions. To add a site whose files follow the usual convention, do
# nothing -- the defaults handle it. To add one that does not, add a `switch()`
# branch. That is the whole mechanism.
# =============================================================================
BOR_flow_path <- function(site) {
  ss <- gsub(".", "_", site, fixed = TRUE)
  paste0("../WeightedHydrograph/BOR_Weighted/data/",ss,"_BOR_future_flow_data.rds")
}
#' Null-IPM posterior for a site
posterior_path <- function(site) {
  file.path(CFG$paths$posterior_dir,
            paste0(site, "_IndicatorVarSel_NullMod_Apr26_02.rds"))
}

#' Gap-filled daily discharge for a site
flow_path <- function(site) {
  file.path(CFG$paths$flow_dir, paste0(site, "_imputed.csv"))
}

#' JAGS parameter CSV -- the file the calendar years are read from
#'
#' Reproduces the original extraction. `StreamSection` is the site name with the
#' dot removed: Madison.Norris -> MadisonNorris.
params_path <- function(site) {
  ss <- gsub(".", "", site, fixed = TRUE)
  
  switch(site,
         
         "Jefferson.Waterloo" =
           file.path("../Jefferson/JAGS_PVA/ModelOutput/csvs_quadratic",
                     paste0(ss, "_LLallParams_resids.csv")),
         
         # ---- default: every other site -----------------------------------------
         file.path("../LL/JAGS_PVA/ModelOutput/csvs_quadratic",
                   paste0(ss, "allParams_update2026_02.csv"))
  )
}
params_year_name <- "Estimated NAdults"

#' Which rows of the parameter CSV to keep
#'
#' Also reproduces the original: most sites select on the model string,
#' BigHole.Melrose selects on the lag columns instead.
params_filter <- function(site, d) {
  if (site == "BigHole.Melrose") {
    stopifnot(all(c("SummerLag", "WinterLag") %in% names(d)))
    d[d$SummerLag == 2 & d$WinterLag == 2, , drop = FALSE]
  } else {
    stopifnot("model" %in% names(d))
    d[grepl("SUMMERQ|Global", d$model), , drop = FALSE]
  }
}
#' Which rows of the parameter CSV to keep
#'
#' Also reproduces the original: most sites select on the model string,
#' BigHole.Melrose selects on the lag columns instead.
params_filter <- function(site, d) {
  if (site == "BigHole.Melrose") {
    stopifnot(all(c("SummerLag", "WinterLag") %in% names(d)))
    d[d$SummerLag == 2 & d$WinterLag == 2, , drop = FALSE]
  } else {
    stopifnot("model" %in% names(d))
    d[grepl("SUMMERQ|Global", d$model), , drop = FALSE]
  }
}

#' The row label whose Year column carries the annual series
params_year_name <- "Estimated NAdults"


# =============================================================================
# 3. RULE-CURVE ARM  (script R/10_rulecurve.R)
# -----------------------------------------------------------------------------
# A SEPARATE ANALYSIS, and it must stay separate in two specific ways.
#
# 1. IT USES THE FLOW-INFORMED IPM, NOT THE NULL FIT.
#    The rule curve needs b1r, b12r, b1S, b12S -- the IPM's own flow
#    coefficients. The null posterior used everywhere else in this project has
#    no such terms, so pointing this arm at it would zero the flow response and
#    collapse the analysis silently. There is no circularity problem here
#    because this arm is not estimating a flow effect; it is PROPAGATING the
#    one the IPM already fitted.
#
# 2. IT USES ITS OWN STANDARDIZATION.
#    beta(t) integrates DAILY anomaly curves standardized per day-of-year.
#    The rule curve needs the z of the ANNUAL SUMMER MEAN, on exactly the scale
#    the IPM was fitted with -- script 10 verifies it reproduces the IPM's own
#    covariate to 1e-10 and stops if it cannot. Do not unify these; doing so
#    puts la0, b and b1r off-scale and every K is then wrong.
#
# The summer window is already calendar day-of-year, so it needed no change in
# the calendar-axis migration.
CFG$rulecurve <- list(
  summer_doy = c(start = 196, end = 273),   # 15 Jul - 30 Sep

  # Estimator settings. See the notes in R/10_rulecurve.R before changing any.
  zscore_ref   = "observed",   # "observed" matches the IPM | "quantile" = FishCast as-is
  recruit_stat = "mean",       # "mean" = E[R] | "median" = exp(mu), FishCast
  axis_mode    = "NALL",       # "NALL" = 1:1 IS the replacement line
  ssb_mode     = "fishcast",   # set by the STEP 3 scale check, not by taste

  # Clamping truncates scenario z at the training range, which compresses exactly
  # the dry-scenario signal the analysis is trying to measure. FALSE by default;
  # if set TRUE, report the FALSE run alongside it.
  clamp_z = FALSE,

  n_draws = 1000, stock_max = 5000, stock_n = 2001
)

#' FishCast export for a site: covarLagIn1Real, Flows, Weight3/4, Survival, RecLag
rulecurve_export_path <- function(site)
  file.path(CFG$paths$data_root, paste0(site, "_rulecurve_inputs.rds"))

#' Observed daily flow, used to verify the summer window reproduces the IPM's covariate
rulecurve_observed_path <- function(site) {
  ss <- sub("^[^.]*\\.", "", site)              # Madison.Norris -> Norris
  file.path(CFG$paths$data_root, paste0(ss, "_daily_flow.csv"))
}

#' BoR projected daily flow for the rule-curve arm
rulecurve_bor_path <- function(site) {
  ss <- toupper(sub("^[^.]*\\.", "", site))
  file.path(CFG$paths$data_root, paste0(ss, "_BOR_future_flow_data.RDS"))
}


# =============================================================================
# 3. THE FLOW LAG -- SITE-SPECIFIC, FROM THE IPM'S OWN MODEL SELECTION
# -----------------------------------------------------------------------------
# TWO DIFFERENT LAGS, AND THEY ARE NOT THE SAME THING.
#
#   recruit_lag (CFG$biology$recruit_lag = 3, all sites)
#       Biology. Fish spawned in fall of year t-3 are counted at age 2 in year t.
#       Fixed by the life history.
#
#   flow_lag(site)  <- this function
#       Statistics. WHICH YEAR'S HYDROGRAPH the IPM's indicator-variable
#       selection chose as the predictor of recruitment. Selected per site, and
#       it VARIES: Madison.Norris = 3, BigHole.Melrose = 2.
#
# The two lags encode different biological hypotheses:
#   flow_lag = recruit_lag (3)  spawning-year conditions -- adult access to
#                               spawning habitat, redd site selection, and the
#                               incubation that follows
#   flow_lag = recruit_lag - 1  age-0 rearing-year conditions -- emergence
#                               timing, fry displacement, first-summer rearing
#
# Update each site from its `_RecLagInclusionProbQuad.csv` as you roll out. Left
# as an explicit switch() rather than a CSV read so the value used is visible in
# the config rather than recovered at run time.
# A NAMED VECTOR, not a switch(), so every configured site is visible at once and
# membership can be tested -- which is what lets an unconfigured site warn instead
# of silently taking a default.
FLOW_LAG_BY_SITE <- c(
  "Madison.Norris"     = 3L,
  "BigHole.Melrose"    = 2L,
  "Jefferson.Waterloo" = 3L    # PLACEHOLDER -- confirm from the selection CSV
  # Add each site as you roll out, from its _RecLagInclusionProbQuad.csv.
)

flow_lag <- function(site) {
  if (site %in% names(FLOW_LAG_BY_SITE))
    return(unname(FLOW_LAG_BY_SITE[[site]]))

  # LOUD, not silent. The lag genuinely varies between sites (Norris 3,
  # BigHole.Melrose 2), so a wrong default shifts every flow window by a year and
  # still produces entirely plausible coefficients. A site that reaches here has
  # not been configured and its results must not be trusted.
  warning("flow_lag(): '", site, "' is not configured, defaulting to ",
          CFG$biology$recruit_lag, ".\n",
          "  Read the selected lag from that site's _RecLagInclusionProbQuad.csv\n",
          "  and add it to FLOW_LAG_BY_SITE in config.R. Until then, results for\n",
          "  this site assume the spawning-year hypothesis and may be wrong.",
          call. = FALSE)
  as.integer(CFG$biology$recruit_lag)
}

#' Which calendar year's hydrograph predicts a given recruit year
#'
#' On a calendar axis this is exactly the lag the IPM selected -- no conversion,
#' no offset, nothing to get wrong.
#'
#' The earlier water-year version needed a conditional offset, because a calendar
#' year straddles two water years and which one applied depended on whether the
#' mechanism sat in Oct-Dec or Jan-Sep. Worse, it MISALIGNED the analysis with the
#' model selection: at a flow lag of 3, the water year drew only 3 of its 12 months
#' from the calendar year the IPM actually chose, and 9 months from a year it did
#' not. Matching the IPM's own selection is the substantive reason for the calendar
#' axis; being legible to a non-specialist audience is the second reason.
#'
#'   recruit year 2000, flow_lag 3 -> calendar 1997 (the spawning year)
#'   recruit year 2000, flow_lag 2 -> calendar 1998 (the age-0 rearing year)
flow_year <- function(recruit_year, site) {
  as.integer(recruit_year - flow_lag(site))
}


# =============================================================================
# 4. LOCAL OVERRIDES  -- sourced LAST so anything there wins
# -----------------------------------------------------------------------------
# config_local.R holds the site registry, the per-site flow lags, and the
# analysis choices made for this project. It exists so that THIS file can be
# replaced when the method develops without wiping settings that are
# irreplaceable and specific to the project.
#
# If it is missing, the defaults above apply -- which is a single placeholder
# site, and almost certainly not what you want. check_setup.R warns.
# =============================================================================
if (file.exists(here::here("config_local.R"))) {
  source(here::here("config_local.R"))
} else {
  warning("config_local.R not found -- using the shipped defaults, which list ",
          "only ", CFG$sites$active[[1]], ". Your site registry and flow lags ",
          "live in that file.", call. = FALSE)
}