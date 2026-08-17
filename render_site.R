# =============================================================================
# render_site.R -- build the results website from manuscript/*.Rmd
#
#     source("render_site.R")
#
# Renders every page into _site/ at the project root. Open _site/index.html in a
# browser to preview before publishing.
#
# WHY RENDERING IS LOCAL, NOT ON GITHUB
# -------------------------------------
# The .Rmd files read from output/, which is git-ignored because it contains
# data-derived products. GitHub Actions checks out the repository and would find
# no output/ folder, so it could not render anything. Rendering locally, where
# the data lives, and publishing the resulting HTML is the correct architecture
# for this project -- not a workaround.
#
# ORDER OF OPERATIONS
#   1. source("RUN_ALL.R")     produces output/
#   2. source("render_site.R") produces _site/
#   3. bash publish_site.sh    pushes _site/ to the gh-pages branch
# =============================================================================

if (!requireNamespace("rmarkdown", quietly = TRUE))
  stop("install.packages('rmarkdown')")

root <- normalizePath(".", mustWork = TRUE)
if (!file.exists(file.path(root, "config.R")))
  stop("Run this from the project root (the folder containing config.R).")

# --- warn, but do not stop, if the analysis has not been run -----------------
# The pages are written to degrade gracefully: missing inputs render as
# NOT AVAILABLE rather than failing. So a partial site is useful, and being able
# to build one before the analysis finishes is deliberate.
# Every model object a page reads. Kept in sync with manuscript/_common.R -- if a
# script starts saving something new that a page consumes, add it here so a
# partial render is reported rather than silently producing NOT AVAILABLE panels.
missing <- setdiff(
  c("beta_recruitment.rds", "beta_survival.rds", "gate.rds", "sensitivity.rds",
    "decision_window.rds", "production.rds", "scenarios.rds", "response.rds"),
  list.files(file.path(root, "output", "models")))

# rulecurve.rds is reported separately: that arm is optional and its absence is
# not a partial render, it is a choice not to run it.
if (!file.exists(file.path(root, "output", "models", "rulecurve.rds")))
  message("\n  NOTE: rulecurve.rds absent -- section 4b will show NOT AVAILABLE.",
          "\n  Run R/10_rulecurve.R if that arm is in scope for this site.")
if (length(missing)) {
  message("\n  NOTE: output/models/ is missing: ", paste(missing, collapse = ", "))
  message("  Those sections will render as NOT AVAILABLE. Run RUN_ALL.R for a full site.\n")
}

# =============================================================================
# GUARD: is _site.yml excluding the figures directory?
# -----------------------------------------------------------------------------
# `exclude:` governs what render_site() COPIES into the output directory, not
# merely what it renders as a page. An entry for `figures` therefore stops
# manuscript/figures/ ever reaching _site/figures/, and every image 404s on the
# published site while the LOCAL preview still looks correct.
#
# Checked by text scan rather than a yaml parse: no extra dependency, and it
# catches the entry however it is written.
# =============================================================================
yml <- file.path(root, "manuscript", "_site.yml")
if (file.exists(yml)) {
  yl <- readLines(yml, warn = FALSE)
  ex_start <- grep("^\\s*exclude\\s*:", yl)
  if (length(ex_start)) {
    blk <- yl[(ex_start[1] + 1):length(yl)]
    blk <- blk[seq_len(max(0, which(!grepl("^\\s*-", blk))[1] - 1))]
    if (any(grepl('["\']?figures/?["\']?\\s*$', sub("^\\s*-\\s*", "", blk)))) {
      message("\n", strrep("=", 66))
      message("  manuscript/_site.yml EXCLUDES `figures`.")
      message(strrep("=", 66))
      message("  That stops manuscript/figures/ being copied into _site/, so every")
      message("  image will 404 once published -- while the local preview looks fine.")
      message("\n  Remove the `- \"figures\"` line from the exclude: block and re-run.\n")
      stop("figures excluded in _site.yml; nothing rendered.", call. = FALSE)
    }
  }
}

