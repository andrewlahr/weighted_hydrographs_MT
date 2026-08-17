# =============================================================================
# check_setup.R -- verify the project can run BEFORE you run it.
#
#     source("check_setup.R")
#
# Takes about a second. Needs no data, no posterior, no flow files. It catches
# the class of error that is otherwise found halfway through a pipeline run:
#
#   * a script that calls a function it never sourced
#   * a CFG setting a script expects but config.R does not define
#   * a required package that is not installed
#   * a syntax error introduced by an edit
#   * input files that are missing or misconfigured for a site
#
# WHY THIS EXISTS. `simulate_beta()` was moved from script 06 into
# fn_fit_beta.R, and script 06 was not given the matching `source()` line. That
# is invisible until script 06 runs -- several minutes into a pipeline, after
# three other scripts have already written output. A parse-level check finds it
# immediately.
#
# Run it after ANY edit to config.R, 00_config.R, or fn_fit_beta.R.
# =============================================================================

cat("\n", strrep("=", 68), "\n  WH_BOR_Trout setup check\n", strrep("=", 68), "\n", sep = "")

ok_all <- TRUE
say <- function(pass, label, detail = "") {
  cat(sprintf("  [%s] %-42s %s\n", if (pass) "OK  " else "FAIL", label, detail))
  if (!pass) ok_all <<- FALSE
  invisible(pass)
}

# =============================================================================
# 1. PACKAGES
# =============================================================================
cat("\n-- packages --\n")
need <- c("here", "dplyr", "ggplot2", "tidyr", "purrr", "lubridate", "mgcv", "knitr")
for (p in need) {
  have <- requireNamespace(p, quietly = TRUE)
  say(have, p, if (have) "" else sprintf('install.packages("%s")', p))
}

opt <- c(rmarkdown = "rendering the website")
for (p in names(opt))
  cat(sprintf("  [%s] %-42s %s\n",
              if (requireNamespace(p, quietly = TRUE)) "OK  " else "note",
              p, if (requireNamespace(p, quietly = TRUE)) "" else
                 paste("optional --", opt[[p]])))

# =============================================================================
# 2. FILES PRESENT
# =============================================================================
cat("\n-- project files --\n")
must <- c("config.R", "RUN_ALL.R", "R/00_config.R", "R/fn_fit_beta.R",
          "R/01_build_response.R", "R/02_build_flow.R",
          "R/03_fit_beta_recruitment.R", "R/04_fit_beta_survival.R",
          "R/05_validate.R", "R/06_daily_sensitivity.R",
          "R/06b_decision_window.R", "R/07_production_sensitivity.R",
          "R/08_scenarios_bor.R", "R/09_figures.R",
          "R/10_rulecurve.R")
for (f in must) say(file.exists(f), f)
if (!ok_all) {
  cat("\n  Missing files -- stopping here.\n\n"); stop("setup incomplete", call. = FALSE)
}

# =============================================================================
# 3. EVERY SCRIPT PARSES
# -----------------------------------------------------------------------------
# parse() reads the file without executing it, so a syntax error is reported
# with a line number and nothing is run.
# =============================================================================
cat("\n-- syntax --\n")
# Include THIS file. It checked every other script and never itself, so a syntax
# error here surfaced only as a source() failure with no context -- which is
# exactly how an orphaned top-level `else` was shipped.
for (f in c("check_setup.R", "render_site.R", "diagnose_site.R",
            must, list.files("R/explain", "\\.R$", full.names = TRUE))) {
  e <- tryCatch({ parse(f); TRUE }, error = function(e) conditionMessage(e))
  say(isTRUE(e), basename(f), if (isTRUE(e)) "" else sub("\n.*", "", e))
}

