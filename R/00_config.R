# =============================================================================
# 00_config.R -- load config.R, check every input exists, set shared constants.
#
# Sourced by every other script. Contains NO analysis and NO hard-coded paths.
#
# Run it alone to check your setup before anything else:
#     source("R/00_config.R")
# It prints OK or MISSING for each input file, so a path problem shows up here
# rather than three scripts later as a confusing error.
# =============================================================================

suppressPackageStartupMessages({
  library(here); library(dplyr); library(ggplot2)
})

`%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a
# =============================================================================
# LOAD THE SETTINGS
# -----------------------------------------------------------------------------
# config.R is plain R: syntax-checked by your editor, errors carry line numbers,
# and site quirks are ordinary switch() branches. It replaced config.yml, whose
# whitespace-only nesting produced a duplicate-key failure with no line number.
# =============================================================================
if (!file.exists(here::here("config.R")))
  stop("config.R not found at the project root: ", here::here())
source(here::here("config.R"))

# Version stamp. If you ever see "could not find function" for something defined
# below, the file that actually loaded is an older copy -- check this number
# against the one in the repository before debugging anything else.
# ---------------------------------------------------------------------------
# CATCH SILENT FIELD-NAME ERRORS.
#
# R's `$` does PARTIAL MATCHING on lists. When a field is renamed, `f$lag` does
# not error -- it quietly resolves to `f$lag_sweep`, giving a confusing failure
# far from the cause. Worse, `z$years` after a rename simply returns NULL, and
# `length(NULL)` is 0, so a count silently becomes zero with no error at all.
#
# Both happened in this project (script 04, session 17). These options turn
# partial matches into visible warnings.
# ---------------------------------------------------------------------------
options(warnPartialMatchDollar = TRUE,
        warnPartialMatchArgs   = TRUE)

CONFIG_VERSION <- "2026-07-29.17"   # + partial-match warnings; survival field renames

for (k in c("paths", "sites", "posterior", "biology", "windows", "fitting",
            "sensitivity", "decision_window", "production", "qc"))
  if (is.null(CFG[[k]]))
    stop("config.R defines CFG but CFG$", k, " is missing. ",
         "Compare against the copy in the repository.")
for (f in c("posterior_path", "flow_path", "params_path", "params_filter"))
  if (!exists(f, mode = "function"))
    stop("config.R must define ", f, "().")

# --- shorthands used everywhere ----------------------------------------------
SITES     <- CFG$sites$all
REC_LAG   <- CFG$biology$recruit_lag
WINDOWS   <- CFG$windows                 # named list of c(start, end) on the WY axis
WIN       <- names(WINDOWS)
ZWIN      <- paste0("z_", WIN)
OUT       <- here::here(CFG$paths$output)
ESTIMATOR <- CFG$fitting$estimator %||% "penalized"
COMPARE   <- isTRUE(CFG$fitting$compare_estimators)
FPC_RULE  <- CFG$fitting$fpc_rule %||% "cumulative"
FPC_VAR   <- CFG$fitting$fpc_target_var %||% 90
FPC_MIN   <- CFG$fitting$fpc_min_var %||% 0
FPC_MAX   <- CFG$fitting$fpc_max %||% 10L
K_BETA    <- CFG$fitting$k_beta %||% 20L

for (d in file.path(OUT, c("models", "tables", "figures")))
  dir.create(d, recursive = TRUE, showWarnings = FALSE)

# --- resolve a path from config.R ------------------------------------------
# "use the left value unless it is missing, then the right one". Defined HERE,
# before anything uses it, rather than at the foot of a file and relying on lazy
# lookup. Scripts 06 and 06b use it for every setting default.
`%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a

# Absolute paths pass through; relative ones resolve from the project root.
path_of <- function(p) if (grepl("^(/|[A-Za-z]:)", p)) p else here::here(p)