# =============================================================================
# CLEAN THE OUTPUT DIRECTORY
# -----------------------------------------------------------------------------
# render_site() does NOT remove stale output. A page that was renamed, or a
# document that used to be rendered and is now excluded, lingers in _site/ and
# gets published forever. (This is how GITHUB_PAGES.html survived after *.md was
# excluded.) Rebuilding from empty is the only way to be sure the published site
# matches the source.
# =============================================================================
site <- file.path(root, "_site")
if (dir.exists(site)) {
  old <- list.files(site, full.names = TRUE, all.files = TRUE, no.. = TRUE)
  unlink(old, recursive = TRUE, force = TRUE)
  message("  cleaned _site/ (", length(old), " item(s) removed)")
}

# =============================================================================
# GENERATE ONE PAGE PER SITE, PLUS A HUB
# -----------------------------------------------------------------------------
# With 14 sites, putting every site on one page means ~300 figures loading at
# once, and faceted panels too small to read. One page per site gives a real URL
# you can send to a collaborator, and only the site you are looking at loads.
#
# Each generated wrapper is three lines: set SITE_FOCUS, pull in
# _site_template.Rmd as a child. The wrappers are disposable and git-ignored --
# edit _site_template.Rmd, never these.
#
# Site names contain dots (Madison.Norris), so filenames use a sanitised form.
# =============================================================================
safe <- function(x) gsub("[^A-Za-z0-9]", "_", x)
sites <- CFG$sites$active

# clear last run's wrappers so a removed site does not linger as a page
old_wrap <- list.files(file.path(root, "manuscript"), "^site_.*[.]Rmd$", full.names = TRUE)
if (length(old_wrap)) unlink(old_wrap)

for (st in sites) {
  writeLines(c(
    "---",
    sprintf('title: "%s"', st),
    'subtitle: "Daily flow effects, scenarios, and equilibrium"',
    "---",
    "",
    "```{r include=FALSE}",
    sprintf('SITE_FOCUS <- "%s"', st),
    "```",
    "",
    '```{r child = "_site_template.Rmd"}',
    "```"),
    file.path(root, "manuscript", paste0("site_", safe(st), ".Rmd")))
}
message("  generated ", length(sites), " per-site page(s)")

# --- the hub: where the navbar's "Results" points ----------------------------
hub <- c(
  "---",
  'title: "Results"',
  'subtitle: "Choose a site"',
  "---",
  "",
  "```{r setup, include=FALSE}",
  'source("_common.R")',
  "```",
  "",
  "```{r hub, results='asis'}",
  "sites <- CFG$sites$active",
  "safe  <- function(x) gsub('[^A-Za-z0-9]', '_', x)",
  "",
  "# Gate status per site, so the hub is a summary rather than just a menu.",
  "tb <- data.frame(Site = sprintf('[%s](site_%s.html)', sites, safe(sites)),",
  "                 stringsAsFactors = FALSE)",
  "if (!is.null(GATE)) {",
  "  g <- GATE[startsWith(GATE$form, 'beta') & GATE$process == 'recruitment', ]",
  "  tb$`Blocked CV R2` <- vapply(sites, function(s) {",
  "    v <- g$r2_blocked[g$site == s]; if (length(v)) V(v[1]) else '_not run_' },",
  "    character(1))",
  "  tb$`Permutation p` <- vapply(sites, function(s) {",
  "    v <- g$p_value[g$site == s]; if (length(v)) V(v[1]) else '_not run_' },",
  "    character(1))",
  "  tb$Gate <- vapply(sites, function(s) {",
  "    v <- g$passes[g$site == s]",
  "    if (!length(v)) '_not run_' else if (all(v)) 'supported' else '**not supported**' },",
  "    character(1))",
  "}",
  "kable(tb, caption = 'One page per site. Recruitment gate shown; see each page for survival.')",
  "```",
  "",
  "Each site page carries a selector so you can move between sites directly.",
  "",
  "The cross-site synthesis — what the daily curves say about brown trout",
  "population ecology across Montana — is on the",
  "**[Among sites](results_among_sites.html)** page.")
