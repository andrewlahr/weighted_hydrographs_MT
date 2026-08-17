#!/usr/bin/env bash
# =============================================================================
# setup_github.sh — put this R project under version control and push to GitHub.
#
# Run ONCE, from the top level of your R project (the folder containing the .Rproj
# file):
#
#     bash setup_github.sh
#
# It is safe to re-run: every step checks whether it has already been done.
# It will NOT commit data files, model fits, or figures (see .gitignore).
# =============================================================================

set -euo pipefail

REPO_NAME="${1:-WH}"
BRANCH="main"

echo "=============================================================="
echo "  Setting up git for: $(andrewlahr)"
echo "  Repository name:    ${REPO_NAME}"
echo "=============================================================="
echo

# --- 1. checks ---------------------------------------------------------------
command -v git >/dev/null 2>&1 || {
  echo "ERROR: git is not installed."
  echo "  macOS:   xcode-select --install"
  echo "  Windows: https://git-scm.com/download/win"
  exit 1; }

if [ ! -f .gitignore ]; then
  echo "ERROR: no .gitignore here. Copy the provided one in first."
  echo "Without it you risk committing large data files to GitHub permanently."
  exit 1
fi

# --- 2. identity -------------------------------------------------------------
if ! git config user.email >/dev/null 2>&1; then
  echo "Git needs to know who you are (once per machine):"
  read -rp "  Your name:  " GIT_NAME
  read -rp "  Your email: " GIT_EMAIL
  git config --global user.name  "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
  echo "  set."
fi

# --- 3. init -----------------------------------------------------------------
if [ ! -d .git ]; then
  git init -b "$BRANCH"
  echo "Initialised a git repository."
else
  echo "Already a git repository; leaving it alone."
fi

# --- 4. what would be committed ---------------------------------------------
echo
echo "--------------------------------------------------------------"
echo "  Files that WOULD be committed (data excluded by .gitignore):"
echo "--------------------------------------------------------------"
git add -An . | head -60
N=$(git add -An . | wc -l | tr -d ' ')
echo "  ... ${N} files total"
echo

BIG=$(git add -An . | sed 's/^add .//;s/.$//' | while read -r f; do
        [ -f "$f" ] && [ "$(wc -c < "$f")" -gt 5000000 ] && echo "$f"
      done || true)
if [ -n "$BIG" ]; then
  echo "WARNING -- files over 5 MB. GitHub rejects anything over 100 MB:"
  echo "$BIG"
  echo "Add them to .gitignore before continuing."
  echo
fi

read -rp "Commit these? [y/N] " OK
[[ "$OK" =~ ^[Yy]$ ]] || { echo "Stopped. Edit .gitignore and re-run."; exit 0; }

git add .
git commit -m "Initial commit: weighted hydrograph FPCA analysis pipeline" || echo "Nothing new to commit."

# --- 5. push -----------------------------------------------------------------
echo
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI found and authenticated. Creating the remote repository..."
  gh repo create "$REPO_NAME" --private --source=. --remote=origin --push
  echo
  echo "Done. Repository: $(gh repo view --json url -q .url)"
else
  cat <<'MSG'
GitHub CLI ('gh') not found or not logged in. Two options:

  EASIER -- install the CLI, then re-run this script:
      macOS:   brew install gh && gh auth login
      Windows: winget install GitHub.cli   (then: gh auth login)

  MANUAL -- create the repo in a browser:
      1. Go to https://github.com/new
      2. Name it, set it PRIVATE, and do NOT tick "Add a README"
      3. Copy the URL it gives you, then run:

           git remote add origin https://github.com/YOUR-USERNAME/REPO-NAME.git
           git push -u origin main
MSG
fi

echo
echo "From now on, after a working session:"
echo "    git add -A && git commit -m 'what you changed' && git push"