# --- per-site file paths -----------------------------------------------------
# Defined in config.R as posterior_path(), flow_path(), params_path(). Kept
# there rather than here so that everything a new site needs is in one file.


# =============================================================================
# SHARED PLOT STYLE
# -----------------------------------------------------------------------------
# Defined once here so every script's figures match, and so the manuscript's
# inline plots match the .png files the scripts write.
#
# MON_B / MON_L put month names on the CALENDAR day-of-year axis (1 = 1 Jan).
# =============================================================================

# =============================================================================
# SAVE A FIGURE: ALL-SITES VERSION PLUS ONE PER SITE
# -----------------------------------------------------------------------------
# Per-site report pages call FIG("03_f3a", SITE_FOCUS), which looks for
#   figures/03_f3a__Madison_Norris.png
# and falls back to figures/03_f3a.png when that is absent. That fallback is why
# the site pages were quietly showing faceted all-site plots instead of failing.
#
# Writing a site-suffixed COPY of the faceted plot would not fix it -- the image
# would still show every site. The plot DATA has to be filtered.
#
# Done generically here so ~40 individual ggplot calls did not need rewriting: a
# ggplot keeps its data in p$data, and any layer given its own data keeps it in
# p$layers[[i]]$data. Filter both to one site, drop the site facet (one panel is
# not a facet), and save.
#
# A plot with no `site` column anywhere is a genuine all-sites figure -- the
# among-site synthesis, the explain figures -- and is saved once, unfiltered.
# =============================================================================
save_fig <- function(name, plot, width = 9.5, height = 5.2, dpi = 150,
                     sites = NULL, dir = file.path(OUT, "figures")) {
  if (is.null(plot)) return(invisible(NULL))
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  ggplot2::ggsave(file.path(dir, paste0(name, ".png")), plot,
                  width = width, height = height, dpi = dpi)

  has_site <- function(d) is.data.frame(d) && "site" %in% names(d)
  present <- character(0)
  if (has_site(plot$data)) present <- unique(as.character(plot$data$site))
  for (ly in plot$layers)
    if (has_site(ly$data)) present <- union(present, as.character(ly$data$site))
  if (!length(present)) return(invisible(NULL))          # genuinely all-sites

  for (s in (if (is.null(sites)) present else sites)) {
    ps <- plot
    if (has_site(ps$data))
      ps$data <- ps$data[as.character(ps$data$site) == s, , drop = FALSE]
    for (i in seq_along(ps$layers)) {
      ld <- ps$layers[[i]]$data
      if (has_site(ld))
        ps$layers[[i]]$data <- ld[as.character(ld$site) == s, , drop = FALSE]
    }
    n_main <- if (is.data.frame(ps$data)) nrow(ps$data) else 0L
    n_lyr  <- sum(vapply(ps$layers,
                 function(l) if (has_site(l$data)) nrow(l$data) else 0L, numeric(1)))
    if (n_main == 0 && n_lyr == 0) next                  # site absent from this figure

    # Drop a site facet; keep a facet on anything else (process, scenario).
    fv <- tryCatch(names(ps$facet$params$facets), error = function(e) NULL)
    fr <- tryCatch(names(ps$facet$params$rows),   error = function(e) NULL)
    fc <- tryCatch(names(ps$facet$params$cols),   error = function(e) NULL)
    if (identical(fv, "site") ||
        (identical(fr, "site") && !length(fc)) ||
        (identical(fc, "site") && !length(fr)))
      ps <- ps + ggplot2::facet_null()

    # A filtered plot inherits a title written for the all-sites version
    # ("every site's beta(d)"). Append the site so the per-site page is not
    # captioned with a claim about sites it does not show.
    ttl <- tryCatch(ps$labels$title, error = function(e) NULL)
    if (!is.null(ttl) && nzchar(ttl) && !grepl(s, ttl, fixed = TRUE))
      ps <- ps + ggplot2::labs(title = paste0(ttl, " — ", s))

    ggplot2::ggsave(
      file.path(dir, paste0(name, "__", gsub("[^A-Za-z0-9]", "_", s), ".png")),
      ps, width = width, height = height, dpi = dpi)
  }

  # Record what was split, so RUN_ALL.R can report which figures are all-sites
  # only. Without this the gap is invisible until a page renders wrong.
  if (!exists(".FIG_INDEX", envir = globalenv()))
    assign(".FIG_INDEX", list(), envir = globalenv())
  idx <- get(".FIG_INDEX", envir = globalenv())
  idx[[name]] <- present
  assign(".FIG_INDEX", idx, envir = globalenv())

  invisible(present)
}