# --- per-site figures the template requests ----------------------------------
# The per-site pages call FIG(name, SITE_FOCUS), which now shows a gap rather
# than silently substituting the all-sites figure. This reports the gaps before
# you render, so they are fixed in the pipeline rather than noticed on the site.
tpl <- file.path("manuscript", "_site_template.Rmd")
if (file.exists(tpl) && dir.exists(file.path(OUT, "figures"))) {
  want <- unique(regmatches(
    paste(readLines(tpl, warn = FALSE), collapse = " "),
    gregexpr('FIG\\("[^"]+", *SITE_FOCUS\\)',
             paste(readLines(tpl, warn = FALSE), collapse = " ")))[[1]])
  want <- gsub('FIG\\("|", *SITE_FOCUS\\)', "", want)
  have <- list.files(file.path(OUT, "figures"), "[.]png$")
  gaps <- character(0)
  for (s_ in SITES) {
    sfx <- gsub("[^A-Za-z0-9]", "_", s_)
    miss <- want[!paste0(want, "__", sfx, ".png") %in% have]
    if (length(miss)) gaps <- c(gaps, sprintf("%s: %s", s_, paste(miss, collapse = ", ")))
  }
  say(length(gaps) == 0, "per-site figures exist for every template FIG() call",
      if (length(gaps)) paste0(length(gaps), " site(s) with gaps") else
        paste(length(want), "figures x", length(SITES), "site(s)"))
  for (g in gaps) cat("      ", g, "\n")
}

# =============================================================================
# STALE-FILE SCAN
# -----------------------------------------------------------------------------
# The symbol checks above test what IS loaded. This tests what is ON DISK.
#
# When files are copied between machines by hand, one script can lag behind the
# rest. The failure is confusing because it appears deep in a run as "object not
# found" for a symbol that was renamed sessions ago, and the version stamp only
# helps if you happen to look at it.
#
# This scans the pipeline for symbols that have been RETIRED and names the file
# and line. If it flags something, that file is an old copy -- replace it rather
# than trying to make the symbol exist.
# =============================================================================
RETIRED <- c(
  # water-year axis -> calendar axis
  "WY_LABELS", "WY_BREAKS", "WY_L", "WY_B", "WY_START",
  "wday_date", "wday_month", "water_year", "water_years",
  "flow_water_year", "spawn_water_year",
  # config.yml -> config.R
  "site_file", "read_yaml", "years_from",
  # survival field renames
  "surv_years_old",
  # manuscript-side renames (index.Rmd used these before the calendar migration)
  "lo_wday", "hi_wday", "median_wday", "beta_mean"
)
# NOTE: render_site.R carries the same list and runs it against manuscript/ before
# rendering. If you add a retired symbol, add it in BOTH places -- they guard
# different moments, and a symbol missing from either is a gap.
# `wday` alone is too common a substring to test safely; the specific names above
# cover every retired use of it.

r_files <- c(list.files("R", pattern = "\\.R$", full.names = TRUE, recursive = TRUE),
             list.files("manuscript", pattern = "\\.(R|Rmd)$", full.names = TRUE),
             "config.R", "RUN_ALL.R")
# The guard files themselves LIST the retired symbols as data, so scanning them
# reports every entry as a hit. Excluded here rather than by some cleverness in
# the pattern, because a literal list is exactly what they are supposed to hold.
r_files <- setdiff(r_files, c("check_setup.R", "render_site.R", "diagnose_site.R"))
r_files <- r_files[file.exists(r_files)]

stale <- list()
for (f in r_files) {
  ln <- readLines(f, warn = FALSE)
  code <- sub("#.*$", "", ln)                     # ignore comments
  for (sym in RETIRED) {
    hit <- grep(paste0("(?<![A-Za-z0-9_.])", sym, "(?![A-Za-z0-9_.])"),
                code, perl = TRUE)
    if (length(hit))
      stale[[length(stale) + 1]] <- data.frame(file = f, line = hit, symbol = sym)
  }
}