writeLines(hub, file.path(root, "manuscript", "results.Rmd"))

# --- copy figures where the pages expect them --------------------------------
fig_src <- file.path(root, "output", "figures")
fig_dst <- file.path(root, "manuscript", "figures")
dir.create(fig_dst, showWarnings = FALSE, recursive = TRUE)
if (dir.exists(fig_src)) {
  pngs <- list.files(fig_src, "\\.png$", full.names = TRUE)
  if (length(pngs)) file.copy(pngs, fig_dst, overwrite = TRUE)
  message("  copied ", length(pngs), " figures into manuscript/figures/")
}

# =============================================================================
# STALE-FILE GUARD
# -----------------------------------------------------------------------------
# render_site.R is the command people reach for, so the check belongs here as
# well as in check_setup.R. A stale .Rmd fails deep inside knitr with a
# "could not find function" traceback that points at dplyr rather than at the
# file, and only after several minutes of rendering. Catching it first costs
# nothing and names the file and line.
# =============================================================================
RETIRED <- c("wday_date", "wday_month", "WY_B", "WY_L", "WY_BREAKS", "WY_LABELS",
             "WY_START", "water_year", "flow_water_year", "spawn_water_year",
             "lo_wday", "hi_wday", "median_wday", "BR\\$sites", "BS\\$sites",
             "beta_mean", "config.yml", "site_file")
stale <- list()
for (f in list.files(file.path(root, "manuscript"), "\\.(Rmd|R)$", full.names = TRUE)) {
  ln <- readLines(f, warn = FALSE)
  for (sym in RETIRED) {
    hit <- grep(sym, ln, perl = TRUE)
    if (length(hit))
      stale[[length(stale) + 1]] <- sprintf("    %s:%d  uses retired `%s`",
                                            basename(f), hit[1], gsub("\\\\", "", sym))
  }
}
if (length(stale)) {
  message("\n", strrep("=", 66))
  message("  STALE FILE(S) IN manuscript/ — not rendering.")
  message(strrep("=", 66))
  for (x in stale) message(x)
  message("\n  These are older copies. Replace them from the repository.")
  message("  Rendering now would fail deep inside knitr with a traceback that")
  message("  points at dplyr rather than at the file.\n")
  stop("stale manuscript files; nothing rendered.", call. = FALSE)
}

# =============================================================================
# GUARD: stray documents in manuscript/ BECOME PUBLISHED PAGES
# -----------------------------------------------------------------------------
# render_site() renders every .Rmd and .md in the directory that does not begin
# with an underscore. `exclude:` in _site.yml does NOT prevent this -- it governs
# which files are COPIED as site resources, not which are rendered as pages.
#
# So a note copied into manuscript/ is published, appears in no navbar, and is
# reachable by anyone who guesses the URL. Internal documentation ending up on a
# public site is the kind of mistake that is embarrassing rather than merely
# broken, so this stops rather than warns.
# =============================================================================
# Hand-written pages, plus the generated ones (results.Rmd and site_*.Rmd).
# _site_template.Rmd begins with "_" and render_site() skips it automatically.
PAGES <- c("index.Rmd", "methods.Rmd", "results.Rmd", "results_among_sites.Rmd")
found <- basename(list.files(file.path(root, "manuscript"), "[.](Rmd|md)$"))