# =============================================================================
# fig_report() -- which figures exist per site, and which are all-sites only
# -----------------------------------------------------------------------------
# A figure whose data carries no `site` column cannot be split, so the per-site
# pages will show a gap for it. That is correct behaviour, but it must be
# VISIBLE: the alternative is discovering it when a collaborator opens the site.
# Called at the end of RUN_ALL.R.
# =============================================================================
fig_report <- function(sites = SITES) {
  idx <- if (exists(".FIG_INDEX", envir = globalenv()))
    get(".FIG_INDEX", envir = globalenv()) else list()
  if (!length(idx)) { message("  (no figures recorded this run)"); return(invisible(NULL)) }

  split_ok <- names(idx)[vapply(idx, length, integer(1)) > 0]
  all_only <- setdiff(names(idx), split_ok)

  message(sprintf("\n  figures: %d produced | %d split per site | %d all-sites only",
                  length(idx), length(split_ok), length(all_only)))
  if (length(all_only)) {
    message("  all-sites only (no `site` column in the plot data):")
    for (n in all_only) message("    ", n)
    message("  These will show a gap on per-site pages. If one of them SHOULD be")
    message("  per-site, give its data a `site` column; otherwise reference it")
    message("  only from the all-sites page.")
  }
  # which sites are missing from figures that DID split
  for (n in split_ok) {
    miss <- setdiff(sites, idx[[n]])
    if (length(miss))
      message("  ", n, ": no data for ", paste(miss, collapse = ", "))
  }
  invisible(idx)
}

PAL <- c(blue = "#2c6fa8", red = "#b5462f", gold = "#c9a227",
         green = "#4a7c4e", ink = "#16202a", mute = "#7a8590")

theme_wh <- ggplot2::theme_classic(base_size = 11) +
  ggplot2::theme(
    plot.title       = ggplot2::element_text(face = "bold", size = 12),
    plot.subtitle    = ggplot2::element_text(size = 9.5, colour = "grey35"),
    strip.background = ggplot2::element_rect(fill = "grey95", colour = NA),
    strip.text       = ggplot2::element_text(face = "bold", size = 9))

MON_B <- c(1, 32, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335)
MON_L <- c("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec")

# Day-of-year -> a readable date, e.g. 195 -> "14 Jul". Non-leap convention
# throughout, matching the 365-day curves.
doy_date <- function(d)
  format(as.Date("2001-01-01") + as.integer(d) - 1L, "%d %b")

# Day-of-year -> month abbreviation
doy_month <- function(d) MON_L[findInterval(d, MON_B)]