if (!length(stale)) {
  say(TRUE, "no retired symbols on disk", "all files current")
} else {
  st <- do.call(rbind, stale)
  say(FALSE, "STALE FILES DETECTED",
      paste0(nrow(st), " use(s) of retired symbols"))
  for (i in seq_len(nrow(st)))
    cat(sprintf("      %s:%d  uses retired `%s`\n", st$file[i], st$line[i], st$symbol[i]))
  cat("\n      These files are older copies. Replace them from the repository;\n")
  cat("      do not try to make the retired symbol exist.\n\n")
}

# =============================================================================
# 4. CONFIG LOADS AND EXPORTS WHAT IT SHOULD
# =============================================================================
cat("\n-- configuration --\n")
loaded <- tryCatch({ source("R/00_config.R"); TRUE },
                   error = function(e) conditionMessage(e))
if (!isTRUE(loaded)) {
  say(FALSE, "R/00_config.R loads", sub("\n.*", "", loaded))
  cat("\n  Fix the above before anything else.\n\n"); stop("config failed", call. = FALSE)
}
say(TRUE, "R/00_config.R loads")

for (f in c("posterior_path", "flow_path", "params_path", "params_filter",
            "site_years", "path_of", "flow_lag", "flow_year",
            "doy_date", "doy_month"))
  say(exists(f, mode = "function"), paste0(f, "()"),
      if (exists(f, mode = "function")) "" else "missing from config.R / 00_config.R")

for (v in c("CFG", "SITES", "REC_LAG", "WINDOWS", "WIN", "ZWIN",
            "OUT", "ESTIMATOR", "COMPARE", "FPC_RULE", "FPC_VAR", "FPC_MIN",
            "FPC_MAX", "K_BETA", "CONFIG_VERSION",
            "PAL", "theme_wh", "MON_B", "MON_L"))
  say(exists(v), v, if (exists(v)) "" else "not exported by R/00_config.R")

# -----------------------------------------------------------------------------
# The two checks below need SITES, path_of() and CFG, so they must run AFTER
# R/00_config.R has been sourced. They were previously placed in the syntax
# section, where none of those existed yet and the rule-curve check errored on
# path_of(). Placement in this file is load-order-sensitive: anything touching
# config must sit below this line.
# -----------------------------------------------------------------------------
# --- has config.R been replaced over the local settings? ---------------------
# The failure this catches is silent: the pipeline runs perfectly on one site and
# the only visible symptom is a short dropdown on the results page.
loc <- file.exists("config_local.R")
say(loc, "config_local.R present",
    if (loc) paste0(length(SITES), " active site(s)")
    else "MISSING -- config.R defaults apply; your site registry is not loaded")
if (loc && length(SITES) == 1)
  say(FALSE, "only one active site",
      "expected if deliberate; otherwise check CFG$sites$active in config_local.R")

# --- every active site must have a configured flow lag -----------------------
# The lag varies between sites and a wrong one is invisible in the results, so an
# unconfigured site is a failure rather than a note.
# `flow_lag()` may be written as a named vector (current) or as a switch() (the
# earlier form). Only the named vector can be inspected, so say which case
# applies rather than reporting "not configured" for a config that is fine.
if (exists("FLOW_LAG_BY_SITE")) {
  unset <- setdiff(SITES, names(FLOW_LAG_BY_SITE))
  say(length(unset) == 0, "flow lag configured for every active site",
      if (length(unset)) paste0("missing: ", paste(unset, collapse = ", "),
                                " -- add to FLOW_LAG_BY_SITE in config.R") else "")
} else {
  say(TRUE, "flow lag (cannot be verified)",
      "config.R defines flow_lag() as a switch(); values are used but not checkable")
}

