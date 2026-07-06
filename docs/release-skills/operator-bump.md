# /operator-bump

Check and bump component version tags in `tektoncd/operator`'s `components.yaml`. Creates a PR on the operator repo when outdated components are found.

## Prerequisites

- **Claude Code** installed and running
- **`gh`** CLI authenticated with a GitHub account that can fork `tektoncd/operator`
- **`yq`** installed (YAML processor)
- **`git`** configured with `user.name` and `user.email` (your commits will use this identity)

Verify your setup:

```bash
gh auth status          # must be logged in
yq --version            # must be installed
git config user.name    # must return your name
```

## What it does

The skill reads `components.yaml` from a `tektoncd/operator` branch and checks each component's version tag against published GitHub releases. If any component has a newer release available, it offers to create a PR bumping the versions.

Two modes:

| Mode | Invocation | Branch | Resolution |
|------|-----------|--------|------------|
| **Patch** | `/operator-bump 1.21.3` | Release branch from hack config | Latest tag within the same minor series (e.g. `v0.26.2` -> `v0.26.5`) |
| **Latest** | `/operator-bump` | `main` | Absolute latest stable release regardless of minor series |

### Patch mode (with version)

Used as a **prep-step gate** before cutting a release. Looks up the operator's release branch from `openshift-pipelines/hack`'s release config (`config/downstream/releases/{MAJOR_MINOR}.yaml`), then checks each component for newer patch releases within the same minor version.

### Latest mode (without version)

Used to keep the development branch (`main`) current. Checks each component against the absolute latest stable release on its GitHub repo.

## Usage

### Check and bump for a release

```
/operator-bump 1.21.3
```

This will:

1. Fetch the hack release config for `1.21` to find the operator branch (e.g. `release-v0.78.x`)
2. Fetch `components.yaml` from that branch via the GitHub API
3. For each component, check if a newer patch release exists
4. Print a comparison table showing current vs latest versions
5. If any are outdated, ask for confirmation before creating a PR
6. Write a report to `reports/1.21/1.21.3/operator-bump-<timestamp>.md`

### Check main branch

```
/operator-bump
```

Same flow but targets `main` and resolves the absolute latest release per component. Report goes to `reports/operator-bump-main.md`.

## Example output

```
Checking components.yaml on tektoncd/operator branch release-v0.78.x (mode: patch).

## Component Version Check

**Operator branch:** tektoncd/operator @ release-v0.78.x

| Component | GitHub Repo | Current | Latest | Status |
|-----------|-------------|---------|--------|--------|
| chains | tektoncd/chains | v0.26.2 | v0.26.5 | **OUTDATED** |
| dashboard | tektoncd/dashboard | v0.63.1 | v0.63.1 | CURRENT |
| pipeline | tektoncd/pipeline | v1.6.3 | v1.6.4 | **OUTDATED** |
| triggers | tektoncd/triggers | v0.34.0 | v0.34.0 | CURRENT |

The following components will be bumped in components.yaml on release-v0.78.x:

  chains: v0.26.2 -> v0.26.5
  pipeline: v1.6.3 -> v1.6.4

Create a PR on tektoncd/operator to apply these changes?
```

## How the PR is created

When you confirm, the skill:

1. Clones `tektoncd/operator` at the target branch into a temp directory
2. Updates each outdated version in `components.yaml` using `yq`
3. Forks `tektoncd/operator` to your GitHub account (idempotent)
4. Commits with your local git identity and a `Co-authored-by: Claude` trailer
5. Pushes to your fork and opens a cross-fork PR against the upstream branch
6. Cleans up the temp directory

## Report structure

Patch mode reports are written to a nested directory structure:

```
reports/
  1.21/
    1.21.3/
      operator-bump-20260706-143000.md
```

Latest mode reports overwrite a single file: `reports/operator-bump-main.md`.

## Edge cases

- **Component ahead of latest release**: If a component's current version is newer than the latest published release (e.g. a pre-release tag), it is marked `CURRENT (ahead)` and not treated as outdated.
- **No releases found**: Components with no matching releases are marked `UNKNOWN`.
- **User declines PR**: The report is still written, noting "Outdated but declined".
- **All components current**: The skill reports "All components up to date" and skips the PR step.