# =============================================================================
# CALENDAR YEARS FOR A SITE
# -----------------------------------------------------------------------------
# Reads the real years out of the JAGS parameter CSV, replacing the hardcoded
# first_year. This matters more than it looks: a wrong start year shifts every
# lag by a whole year and is INVISIBLE in the output -- the analysis still
# produces plausible coefficients. Reading the actual years gives the start AND
# the count, so scripts 01 and 04 can CHECK them against the posterior's column
# count and stop rather than guess.
#
# Where the file lives and which rows to keep are decided by params_path() and
# params_filter() in config.R -- plain switch()/if() branches, one place.
#
# Returns an integer vector of years, or NULL if the CSV is absent (the caller
# decides whether that is fatal).
# =============================================================================
site_years <- function(site, quiet = FALSE) {
  path <- path_of(params_path(site))

  if (!file.exists(path)) {
    if (!quiet)
      warning("site_years(): no params CSV for ", site, " at\n  ", path,
              "\n  Add a switch() branch in config.R -> params_path().",
              call. = FALSE)
    return(NULL)
  }

  d <- params_filter(site, utils::read.csv(path, stringsAsFactors = FALSE))
  if (!nrow(d))
    stop("site_years(): ", site, " -- params_filter() kept no rows. ",
         "Check the branch in config.R.")
  for (k in c("name", "Year"))
    if (!k %in% names(d))
      stop("site_years(): ", site, " -- CSV has no `", k, "` column.")

  yrs <- sort(unique(as.integer(d$Year[d$name == params_year_name])))
  yrs <- yrs[is.finite(yrs)]
  if (!length(yrs))
    stop("site_years(): ", site, " -- no rows with name == '", params_year_name,
         "'. Check params_year_name in config.R.")

  # Gaps are not fatal -- scripts 01 and 04 match years explicitly rather than
  # assuming a fixed offset -- but they silently shrink the usable series.
  gaps <- setdiff(seq(min(yrs), max(yrs)), yrs)
  if (length(gaps) && !quiet)
    message("    note: ", site, " has ", length(gaps), " missing year(s) between ",
            min(yrs), " and ", max(yrs), "; lagged pairs spanning a gap are dropped.")

  attr(yrs, "path") <- path
  attr(yrs, "gaps") <- gaps
  yrs
}


# =============================================================================
# STARTUP CHECK
# =============================================================================
message("\n--- WH_BOR_Trout configuration ---")
message("  settings      : config.R")
message("  project root  : ", here::here())
message("  sites         : ", paste(SITES, collapse = ", "))
message("  recruit lag   : ", REC_LAG, " years (biology, all sites)")
for (s_ in SITES) {
  # config.R may define flow_lag() as a named vector (inspectable) or as a
  # switch() (not inspectable). Reporting "NOT CONFIGURED" for the switch() form
  # is a false alarm, and a check that cries wolf gets ignored.
  inspectable <- exists("FLOW_LAG_BY_SITE")
  configured  <- inspectable && s_ %in% names(FLOW_LAG_BY_SITE)
  L_ <- suppressWarnings(tryCatch(flow_lag(s_), error = function(e) NA_integer_))
  message("  flow lag      : ", s_, " = ", L_,
          if (inspectable && !configured)
            "  *** NOT CONFIGURED -- default assumed, see config.R ***"
          else if (is.na(L_)) "  *** could not be determined ***"
          else if (L_ == REC_LAG) "  (spawning-year conditions)"
          else "  (age-0 rearing-year conditions)")
}
if (ESTIMATOR == "fpc" || COMPARE)
  message("  fpc selection : ", FPC_RULE,
          switch(FPC_RULE,
                 cumulative = paste0("   (jointly >= ", FPC_VAR, "% of flow variance)"),
                 individual = paste0("   (each >= ", FPC_MIN, "%)"),
                 both       = paste0("   (jointly >= ", FPC_VAR, "% AND each >= ", FPC_MIN, "%)")),
          "   cap ", FPC_MAX)
message("  estimator     : ", ESTIMATOR,
        if (COMPARE) "   (the other arm is also fitted and gated)" else
                     "   (compare_estimators is off -- you will not see the other arm)")
message("  stock node    : ", CFG$posterior$stock_node,
        if (identical(CFG$posterior$stock_node, "BAdults"))
          "   (adult BIOMASS, grams -- matches the IPM Ricker)"
        else "   *** NOT BAdults: this reproduces the old numbers-vs-biomass mismatch ***")

