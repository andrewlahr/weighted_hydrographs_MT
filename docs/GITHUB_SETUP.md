# Putting this project on GitHub

Written for someone who has not used git before. Fifteen minutes, once.

## Why bother

Three reasons that matter for this project specifically:

1. **You can undo anything.** Every version of every script is recoverable. This is what makes a big clean-up safe — if a simplification turns out to be wrong, you go back.
2. **The manuscript needs it.** PNAS requires a code availability statement. "Archived at github.com/..., DOI 10.5281/zenodo..." satisfies it.
3. **Collaborators stop emailing scripts.** The repository is the authoritative copy.

## Step by step

### 1. Install git

- **macOS:** open Terminal, type `git --version`. If it isn't installed you'll get a prompt to install it. Accept.
- **Windows:** download from <https://git-scm.com/download/win>, run the installer, accept all defaults.

Check: `git --version` should print a version number.

### 2. Make a GitHub account

<https://github.com/join>. Free. Use your work email if the repository will be
institutional.

### 3. Copy two files into your project

Put `setup_github.sh` and `.gitignore` at the **top level** of your R project —
the folder with the `.Rproj` file in it, not inside `R/`.

### 4. Read the .gitignore before running anything

This is the step worth slowing down for. The file decides what gets uploaded.
As written, it **excludes all `.csv`, `.rds`, and `.RData` files**, because your
data folders are large and some fish data may be restricted.

**Anything committed to git stays in the history forever**, even if you delete it
later. Getting it wrong is a pain to fix. Getting it right takes two minutes.

The test: *if I deleted this file, could I regenerate it by re-running the
pipeline?* If yes, ignore it.

### 5. Run the setup script

In RStudio, go to the **Terminal** tab (next to Console), and:

```bash
bash setup_github.sh
```

It will show you what it's about to commit and wait for you to confirm. Look at
that list. If a data file appears, answer `N`, add it to `.gitignore`, re-run.

### 6. Push

If you have the GitHub CLI installed, the script does this for you. If not it
prints the two commands to run. Installing the CLI is worth it:

```bash
brew install gh && gh auth login     # macOS
winget install GitHub.cli            # Windows, then: gh auth login
```

## Day-to-day use

After a working session, three commands:

```bash
git add -A
git commit -m "Added seasonal window estimator; fixed beta band labels"
git push
```

Or use RStudio's **Git** pane (appears once the repo exists): tick the files,
click Commit, write a message, click Push. Same thing with buttons.

**Write real commit messages.** "Updated stuff" is worthless in six months.
"Fixed beta(t) band labels from 80% to 95%" tells you exactly what changed.

## Recommended repository structure

```
weighted-hydrographs-fpca/
├── .gitignore
├── README.md                 <- what this is, how to run it
├── PROJECT_LOG.md            <- decisions and changes
├── weighted-hydrographs.Rproj
├── R/
│   ├── 00_config.R
│   ├── 01_...  02_...
│   └── explain/              <- the teaching figures
├── docs/
│   ├── 00_SCRIPT_MAP.md
│   ├── PROPOSAL_01_...md
│   └── daily/                <- one file per working session
├── manuscript/
│   ├── methods_PNAS.Rmd
│   └── RESULTS.Rmd
├── data/                     <- IGNORED by git
└── output/                   <- IGNORED by git
```

## Two things worth knowing early

**Branches.** Before a big change, `git checkout -b try-new-framework`. Work
there; if it fails, `git checkout main` and the old version is untouched. This is
the right tool for testing Proposal 01 without risking the current pipeline.

**Zenodo.** When the manuscript is ready, connect the repo to
<https://zenodo.org> and cut a release. Zenodo mints a DOI that points at that
exact snapshot. That is what goes in the code availability statement.

## If something goes wrong

| Problem | Fix |
|---|---|
| Committed a big data file | `git rm --cached path/to/file`, add to `.gitignore`, commit again |
| Want to undo the last commit but keep the edits | `git reset --soft HEAD~1` |
| Want to discard local edits to one file | `git checkout -- path/to/file` |
| "rejected — non-fast-forward" on push | `git pull --rebase` then push |
| Truly stuck | Copy the whole folder somewhere safe, then experiment freely |

That last one is not a joke. A folder copy costs nothing and removes all fear from
learning git.
