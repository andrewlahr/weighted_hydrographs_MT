# =============================================================================
# config_local.R -- YOUR settings. Nothing I send will ever overwrite this file.
#
# WHY THIS FILE EXISTS
# --------------------
# config.R mixes two kinds of content:
#
#   * ANALYSIS DEFAULTS  -- window definitions, fitting parameters, the estimator
#                           machinery. These change as the method develops, so
#                           config.R gets replaced from time to time.
#   * YOUR REGISTRY      -- which sites are active, each site's flow lag, which
#                           stock node, which estimator. Irreplaceable, and
#                           specific to this project and this machine.
#
# Keeping both in one file means every replacement of config.R silently wipes the
# second kind. That is exactly what happened: six configured sites and six
# per-site flow lags reverted to a single-site placeholder, and the only visible
# symptom was one entry in the site dropdown.
#
# config.R now sources this file LAST, so anything set here wins. Put your
# settings here and config.R can be replaced freely.
#
# It is committed, not git-ignored: the site registry and the flow lags are part
# of the analysis and belong in the repository.
# =============================================================================


# =============================================================================
# 1. ACTIVE SITES
# -----------------------------------------------------------------------------
# One results page is generated per site listed here, plus the hub. Comment a
# site out to drop it from a run without losing the entry.
# =============================================================================
CFG$sites$active <- c(
  "Madison.Norris",
  "Missouri.Cascade",
  "Missouri.Craig",
  "BigHole.Melrose",
  "Beaverhead.FishAndGame",
  "Beaverhead.Hildreth"
)


# =============================================================================
# 2. FLOW LAG PER SITE
# -----------------------------------------------------------------------------
# From each site's IPM indicator-variable selection
# (`_RecLagInclusionProbQuad.csv`). NOT the recruit lag, which is 3 everywhere.
#
#   lag == recruit lag (3)  the hydrograph is the SPAWNING year
#   lag <  recruit lag      the hydrograph is the AGE-0 REARING year
#
# These encode different biological hypotheses, so a wrong value here shifts the
# whole analysis by a year at that site and is invisible in the output. A named
# vector rather than a switch(), so an unconfigured site can be detected and
# reported instead of silently taking a default.
# =============================================================================
FLOW_LAG_BY_SITE <- c(
  "Madison.Norris"         = 3L,
  "Missouri.Cascade"       = 2L,
  "Missouri.Craig"         = 3L,
  "BigHole.Melrose"        = 2L,
  "Beaverhead.FishAndGame" = 2L,
  "Beaverhead.Hildreth"    = 2L
)


# =============================================================================
# 3. ANALYSIS CHOICES YOU HAVE MADE
# -----------------------------------------------------------------------------
# Recorded here rather than in config.R so they survive a replacement, and so
# they are visible in one place when writing the methods section.
# =============================================================================

# --- which posterior node is the stock ---------------------------------------
# *** THIS ONE IS WORTH A DECISION, NOT A DEFAULT. ***
# "BAdults" is adult BIOMASS in grams and is what the IPM's own Ricker uses:
#     lRm = la0 + log(BAdults) - b*BAdults
# "NAdults" is adult NUMBERS. With NAdults the flow effect is estimated against
# one stock definition and projected with another -- the same mismatch found in
# the original WorkingFPCA_robust.R, which pulled NAdults while its comment said
# BAdults.
#
# Set deliberately, and say which in the methods.
CFG$posterior$stock_node <- "NAdults"

# --- how beta(d) is estimated -------------------------------------------------
# "fpc"       beta(d) built from the leading modes of variation in flow
# "penalized" beta(d) constrained to be smooth
#
# With compare_estimators = TRUE both are fitted and gated on identical folds,
# which costs seconds. Agreement between two different priors is the strongest
# available evidence that a daily peak is in the data rather than in the
# estimator -- see docs/FPC_reviewer_critiques.md, which also covers the
# cross-site basis problem now that six sites are active.
CFG$fitting$estimator          <- "fpc"
CFG$fitting$compare_estimators <- FALSE

# --- fpc component selection --------------------------------------------------
#   "cumulative"  retain until joint variance >= fpc_target_var
#   "individual"  retain each component explaining >= fpc_min_var
#   "both"        the smaller of the two
CFG$fitting$fpc_rule       <- "both"
CFG$fitting$fpc_target_var <- 90
CFG$fitting$fpc_min_var    <- 1
CFG$fitting$fpc_max        <- 6


# =============================================================================
# 4. ANYTHING ELSE
# -----------------------------------------------------------------------------
# This file is sourced after CFG is fully built, so any element can be
# overridden here. Examples:
#
#   CFG$paths$data_root        <- "../DroughtTrout/LL/Data"
#   CFG$fitting$block_len      <- 5
#   CFG$decision_window$start  <- "05-01"
#   CFG$windows$summer         <- c(182, 273)
#
# Put a comment on anything non-obvious. This file is the record of what was
# chosen and why, and it is what a reader of the manuscript will want to see.
# =============================================================================