# When a path is missing, saying so is not much help. Walking up to the deepest
# folder that DOES exist and listing what is in it turns "MISSING" into a
# diagnosis -- it shows immediately whether the prefix is wrong (nothing looks
# familiar) or just the filename (the folder is full of near-misses).
.diagnose <- function(p) {
  d <- dirname(p)
  while (nchar(d) > 1 && !dir.exists(d)) d <- dirname(d)
  if (!dir.exists(d)) return(invisible(NULL))
  message("           deepest existing folder: ", d)
  f <- head(sort(list.files(d)), 8)
  if (length(f)) message("           contains: ", paste(f, collapse = ", "),
                         if (length(list.files(d)) > 8) ", ..." else "")
  else message("           (empty)")
}

.ok <- function(label, p, diagnose = TRUE) {
  e <- file.exists(p) || dir.exists(p)
  message(sprintf("  [%s] %-24s %s", if (e) "OK " else "MISSING", label, p))
  if (!e && diagnose) .diagnose(p)
  e
}

checks <- c(flow_dir = .ok("flow directory", path_of(CFG$paths$flow_dir)),
            post_dir = .ok("posterior directory", path_of(CFG$paths$posterior_dir)))
for (s in SITES) {
  checks[paste0("post_", s)] <- .ok(paste0("posterior: ", s),
                                    posterior_path(s))
  checks[paste0("flow_", s)] <- .ok(paste0("flow: ", s),
                                    flow_path(s))
}

# --- year extraction, per site ------------------------------------------------
# Scaling to 14 sites, this is where a misconfigured site announces itself --
# immediately, rather than three scripts later as a shifted lag nobody notices.
if (TRUE) {
  message("\n  calendar years (read from the JAGS parameter CSVs):")
  for (s in SITES) {
    # Deliberately NOT catching everything: a missing helper means the wrong
    # version of this file or of config.R is loaded, and that must surface as a
    # hard stop rather than as a per-site "ERROR" line that looks like a data
    # problem.
    for (fn in c("params_path", "params_filter", "site_years"))
      if (!exists(fn, mode = "function"))
        stop("`", fn, "()` is not defined.\n",
             "  This means a STALE copy of R/00_config.R or config.R is loaded.\n",
             "  Restart R (Session > Restart R), then source R/00_config.R again.\n",
             "  Loaded config version: ",
             if (exists("CONFIG_VERSION")) CONFIG_VERSION else "(pre-versioning)")

    yr <- tryCatch(site_years(s, quiet = TRUE), error = function(e) e)
    if (inherits(yr, "error")) {
      message(sprintf("  [ERROR  ] %-24s %s", s, conditionMessage(yr)))
      checks[paste0("years_", s)] <- FALSE
    } else if (is.null(yr)) {
      message(sprintf("  [MISSING] %-24s no params CSV -- would fall back to first_year = %s",
                      s, CFG$posterior$first_year))
      checks[paste0("years_", s)] <- FALSE
    } else {
      message(sprintf("  [OK     ] %-24s %d-%d  (%d years%s)", s,
                      min(yr), max(yr), length(yr),
                      if (length(attr(yr, "gaps"))) paste0(", ", length(attr(yr, "gaps")), " gap(s)") else ""))
      checks[paste0("years_", s)] <- TRUE
    }
  }
}

if (any(!checks)) {
  message("\n  One or more inputs are missing.")
  message("  Paths in config.R are relative to the PROJECT ROOT printed above.")
  message("  If every path is missing but the folder listing looks familiar, the")
  message("  prefix is wrong -- check whether this project sits INSIDE the data")
  message("  folder (prefix \"../LL/\") or beside it (prefix \"../DroughtTrout/LL/\").")
  message("  Edit CFG$paths, and params_path() at the foot of config.R, together.")
  message("  Nothing downstream will work until every line above says OK.\n")
} else {
  message("\n  All inputs found. Ready.\n")
}

invisible(NULL)
