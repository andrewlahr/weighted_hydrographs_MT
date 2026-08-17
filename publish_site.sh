#!/usr/bin/env bash
# =============================================================================
# publish_site.sh -- push the rendered site to the gh-pages branch.
#
#     bash publish_site.sh
#
# Run render_site.R first. Safe to re-run, and safe to interrupt: a failed run
# leaves nothing behind that breaks the next one.
#
# HOW IT WORKS
# ------------
# A git WORKTREE: a second checkout of this repository, on the gh-pages branch,
# in a temporary folder. The site is copied there, committed, and pushed. Your
# working directory and `main` are never touched -- no branch switching, nothing
# to go wrong mid-edit.
#
# gh-pages holds ONLY rendered HTML; source stays on main. That separation is why
# the published site can contain figures derived from git-ignored data.
# =============================================================================

set -euo pipefail

BRANCH="gh-pages"
SITE="_site"
TMP=".gh-pages-worktree"

# =============================================================================
# CLEANUP -- runs on EVERY exit, including failure.
# -----------------------------------------------------------------------------
# Without this, a network drop mid-push aborted the script before cleanup and
# left the worktree behind with gh-pages checked out. Git then refuses to check
# the same branch out again, so every subsequent run failed with a message about
# the branch already existing -- which was true, and not the problem.
# =============================================================================
cleanup() {
  if [ -d "$TMP" ]; then
    git worktree remove "$TMP" --force >/dev/null 2>&1 || rm -rf "$TMP"
  fi
  git worktree prune >/dev/null 2>&1 || true
  # the per-run orphan build branch, if it outlived the worktree
  if [ -n "${BUILD:-}" ]; then
    git branch -D "$BUILD" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

command -v git >/dev/null || { echo "ERROR: git not installed."; exit 1; }
[ -d .git ] || { echo "ERROR: not a git repository. Run: bash setup_github.sh"; exit 1; }

if [ ! -f "$SITE/index.html" ]; then
  echo "ERROR: $SITE/index.html not found."
  echo "  Run this first:  Rscript -e 'source(\"render_site.R\")'"
  exit 1
fi

git remote get-url origin >/dev/null 2>&1 || {
  echo "ERROR: no 'origin' remote. Run: bash setup_github.sh"; exit 1; }

echo "=============================================================="
echo "  Publishing $SITE/ to the $BRANCH branch"
echo "=============================================================="

# --- refuse to publish a site whose images are missing ------------------------
MISSING=0
while IFS= read -r img; do
  case "$img" in http*|data:*) continue;; esac
  [ -f "$SITE/$img" ] || MISSING=$((MISSING+1))
done < <(grep -ho 'src="[^"]*\.\(png\|jpg\|jpeg\|gif\|svg\)"' "$SITE"/*.html 2>/dev/null \
         | sed 's/^src="//; s/"$//' | sort -u)

if [ "$MISSING" -gt 0 ]; then
  cat <<MSG
ERROR: $MISSING image(s) referenced by the pages are missing from $SITE/.
  Publishing now would put a site with broken images online, and the local
  preview would still look correct.

  Most likely: 'figures' is listed under 'exclude:' in manuscript/_site.yml,
  which stops the folder being copied into $SITE/. Remove it and re-run:

      Rscript -e 'source("render_site.R")'
MSG
  exit 1
fi

# --- clear anything left by an interrupted run --------------------------------
if [ -d "$TMP" ]; then
  echo "  clearing a worktree left by an earlier run"
  git worktree remove "$TMP" --force >/dev/null 2>&1 || rm -rf "$TMP"
fi
git worktree prune >/dev/null 2>&1 || true

# --- can we reach the remote? -------------------------------------------------
# Checked BEFORE any destructive work, so an offline run stops early rather than
# committing and then failing at the push.
ONLINE=yes
git ls-remote --exit-code --heads origin >/dev/null 2>&1 || ONLINE=no

if [ "$ONLINE" = "no" ]; then
  echo
  echo "ERROR: cannot reach github.com."
  echo "  Nothing has been changed. Check your connection and re-run."
  echo "  Any commit from an earlier interrupted run is safe on the local"
  echo "  '$BRANCH' branch and will be pushed automatically next time."
  exit 1
fi

# =============================================================================
# BUILD gh-pages FRESH: ONE COMMIT, NO ANCESTRY
# -----------------------------------------------------------------------------
# Each publish creates an ORPHAN commit and force-pushes it, so the branch holds
# exactly one commit containing exactly the current site.
#
# WHY, rather than appending to the branch's history:
#
#   * The published site is BUILD OUTPUT. Its history has no value -- the record
#     is the source on `main`, which regenerates it.
#   * A branch that accumulates history also accumulates whatever was ever
#     committed to it. This repository hit exactly that: gh-pages was branched
#     from `main` and inherited a commit containing output/models/*.rds (368 MB,
#     354 MB, 78 MB), so every push was rejected by GitHub's 100 MB limit even
#     though the current tree was only HTML. Deleting the files did not help,
#     because a push sends the ancestry too.
#   * With an orphan commit the branch cannot grow and cannot inherit anything.
#
# This is what static-site deploy tooling does. The force-push is safe here
# because nothing else ever writes to this branch; if that changes, revisit it.
# =============================================================================
BUILD="gh-pages-build-$$"

git worktree add --detach "$TMP" >/dev/null
( cd "$TMP" && git checkout --orphan "$BUILD" >/dev/null 2>&1 && \
  git rm -rf . >/dev/null 2>&1 || true )

find "$TMP" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
cp -R "$SITE"/. "$TMP"/
touch "$TMP/.nojekyll"

# --- refuse to push anything GitHub will reject -------------------------------
# Cheaper to catch here than in a rejected push, and the message names the file.
BIG=$(find "$TMP" -type f -size +45M ! -path "*/.git/*" 2>/dev/null || true)
if [ -n "$BIG" ]; then
  echo
  echo "ERROR: file(s) over 45 MB in the site. GitHub rejects over 100 MB and"
  echo "       warns over 50 MB. These should not be in _site/:"
  echo "$BIG" | sed 's/^/       /'
  exit 1
fi

cd "$TMP"
git add -A
git commit -q -m "Rendered site: $(date -u '+%Y-%m-%d %H:%M UTC')"

if git push -q --force origin "HEAD:$BRANCH"; then
  NEW_SHA=$(git rev-parse HEAD)
  echo "  pushed (single orphan commit, branch history reset)."
else
  cd ..
  cat <<MSG

ERROR: the push failed.

  If GitHub rejected LARGE FILES, they are in this repository's history, not in
  the site. .gitignore does not untrack a file that was already committed. See
  docs/GITHUB_PAGES.md -> "Large files rejected".

  Otherwise it is network or credentials; re-run when that is resolved.
MSG
  exit 1
fi
cd ..

# keep the local branch pointing at what was published, so
#   git log --oneline -1 gh-pages
# still shows the truth
git branch -f "$BRANCH" "$NEW_SHA" >/dev/null 2>&1 || true

URL=$(git remote get-url origin | sed -E 's#(git@|https://)github.com[:/]##; s#\.git$##')
USER=${URL%%/*}; REPO=${URL##*/}

cat <<MSG

--------------------------------------------------------------
  Published.

  https://${USER}.github.io/${REPO}/

  FIRST TIME ONLY -- enable Pages:
    Repository -> Settings -> Pages
    Source: "Deploy from a branch"
    Branch: gh-pages    Folder: / (root)
    Save

  Allow a minute or two for the first build, then hard-refresh
  (Cmd+Shift+R) -- Pages caches aggressively.
--------------------------------------------------------------
MSG