# --- rule-curve arm (optional; only checked if its export exists) ------------
if (exists("rulecurve_export_path")) {
  ex <- path_of(rulecurve_export_path(SITES[[1]]))
  if (file.exists(ex)) {
    E <- try(readRDS(ex), silent = TRUE)
    ok <- !inherits(E, "try-error") &&
          all(c("covarLagIn1Real", "Flows", "Weight3", "Weight4",
                "Survival", "posterior_file") %in% names(E))
    say(ok, "rule-curve export readable",
        if (ok) basename(ex) else "missing required fields")
    if (ok) {
  # The export names a posterior file but not its folder. Fits normally live in
  # posterior_dir; some exports were written when they sat in data_root. Try both
  # rather than assuming, and say which was used.
  cand <- c(file.path(path_of(CFG$paths$posterior_dir), E$posterior_file),
            file.path(path_of(CFG$paths$data_root),     E$posterior_file))
  hit  <- cand[file.exists(cand)]
  say(length(hit) > 0, "rule-curve posterior (FLOW-INFORMED)",
      if (length(hit)) basename(hit[1])
      else paste0("not in posterior_dir or data_root: ", E$posterior_file))
    }
  } else {
    say(TRUE, "rule-curve export absent", "arm not in use — skipped")
  }
}


# =============================================================================
# 5. EVERY CFG SETTING THE SCRIPTS ASK FOR EXISTS
# -----------------------------------------------------------------------------
# Scans the scripts for CFG$group$key and checks each against the live list.
# A missing key would otherwise surface as a silent NULL -- and NULL flowing
# into arithmetic gives numeric(0), which propagates without erroring.
# =============================================================================
cat("\n-- CFG settings referenced by the scripts --\n")
files <- c(list.files("R", "\\.R$", full.names = TRUE, recursive = TRUE),
           list.files("manuscript", "\\.(R|Rmd)$", full.names = TRUE),
           "RUN_ALL.R")

# Comment lines are skipped. A reference inside a comment is documentation, not
# a dependency, and flagging it sends you hunting for a bug that is not there.
bad <- list()
for (f in files) {
  x <- readLines(f, warn = FALSE)
  x <- x[!grepl("^\\s*#", x)]
  for (r in unique(unlist(regmatches(x, gregexpr("CFG\\$[A-Za-z_0-9]+\\$[A-Za-z_0-9]+", x))))) {
    k <- strsplit(sub("^CFG\\$", "", r), "\\$")[[1]]
    if (is.null(CFG[[k[1]]]) || !(k[2] %in% names(CFG[[k[1]]])))
      bad[[length(bad) + 1]] <- data.frame(ref = r, file = f)
  }
}
n_refs <- length(unique(unlist(lapply(files, function(f) {
  x <- readLines(f, warn = FALSE); x <- x[!grepl("^\\s*#", x)]
  regmatches(x, gregexpr("CFG\\$[A-Za-z_0-9]+\\$[A-Za-z_0-9]+", x))
}))))

if (length(bad)) {
  bad <- do.call(rbind, bad)
  say(FALSE, sprintf("%d settings referenced", n_refs),
      sprintf("%d unresolved", nrow(bad)))
  for (i in seq_len(nrow(bad)))
    cat(sprintf("         %-32s in %s\n", bad$ref[i], bad$file[i]))
} else {
  say(TRUE, sprintf("%d settings referenced", n_refs), "all resolve")
}

# =============================================================================
# 6. FUNCTION CALLS MATCH source() LINES
# -----------------------------------------------------------------------------
# The check that would have caught simulate_beta(). For each script, does it
# call a function whose definition lives in a file it does not source?
# =============================================================================
cat("\n-- source() lines match function use --\n")
shared <- c(simulate_beta = "fn_fit_beta.R", fit_beta_curve = "fn_fit_beta.R",
            fit_seasonal  = "fn_fit_beta.R")

