# =============================================================================
# manuscript/_common.R -- shared by every page. Sourced, never rendered (the
# leading underscore is what keeps render_site() from publishing it).
#
# Loads the configuration and the model objects ONCE per page, and defines the
# four helpers the pages use. Nothing here does any analysis: if a page needs a
# number that is not in output/, the answer is to run the script that makes it,
# not to compute it here. A figure or table that exists in two places drifts.
# =============================================================================

# Only what the PAGES use. The analysis scripts need more, but a page layer that
# loads a package it never calls fails the whole render on a machine where that
# package happens to be missing -- for nothing.
suppressPackageStartupMessages({ library(knitr); library(dplyr) })

knitr::opts_chunk$set(echo = FALSE, message = FALSE, warning = FALSE,
                      fig.align = "center", out.width = "100%")

# --- configuration ------------------------------------------------------------
# Pages render from manuscript/, and with new_session: true each page starts a
# fresh R session, so the config has to be loaded here rather than inherited.
#
# SOURCED FROM THE PROJECT ROOT, DELIBERATELY. config.R contains relative paths
# that are written to resolve from the root, because that is where you source it
# in the console -- most visibly
#
#     allSections <- read.csv("../LL/ALLSectionsIN.csv")
#
# which is meant to reach the sibling LL/ folder. knitr renders from manuscript/,
# so sourcing it from here turns "../LL" into <project>/LL, which does not
# exist, and the render dies inside read.csv() with "cannot open the connection"
# -- an error that names the CSV and gives no hint that the working directory is
# the problem.
#
# setwd() around the source call, restored in finally, so every relative path in
# the config chain (the sections list, the lag CSVs, anything added later)
# resolves exactly as it does from the console. Nothing else in the render
# depends on the working directory: OUT and path_of() are built from here::here()
# and are absolute.
if (!exists("CFG")) {
  .old_wd <- setwd(here::here())
  tryCatch(suppressMessages(source(here::here("R", "00_config.R"))),
           finally = setwd(.old_wd))
}

ROOT <- here::here()
MOD  <- file.path(ROOT, "output", "models")
TAB  <- file.path(ROOT, "output", "tables")

# --- model objects, or NULL --------------------------------------------------
# Every page is written to degrade: a missing input renders a labelled
# NOT AVAILABLE, never an error. A half-built site that says which half is
# missing is useful; one that fails to build tells the reader nothing.
rd <- function(f) { p <- file.path(MOD, f); if (file.exists(p)) readRDS(p) else NULL }

RESP <- rd("response.rds")
FLOW <- rd("flow.rds")
BR   <- rd("beta_recruitment.rds")
BS   <- rd("beta_survival.rds")
GT   <- rd("gate.rds")
SE   <- rd("sensitivity.rds")
DW   <- rd("decision_window.rds")
PR   <- rd("production.rds")
GATE <- GT$gate                                  # NULL if 05 has not run

# per-site objects (08 and 10 write one file per site)
SCEN <- function(site) if (exists("scenarios_file")) rd(basename(scenarios_file(site))) else NULL
RULE <- function(site) if (exists("rulecurve_file")) rd(basename(rulecurve_file(site))) else NULL