# A stray is a file render_site() WOULD render and should not. Two things are
# legitimately present and must not be flagged:
#   ^_   render_site() skips these outright -- that is how _site_template.Rmd
#        and _common.R stay out of the site. (An earlier version of this guard
#        omitted this test and flagged its own template.)
#   site_*.Rmd   generated wrappers, written a few lines above.
found <- found[!grepl("^_", found)]
strays <- setdiff(found[!grepl("^site_.*[.]Rmd$", found)], PAGES)
if (length(strays)) {
  message("\n", strrep("=", 66))
  message("  ", length(strays), " FILE(S) IN manuscript/ WOULD BE PUBLISHED AS PAGES")
  message(strrep("=", 66))
  for (x in strays) message("    ", x)
  message("\n  render_site() renders every .Rmd/.md that does not start with \"_\".")
  message("  `exclude:` in _site.yml does NOT stop this -- it only controls which")
  message("  files are copied as resources.")
  # Name the specific fix where it is known, rather than offering three generic
  # options for a file whose fate is not ambiguous.
  if ("results_by_site.Rmd" %in% strays)
    message("\n  results_by_site.Rmd was REPLACED by _site_template.Rmd, which is now\n",
            "  rendered once per site by the generator above. Delete it:\n",
            "      rm manuscript/results_by_site.Rmd")
  other <- setdiff(strays, "results_by_site.Rmd")
  if (length(other)) {
    message("\n  For ", paste(other, collapse = ", "), ", pick one:")
    message("    * delete it   -- documentation belongs in docs/")
    message("    * move it     -- mv manuscript/X.md docs/")
    message("    * hide it     -- rename to _X.md, which render_site() skips")
  }
  message("")
  stop("stray page(s) in manuscript/; nothing rendered.", call. = FALSE)
}

message("\n  rendering ...")
rmarkdown::render_site(input = file.path(root, "manuscript"))

# Pages serves through Jekyll by default, which ignores folders starting with an
# underscore -- which would silently drop every figure. .nojekyll turns that off.
file.create(file.path(site, ".nojekyll"))

# =============================================================================
# POST-RENDER: DOES EVERY IMAGE THE PAGES REFERENCE ACTUALLY EXIST IN _site/ ?
# -----------------------------------------------------------------------------
# This is the check that would have caught an `exclude: figures` entry in
# _site.yml. That entry stops manuscript/figures/ being copied into _site/, and
# the result is invisible locally -- the preview resolves images against
# manuscript/figures/, which still exists -- but every image 404s once published.
#
# A broken image on a live site is worse than a build error: nothing fails, and
# the person who notices is usually a reader rather than the author.
# =============================================================================
# Pattern kept in a variable, and quoting kept uniform, so the line stays legible
# and greppable. Captures src="...png" and friends.
img_pat <- "src=\"[^\"]+[.](png|jpg|jpeg|gif|svg)\""
scan_imgs <- function(h) {
  x <- paste(readLines(h, warn = FALSE), collapse = " ")
  m <- regmatches(x, gregexpr(img_pat, x))[[1]]
  gsub("^src=\"|\"$", "", m)
}
img_src <- unique(unlist(lapply(
  list.files(site, "[.]html$", full.names = TRUE), scan_imgs)))
img_src <- img_src[!grepl("^(https?:|data:)", img_src)]   # external / inline are fine

broken <- img_src[!file.exists(file.path(site, img_src))]
if (length(broken)) {
  message("\n", strrep("=", 66))
  message("  ", length(broken), " IMAGE(S) REFERENCED BUT NOT PRESENT IN _site/")
  message(strrep("=", 66))
  for (b in head(broken, 12)) message("    ", b)
  if (length(broken) > 12) message("    ... and ", length(broken) - 12, " more")
  message("\n  Most likely cause: `figures` is listed under `exclude:` in")
  message("  manuscript/_site.yml. That stops the folder being copied into _site/.")
  message("  Remove it, re-run render_site.R, and check again.")
  message("  DO NOT PUBLISH until this is clear -- the local preview will look fine.\n")
} else if (length(img_src)) {
  message(sprintf("\n  all %d referenced image(s) present in _site/", length(img_src)))
}

pages <- list.files(site, "\\.html$")
message("\n", strrep("=", 66))
message("  built ", length(pages), " pages in _site/")
for (p in pages) message("    ", p)
message("\n  PREVIEW:  open _site/index.html in a browser")
message("  PUBLISH:  bash publish_site.sh")
message(strrep("=", 66), "\n")