# NOTE the two corrections here, both of which produced false alarms:
#   1. "^[0-9]" alone matched non-R files (a stray .md in R/). Require .R.
#   2. The old sub() left a TRAILING QUOTE on each sourced filename, so
#      "fn_fit_beta.R\"" never matched "fn_fit_beta.R" and every script that
#      genuinely sourced it was reported as broken. regexec() with a capture
#      group returns the filename cleanly.
pipeline <- list.files("R", "^[0-9].*\\.R$", full.names = TRUE)
for (f in pipeline) {
  x <- paste(readLines(f, warn = FALSE), collapse = "\n")
  hits <- regmatches(x, gregexpr('source\\(here::here\\("R",\\s*"[^"]+"', x))[[1]]
  srcd <- vapply(hits, function(h)
    regmatches(h, regexec('"R",\\s*"([^"]+)"?$', h))[[1]][2], character(1),
    USE.NAMES = FALSE)
  srcd <- sub('"$', "", srcd)
  miss <- character(0)
  for (fn in names(shared))
    if (grepl(paste0("\\b", fn, "\\s*\\("), x) && !(shared[[fn]] %in% srcd))
      miss <- c(miss, sprintf("%s() needs %s", fn, shared[[fn]]))
  say(length(miss) == 0, basename(f), paste(miss, collapse = "; "))
}

# =============================================================================
# 6b. STALE FILES
# -----------------------------------------------------------------------------
# Files in R/ that are not part of the current pipeline. RUN_ALL.R sources by
# name so it will not execute them, but they are a hazard for two reasons:
#   * they are scanned by sections 5 and 6, producing failures that point at
#     code nothing runs
#   * an old copy is easy to open and edit by mistake
# Duplicates from a re-download -- "script (1).R" -- are the most common case.
# =============================================================================
cat("\n-- stale files in R/ --\n")
expected <- c("00_config.R", "fn_fit_beta.R", "diag_fpc_truncation.R",
              "01_build_response.R", "02_build_flow.R",
              "03_fit_beta_recruitment.R", "04_fit_beta_survival.R",
              "05_validate.R", "06_daily_sensitivity.R", "06b_decision_window.R",
              "07_production_sensitivity.R", "08_scenarios_bor.R", "09_figures.R")
present <- setdiff(list.files("R"), c("explain", "armB"))
present <- present[!dir.exists(file.path("R", present))]
extra   <- setdiff(present, expected)
if (length(extra)) {
  say(FALSE, sprintf("%d unexpected file(s) in R/", length(extra)), "move or delete")
  for (e in extra) cat("         ", e, "\n", sep = "")
  cat("         These are scanned by the checks above and can produce failures\n")
  cat("         that point at code the pipeline never runs.\n")
} else {
  say(TRUE, "no stale files in R/")
}

# =============================================================================
# 7. DATA INPUTS
# -----------------------------------------------------------------------------
# Reported but NOT fatal -- you may be checking the code on a machine without
# the data folder mounted.
# =============================================================================
cat("\n-- data inputs (informational) --\n")
for (s in SITES) {
  say(file.exists(path_of(posterior_path(s))), paste("posterior:", s),
      if (file.exists(path_of(posterior_path(s)))) "" else path_of(posterior_path(s)))
  say(file.exists(path_of(flow_path(s))), paste("flow:", s),
      if (file.exists(path_of(flow_path(s)))) "" else path_of(flow_path(s)))
  yr <- tryCatch(site_years(s, quiet = TRUE), error = function(e) e)
  if (inherits(yr, "error"))
    say(FALSE, paste("years:", s), conditionMessage(yr))
  else if (is.null(yr))
    say(FALSE, paste("years:", s), "params CSV not found -- add a params_path() branch")
  else
    say(TRUE, paste("years:", s), sprintf("%d-%d (%d years)", min(yr), max(yr), length(yr)))
}

# =============================================================================
cat("\n", strrep("=", 68), "\n", sep = "")
# Braced deliberately. At TOP LEVEL, R parses `if (cond) expr` as a complete
# statement, so an `else` beginning the next line is orphaned and is a syntax
# error. Inside {} it is fine, which is why the `else if` chain in the loop above
# parses. Braces here make the construct correct regardless of position.
if (ok_all) {
  cat("  Everything checks out. Run: source(\"RUN_ALL.R\")\n")
} else {
  cat("  Some checks failed. Data-input failures are fine if the data folder is\n",
      "  not mounted; anything in sections 1-6 must be fixed first.\n", sep = "")
}
cat(strrep("=", 68), "\n\n", sep = "")
