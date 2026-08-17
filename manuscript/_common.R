# =============================================================================
# _common.R -- shared setup for every .Rmd in this folder.
#
# EVERY NUMBER IN THE MANUSCRIPT COMES FROM DISK. Nothing is typed by hand.
# If an input is missing, the value renders as **[PENDING]** rather than silently
# falling back to a stale figure. That is deliberate: a methods section that
# renders cleanly with missing inputs is one that will eventually describe an
# analysis nobody ran.
# =============================================================================

knitr::opts_chunk$set(echo = FALSE, message = FALSE, warning = FALSE,
                      fig.align = "center", dpi = 150, out.width = "100%")

suppressPackageStartupMessages({
  library(dplyr); library(ggplot2); library(knitr); library(tidyr)
})

ROOT <- normalizePath(file.path(dirname(knitr::current_input(dir = TRUE)), ".."),
                      mustWork = FALSE)
if (!dir.exists(file.path(ROOT, "output"))) ROOT <- normalizePath("..", mustWork = FALSE)
OUTD <- file.path(ROOT, "output")
# config.R is plain R now; source it rather than parsing yaml.
# "use the left value unless it is missing". Defined here because _common.R does
# NOT source R/00_config.R -- the pages must render from config.R plus the saved
# output alone, without re-running the pipeline's startup checks.
`%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a

source(file.path(ROOT, "config.R"))

.rd <- function(f) { p <- file.path(OUTD, "models", f); if (file.exists(p)) readRDS(p) else NULL }
.tb <- function(f) { p <- file.path(OUTD, "tables", f)
                     if (file.exists(p)) read.csv(p, stringsAsFactors = FALSE) else NULL }

BR <- .rd("beta_recruitment.rds"); BS <- .rd("beta_survival.rds")

# The per-day curves as tables: site, doy, beta, lo, hi, p_pos, edf. Scripts 03
# and 04 already compute these, so pages read them rather than re-deriving from
# beta_draws and Vbeta -- one definition, and no chance of the two drifting.
BETAR <- .tb("beta_recruitment.csv"); BETAS <- .tb("beta_survival.csv")

# Flow lag per site, for the RQ2 comparability grouping. Sites with different
# lags describe different years of the fish's life and must not be pooled.
lag_of <- function(B) if (is.null(B) || is.null(B$fits)) NULL else
  vapply(B$fits, function(f) as.integer(f$flow_lag %||% NA), integer(1))
lag_group_of <- function(lags) ifelse(
  is.na(lags), "lag unknown",
  ifelse(lags >= CFG$biology$recruit_lag, "spawning-year lag", "rearing-year lag"))
GT <- .rd("gate.rds"); SE <- .rd("sensitivity.rds")
PR <- .rd("production.rds"); SC <- .rd("scenarios.rds"); RESP <- .rd("response.rds")
DW <- .rd("decision_window.rds")
RCV <- .rd("rulecurve.rds")               # script 10: equilibrium K / MS          # script 06b: the allocation season

GATE  <- .tb("gate.csv"); DAILY <- .tb("sensitivity_daily.csv")
IVS   <- .tb("best_day_intervals.csv"); RELW <- .tb("release_windows.csv")
STAGE <- .tb("life_stage_sensitivity.csv"); LIFE <- .tb("life_history_timeline.csv")
MODES <- .tb("fpc_modes.csv")            # script 03, fpc arm only
SCEFF <- .tb("scenario_effects.csv"); PRODT <- .tb("production_sensitivity.csv")
DWDAY <- .tb("decision_window_daily.csv"); DWCOST <- .tb("decision_window_cost.csv")
DWSCH <- .tb("decision_window_schedule.csv")
RCSUM <- .tb("rulecurve_summary.csv"); RCYR <- .tb("rulecurve_by_year.csv")

S <- local({ d <- .tb("derived_stats.csv"); if (is.null(d)) list() else
             setNames(as.list(d$value), d$stat) })

# value-or-placeholder
# derived_stats.csv stores every value as character, so these coerce. A value
# that is genuinely non-numeric (estimator = "penalized", fpc_rule = "individual")
# is returned AS IS rather than becoming NA -- otherwise a label would silently
# render as "[PENDING]" and read as a missing result.
V <- function(x, dg = 3) {
  if (is.null(x) || !length(x) || all(is.na(x))) return("**[PENDING]**")
  n <- suppressWarnings(as.numeric(x[1]))
  if (is.na(n)) as.character(x[1]) else formatC(n, format = "f", digits = dg)
}
Vi <- function(x) {
  if (is.null(x) || !length(x) || is.na(x[1])) return("**[PENDING]**")
  n <- suppressWarnings(as.numeric(x[1]))
  if (is.na(n)) as.character(x[1]) else formatC(n, format = "d")
}

# Calendar day-of-year -> readable date label. Anchored on 1 JANUARY: day 1 is
# 1 Jan, day 365 is 31 Dec. 2001 is used because it is a non-leap year, matching
# the 365-day grid the pipeline builds.
doy_date <- function(d) {
  if (is.null(d) || !length(d) || any(is.na(d))) return("**[PENDING]**")
  format(as.Date("2001-01-01") + (round(as.numeric(d)) - 1), "%d %b")
}

# Prefer the RELATIVE copy that render_site.R places in manuscript/figures/.
#
# An absolute path into output/ works when you knit a single .Rmd locally, but
# output/ is git-ignored and never reaches the gh-pages branch, so the deployed
# site would show broken images while looking fine on the machine that built it.
# Falling back to the absolute path keeps single-file knitting working.
# `site` is optional. When a per-site figure exists (written as
# <name>__<site>.png) it is preferred; otherwise the faceted all-site figure is
# used. That lets the plotting scripts move to per-site output incrementally
# without the pages changing.
FIG <- function(name, site = NULL) {
  if (!is.null(site)) {
    per <- file.path("figures", paste0(name, "__", gsub("[^A-Za-z0-9]", "_", site), ".png"))
    if (file.exists(per)) return(knitr::include_graphics(per))
  }
  rel <- file.path("figures", paste0(name, ".png"))     # relative to the .Rmd
  if (file.exists(rel)) return(knitr::include_graphics(rel))
  abs <- file.path(OUTD, "figures", paste0(name, ".png"))
  if (file.exists(abs)) {
    warning(sprintf("FIG('%s') fell back to an absolute path. Fine for local knitting; ",
                    name), "run render_site.R before publishing.", call. = FALSE)
    return(knitr::include_graphics(abs))
  }
  cat("\n> **Figure not available** — run the corresponding script.\n\n")
}

# Calendar day-of-year axis. MUST match MON_B / MON_L in R/00_config.R, or the
# figures script and the manuscript will label the same axis differently.
MON_B <- c(1, 32, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335)
MON_L <- c("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec")

# `form` is matched as a PREFIX, because script 05 now labels the functional arms
# "beta:penalized" and "beta:fpc". GATE_OK("recruitment", "beta") therefore asks
# "did every functional arm pass", which is the conservative reading and the one
# the daily-guidance sections should use.
GATE_OK <- function(proc = "recruitment", form = "beta") {
  if (is.null(GATE)) return(NA)
  g <- GATE[GATE$process == proc & startsWith(GATE$form, form), ]
  if (!nrow(g)) NA else all(g$passes)
}

# Do the two beta estimators agree that the signal is real? This is the standard
# for daily guidance: agreement across priors beats either one's interval.
ESTIMATORS_AGREE <- function(proc = "recruitment") {
  if (is.null(GATE)) return(NA)
  g <- GATE[GATE$process == proc & startsWith(GATE$form, "beta"), ]
  if (nrow(g) < 2) return(NA)      # only one arm was run
  all(g$passes)
}

# --- shared plot style, so inline figures match the ones script 09 writes -----
PAL <- c(blue = "#2c6fa8", red = "#b5462f", gold = "#c9a227",
         green = "#4a7c4e", ink = "#16202a", mute = "#7a8590")

theme_wh <- ggplot2::theme_classic(base_size = 11) +
  ggplot2::theme(
    plot.title       = ggplot2::element_text(face = "bold", size = 12),
    plot.subtitle    = ggplot2::element_text(size = 9.5, colour = "grey35"),
    strip.background = ggplot2::element_rect(fill = "grey95", colour = NA),
    strip.text       = ggplot2::element_text(face = "bold", size = 9))
