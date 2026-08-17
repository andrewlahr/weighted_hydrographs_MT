# Publishing the results website

Three pages — overview, methods, results — hosted free at
`https://YOUR-USERNAME.github.io/WH_BOR_Trout/`. Collaborators, DOI-WMA, and BoR
read a link instead of running R.

## Why rendering happens on your machine, not on GitHub

The `.Rmd` files read `output/`, which is git-ignored because it holds data-derived
products. A GitHub Actions runner has no data and therefore cannot run the
analysis. So:

```
run the analysis locally  →  render locally  →  publish the HTML
```

That is not a workaround. It keeps data out of the repository while the *rendered
result* is public, which is usually exactly what you want.

## One-time setup

**1.** Version control, if not done already:

```bash
bash setup_github.sh WH_BOR_Trout
```

**2.** Point `_site.yml` at your repository. Edit `manuscript/_site.yml`:

```yaml
      href: https://github.com/YOUR-USERNAME/WH_BOR_Trout
```

**3.** Publish once:

```r
source("render_site.R")
```
```bash
bash publish_site.sh
```

**4.** Turn Pages on. In the browser: **Settings → Pages → Source: "Deploy from a
branch" → Branch: `gh-pages` → folder `/ (root)` → Save.** Once only; it stays on.

Live within a minute or two at
`https://YOUR-USERNAME.github.io/WH_BOR_Trout/`.

## Every time after

```r
source("RUN_ALL.R")      # if the analysis changed
source("render_site.R")
```
```bash
bash publish_site.sh
```

Preview before publishing by opening `_site/index.html` in a browser.

## What `publish_site.sh` does

It uses a **git worktree** to check out the `gh-pages` branch into a temporary
folder, replaces its contents with `_site/`, commits, pushes, and removes the
worktree. Your working files are never touched and `main` never sees the rendered
HTML. It asks for confirmation before pushing.

It also creates `.nojekyll`, without which GitHub Pages strips folders whose names
begin with an underscore — which would silently break every figure.

## Private repository, public site

GitHub Pages on a private repository requires a paid plan. Options:

- **Public repo, no data.** `.gitignore` already excludes every `.csv`, `.rds`, and `.RData`, so code and rendered results are public while data stays local. Check the `setup_github.sh` file listing before your first commit.
- **Keep it private, share the HTML.** Skip Pages; zip `_site/` and send it, or host on institutional web space.
- **Two repositories.** Private for code, public for the rendered site.

## The Actions workflow — pick ONE route, not both

`.github/workflows/deploy-site.yml` is an **alternative** to `publish_site.sh`,
and the two cannot both be active. They use different GitHub Pages *sources*, and
Pages only has one:

| Route | Pages source setting | What you commit |
|---|---|---|
| **`publish_site.sh`** *(recommended)* | Deploy from a branch → `gh-pages` → `/ (root)` | nothing extra; `_site/` stays ignored |
| Actions workflow | **GitHub Actions** | the rendered `_site/` folder on `main` |

If you set the source to `gh-pages` (step 4 above) and *also* leave the workflow
in place, every workflow run fails — Pages is not configured for Actions, and the
`deploy-pages` step errors. The failure is confusing because the site itself keeps
working, published by the script.

**Most people should use `publish_site.sh` and delete
`.github/workflows/deploy-site.yml`.** The workflow is included only because some
institutions require deployments to be auditable in Actions. To switch to it:
remove `_site/` from `.gitignore`, commit the rendered folder, and change the
Pages source to *GitHub Actions*.

Neither route runs R. The `.Rmd` files read `output/`, which is git-ignored
because it holds data-derived products, so a runner has nothing to render from.
Rendering is local by necessity, not preference.

## Large files rejected

```
remote: error: File output/models/beta_recruitment.rds is 368.48 MB;
        this exceeds GitHub's file size limit of 100.00 MB
! [remote rejected] HEAD -> gh-pages (pre-receive hook declined)
```

**`.gitignore` does not untrack a file that was already committed.** Once a blob
is in a commit it stays in history, and a push sends the history — so deleting
the file now changes nothing.

Diagnose:

```bash
git log --oneline --all -- output/models        # which commits touched it
git ls-files output/ | head                     # is it tracked right now?
```

**The site**: fixed automatically. `publish_site.sh` now builds `gh-pages` as a
single orphan commit containing only `_site/`, so it carries no ancestry and
cannot inherit anything.

**The source branch**: needs its history rebuilt. On a young repository whose
history is not worth preserving, squashing to a single clean commit is simplest
and needs no extra tooling:

```bash
git rm -r --cached output              # untrack (files stay on disk)
git checkout --orphan clean-main       # new branch, no parent
git add -A                             # .gitignore now applies
git commit -m "Project source"
git branch -D main
git branch -m main
git push --force origin main
```

If the history *is* worth keeping, use `git filter-repo` instead:

```bash
brew install git-filter-repo
git filter-repo --path output --invert-paths
git push --force origin main
```

Either way, verify before pushing:

```bash
git count-objects -vH | grep size-pack     # should be a few MB
git ls-files | wc -l                       # ~46 files
```

## If something goes wrong

Run `source("diagnose_site.R")` first. It walks the five links of the chain —
scripts write PNGs, `render_site.R` copies them, `render_site()` copies them into
`_site/`, the pages reference them, `.nojekyll` exists — and names the first one
that is broken. It also prints how many figures each page carries, which settles
the most common false alarm: **`index.html` has none by design**, because it is a
text overview. The figures live on `results.html` and
`results_among_sites.html`.

| Problem | Fix |
|---|---|
| `fatal: a branch named 'gh-pages' already exists` | A previous run was interrupted (usually a network drop) and left `.gh-pages-worktree` behind with the branch checked out. The current `publish_site.sh` clears this automatically. To clear it by hand: `git worktree remove .gh-pages-worktree --force && git worktree prune` |
| `Could not resolve host: github.com` | Offline. Any commit from the interrupted run is safe on the local `gh-pages` branch; re-running pushes it. |
| Figures missing on the live site | Two causes. **(1)** `figures` listed under `exclude:` in `manuscript/_site.yml` — that stops the folder being copied into `_site/`, so every image 404s while the *local preview still looks fine*. Remove it and re-render. **(2)** `.nojekyll` absent — re-run `publish_site.sh`, which creates it. |
| Pages shows a 404 | Pages not enabled, or set to the wrong branch. Settings → Pages → `gh-pages`, `/ (root)` |
| Pages shows the README instead of the site | Branch set to `main` instead of `gh-pages` |
| `[PENDING]` all over the pages | `output/` is empty. Run `RUN_ALL.R` first. |
| "worktree already exists" | `git worktree remove --force .gh-pages-wt` then retry |
| Committed a data file by mistake | `git rm --cached path/to/file`, add to `.gitignore`, commit again |

## For the manuscript

PNAS requires a code availability statement. Once the analysis is final, connect
the repository to <https://zenodo.org> and cut a release — Zenodo mints a DOI
pointing at that exact snapshot, which is what goes in the statement.