`%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a

# --- V(): format a number for prose ------------------------------------------
# One formatter, so the same quantity is never shown to two decimals in one
# sentence and four in the next.
V <- function(x, d = 2) {
  if (is.null(x) || !length(x)) return("_not available_")
  if (is.numeric(x)) formatC(x, digits = d, format = "f", big.mark = ",") else as.character(x)
}
PCT <- function(x, d = 1) if (is.null(x) || !length(x)) "_not available_" else
  paste0(formatC(x, digits = d, format = "f"), "%")

# --- NA_(): the one way a page reports a missing input -----------------------
# Always says WHICH script would produce it. "NOT AVAILABLE" on its own sends
# the reader to ask, and the answer is always the same sentence.
NA_ <- function(what, script) knitr::asis_output(sprintf(
  "\n> **NOT AVAILABLE** - %s. Run `%s` to produce it.\n\n", what, script))

# --- FIG(): insert a figure, per site ----------------------------------------
# save_fig() writes <name>__<site slug>.png for any figure whose plot data
# carries a `site` column, and <name>.png for the all-sites version. That is the
# convention FIG() expects.
#
# Several scripts still bake the site into the figure NAME instead
# (02: "02_f2a_Madison.Norris", 10: "10_a_Madison_Norris", 01: "01_f1aMadison.Norris"),
# which produces a file the template would never find. Rather than let those
# render as gaps, FIG() tries each spelling and reports which it used via
# attr(, "found"). The real fix is upstream -- put `site` on the plot data and
# drop it from the name -- and FIG_AUDIT() below lists what is still wrong.
FIG_DIR <- "figures"
fig_candidates <- function(name, site) {
  if (is.null(site)) return(paste0(name, ".png"))
  slug <- gsub("[^A-Za-z0-9]", "_", site)
  c(paste0(name, "__", slug, ".png"),   # save_fig(), the convention
    paste0(name, "_",  site, ".png"),   # 08-style legacy
    paste0(name, "_",  slug, ".png"),   # 02/10-style legacy
    paste0(name,       site, ".png"),   # 01-style legacy (no separator)
    paste0(name, ".png"))               # all-sites fallback
}
FIG <- function(name, site = NULL, caption = NULL) {
  hit <- Filter(function(f) file.exists(file.path(FIG_DIR, f)), fig_candidates(name, site))
  if (!length(hit)) return(knitr::asis_output(sprintf(
    "\n> **FIGURE NOT AVAILABLE** - `%s` was not produced for this site.\n\n", name)))
  knitr::asis_output(sprintf("\n![%s](%s/%s)\n\n", caption %||% "", FIG_DIR, hit[1]))
}
FIG_AUDIT <- function(names, site) {
  data.frame(figure = names,
             file = vapply(names, function(n) {
               hit <- Filter(function(f) file.exists(file.path(FIG_DIR, f)),
                             fig_candidates(n, site))
               if (length(hit)) hit[1] else "MISSING" }, character(1)),
             row.names = NULL)
}

# --- GATE_BOX(): the warrant that travels with every number ------------------
# The gate decides whether a daily claim is a finding or arithmetic. Every page
# that shows a daily number calls this first, so the reader never has to go
# looking for it.
gate_rows <- function(site, process = NULL) {
  if (is.null(GATE)) return(NULL)
  g <- GATE[GATE$site == site & grepl("^beta", GATE$form), , drop = FALSE]
  if (!is.null(process)) g <- g[g$process == process, , drop = FALSE]
  g
}
gate_passed <- function(site, process = NULL) {
  g <- gate_rows(site, process)
  !is.null(g) && nrow(g) > 0 && all(g$passes, na.rm = TRUE)
}
GATE_BOX <- function(site, process = NULL) {
  g <- gate_rows(site, process)
  if (is.null(g) || !nrow(g))
    return(knitr::asis_output(paste0(
      "\n> **NO GATE ROW.** Validation has not been run for this site, so nothing\n",
      "> below has a warrant. Run `R/05_validate.R`.\n\n")))
  ok <- all(g$passes, na.rm = TRUE)
  txt <- if (ok)
    sprintf(paste0("\n> **Validated.** Blocked CV R-squared %s, permutation p %s",
                   " (finest resolvable p here is %s).\n",
                   "> The daily structure below predicts years the model did not see.\n\n"),
            V(max(g$r2_blocked), 3), V(min(g$p_value), 3), V(min(g$finest_p), 3))
  else
    sprintf(paste0("\n> **NOT VALIDATED.** Blocked CV R-squared %s, permutation p %s.\n",
                   "> Everything below is arithmetic, not a finding. Do not brief it.\n",
                   "> A site where the record cannot resolve a daily signal is a result\n",
                   "> about Montana flow records, not a failure of the analysis.\n\n"),
            V(max(g$r2_blocked), 3), V(min(g$p_value), 3))
  knitr::asis_output(txt)
}

# --- TBL(): one table style --------------------------------------------------
TBL <- function(x, caption = NULL, digits = 3) {
  if (is.null(x) || !nrow(x)) return(NA_("no rows to show", "the script above"))
  knitr::kable(x, caption = caption, digits = digits, row.names = FALSE)
}

MON_B <- c(1, 32, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335)
MON_L <- c("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec")
