---
description: Check and bump component versions in tektoncd/operator components.yaml
---

# Operator Bump

<objective>
Check `tektoncd/operator`'s `components.yaml` for outdated component version tags and optionally create a PR to bump them. Supports two modes:

1. **With version** (`/operator-bump 1.21.3`): Targets the operator release branch from the hack release config. Uses **patch** mode — resolves the latest tag within the same minor version series (e.g. `v0.26.2` → `v0.26.5`). This is a **prep-step gate** for the `/release` orchestrator.

2. **Without version** (`/operator-bump`): Targets the `main` branch. Uses **latest** mode — resolves the absolute latest release for each component regardless of minor series (e.g. `v0.26.2` → `v0.27.0`). Useful for keeping the development branch current.

**External systems:**
- GitHub: `gh` CLI (authenticated via local credentials)

**Tools required:**
- `gh` — GitHub CLI (authenticated)
- `yq` — YAML processor
- `git` — for clone/commit/push

**Formatting rules** (apply everywhere — report and conversation output):
- **PR links:** Always render PR numbers as markdown links: `[#NUMBER](https://github.com/OWNER/REPO/pull/NUMBER)`.
- **Timestamps:** All timestamps must be absolute local time with timezone (e.g. `2026-07-06 14:30 IST`). Never use relative times.
</objective>

<process>
<step name="setup">
**Parse arguments, initialize, and resolve the operator branch and resolution mode.**

Set up time formatting:
```bash
TZ_FMT='%Y-%m-%d %H:%M %Z'
```

Check if a version argument was provided:

**With version** (e.g. `/operator-bump 1.21.3`):

Parse the version argument. It must match `X.Y.Z` (e.g. `1.21.3`).

Derive:
- `VERSION` — e.g. `1.21.3`
- `MAJOR_MINOR` — e.g. `1.21`

Fetch the hack release config and extract the operator branch:
```bash
RELEASE_CFG=$(gh api repos/openshift-pipelines/hack/contents/config/downstream/releases/${MAJOR_MINOR}.yaml \
  --jq '.content' | base64 -d)
OPERATOR_BRANCH=$(echo "$RELEASE_CFG" | yq e '.branches.operator.upstream')
```

If the release config doesn't exist, stop: "Release config for ${MAJOR_MINOR} not found in hack repo."
If `OPERATOR_BRANCH` is empty or `null`, stop: "Operator branch not found in hack release config for ${MAJOR_MINOR}."

Set `MODE=patch` — resolve latest within the same minor series.

**Without version** (`/operator-bump`):
- Set `OPERATOR_BRANCH=main`
- Set `MODE=latest` — resolve the absolute latest release for each component.
- Set `VERSION=main` (used in report filenames and PR titles).

Report: "Checking components.yaml on tektoncd/operator branch ${OPERATOR_BRANCH} (mode: ${MODE})."
</step>

<step name="check">
**Fetch components.yaml via API and compare each component's version against the latest release.**

### Fetch components.yaml

```bash
COMPONENTS_YAML=$(gh api repos/tektoncd/operator/contents/components.yaml?ref=${OPERATOR_BRANCH} \
  --jq '.content' 2>/dev/null | base64 -d)
```

If the API call fails (branch or file doesn't exist), stop: "Could not fetch components.yaml from tektoncd/operator branch ${OPERATOR_BRANCH}."

### Parse all components once

```bash
COMPONENTS=$(echo "$COMPONENTS_YAML" | yq e '[keys[] as $k | {"name": $k, "github": .[$k].github, "version": .[$k].version}] | .[] | [.name, .github, .version] | @tsv' -)
```

### Resolve latest versions

For each component, resolve the latest version using the mode determined in setup:

```bash
while IFS=$'\t' read -r component github_repo current_version; do
  if [[ -z "$github_repo" || "$github_repo" == "null" ]]; then
    continue
  fi

  new_version=""
  if [[ "$MODE" == "latest" ]]; then
    new_version=$(gh release view --repo "$github_repo" --json tagName -q .tagName 2>/dev/null)
  else
    # Latest within same minor series (for release branches)
    minor_prefix="${current_version%.*}"
    escaped_minor="${minor_prefix//./\\.}"
    new_version=$(gh release list --repo "$github_repo" --limit 20 --exclude-pre-releases \
      --json tagName --jq '.[].tagName' 2>/dev/null \
      | grep "^${escaped_minor}\.[0-9]\+$" | sort -V | tail -1)
  fi

  if [[ -z "$new_version" ]]; then
    echo "  $component: $current_version → UNKNOWN (no releases found)"
  elif [[ "$new_version" == "$current_version" ]]; then
    echo "  $component: $current_version (up to date)"
  else
    highest=$(printf '%s\n%s\n' "$current_version" "$new_version" | sort -V | tail -1)
    if [[ "$highest" == "$new_version" ]]; then
      echo "  $component: $current_version → $new_version  OUTDATED"
    else
      echo "  $component: $current_version (up to date, ahead of latest release $new_version)"
    fi
  fi
done <<< "$COMPONENTS"
```

### Present results

Print a comparison table to the conversation:

```markdown
## Component Version Check

**Operator branch:** tektoncd/operator @ ${OPERATOR_BRANCH}

| Component | GitHub Repo | Current | Latest | Status |
|-----------|-------------|---------|--------|--------|
| chains | tektoncd/chains | v0.26.2 | v0.26.5 | **OUTDATED** |
| pipeline | tektoncd/pipeline | v1.6.3 | v1.6.3 | CURRENT |
```

If a component has no matching releases, mark it as `UNKNOWN` and note the reason. If a component's current version is ahead of the latest published release (e.g. a pre-release tag), mark it as `CURRENT (ahead)` — do not treat this as outdated.

If **all components are CURRENT**: print "All components in components.yaml are up to date." and skip to the report step.

If **any components are OUTDATED**: list them with their version changes and proceed to the execute step.
</step>

<step name="execute">
**Clone the operator repo and create a PR to bump outdated component versions.**

This step only runs if outdated components were found in the check step. Before executing, present the planned changes and ask the user for confirmation:

```
The following components will be bumped in components.yaml on ${OPERATOR_BRANCH}:

  chains: v0.26.2 → v0.26.5
  results: v0.17.2 → v0.17.3

Create a PR on tektoncd/operator to apply these changes?
```

If the user declines, skip to the report step.

### Check for existing PR

Before cloning, check if an open PR already exists that bumps components on this branch:

```bash
FORK_USER=$(gh api user --jq .login)
EXISTING_PR=$(gh pr list --repo tektoncd/operator --base "$OPERATOR_BRANCH" \
  --search "bump component versions" --state open --json number,url,author \
  --jq '.[] | select(.author.login != "") | [.number, .url, .author.login] | @tsv' 2>/dev/null | head -1)
```

If an existing PR is found:

- **Author is the current user** (`$FORK_USER`): Ask the user how to proceed with three options:
  1. **Update PR (commit + description)** — push new commits and update the PR body.
  2. **Update description only** — update the PR body without pushing new commits. Skip clone/commit/push entirely; go straight to `gh pr edit`.
  3. **Skip** — proceed to the report step without changes.
- **Author is someone else**: Skip PR creation. Report: "Existing PR [#NUMBER](URL) by @AUTHOR already targets ${OPERATOR_BRANCH} — skipping." Proceed to the report step with this information.

### Clone operator repo

```bash
WORK_DIR=$(mktemp -d)
gh repo clone tektoncd/operator "$WORK_DIR/operator" -- --branch "$OPERATOR_BRANCH" --depth 1
COMPONENTS_FILE="$WORK_DIR/operator/components.yaml"
```

If the clone fails, clean up and stop: "Could not clone tektoncd/operator branch ${OPERATOR_BRANCH}."

### Update components.yaml

For each outdated component, update the version using `yq`:
```bash
yq -i e ".${component}.version = \"${new_version}\"" "$COMPONENTS_FILE"
```

Verify the diff looks correct:
```bash
git -C "$WORK_DIR/operator" diff components.yaml
```

If `git diff --quiet` (no changes), something went wrong — stop and report.

Show the diff to the user.

### Fork, commit, and push

Use the local user's git identity (the release captain running the skill) with a Co-authored-by trailer for Claude:

```bash
gh repo fork tektoncd/operator --clone=false 2>/dev/null || true

# Resolve the actual fork repo name (may differ from upstream, e.g. "tekton-operator" vs "operator")
FORK_REPO=$(gh api repos/tektoncd/operator/forks --jq ".[] | select(.owner.login == \"${FORK_USER}\") | .name")
if [[ -z "$FORK_REPO" ]]; then
  echo "ERROR: Could not find fork of tektoncd/operator for user ${FORK_USER}."
  rm -rf "$WORK_DIR"
  exit 1
fi

git -C "$WORK_DIR/operator" config user.name "$(git config user.name)"
git -C "$WORK_DIR/operator" config user.email "$(git config user.email)"
git -C "$WORK_DIR/operator" remote add fork "git@github.com:${FORK_USER}/${FORK_REPO}.git"
```

**If updating an existing PR (commit + description)**:

```bash
# Check out the existing PR's head branch
EXISTING_HEAD=$(gh pr view "$EXISTING_PR_NUMBER" --repo tektoncd/operator --json headRefName -q .headRefName)
git -C "$WORK_DIR/operator" fetch fork "$EXISTING_HEAD"
git -C "$WORK_DIR/operator" checkout -b "$EXISTING_HEAD" "fork/$EXISTING_HEAD"
git -C "$WORK_DIR/operator" add components.yaml
git -C "$WORK_DIR/operator" commit -m "chore: bump component versions to latest patch releases

Co-authored-by: Claude <noreply@anthropic.com>"
git -C "$WORK_DIR/operator" push fork "$EXISTING_HEAD"
```

Then update the PR body to reflect the current bumps:
```bash
gh pr edit "$EXISTING_PR_NUMBER" --repo tektoncd/operator \
  --body "# Changes

Bump component versions in components.yaml to their latest patch releases.

| Component | Old Version | New Version |
|-----------|-------------|-------------|
| chains | v0.26.2 | v0.26.5 |
...

# Submitter Checklist

- [ ] Run \`make test lint\` before submitting a PR
- [ ] Includes [tests](https://github.com/tektoncd/community/blob/master/standards.md#principles) (if functionality changed/added)
- [ ] Includes [docs](https://github.com/tektoncd/community/blob/master/standards.md#principles) (if user facing)
- [x] Commit messages follow [commit message best practices](https://github.com/tektoncd/community/blob/master/standards.md#commit-messages)

_See [the contribution guide](https://github.com/tektoncd/operator/blob/master/CONTRIBUTING.md) for more details._

# Release Notes

\`\`\`release-note
NONE
\`\`\`
"
```

Report: "Updated existing PR [#NUMBER](URL) with new component bumps."

**If updating an existing PR (description only)**:

Skip clone/commit/push entirely. Run only `gh pr edit` with the updated body (same template as above). No `WORK_DIR` needed.

Report: "Updated existing PR [#NUMBER](URL) description."

**If creating a new PR**:

```bash
SOURCE_BRANCH="chore/bump-component-versions-${OPERATOR_BRANCH}-$(date +%Y%m%d%H%M%S)"
git -C "$WORK_DIR/operator" checkout -b "$SOURCE_BRANCH"
git -C "$WORK_DIR/operator" add components.yaml
git -C "$WORK_DIR/operator" commit -m "chore: bump component versions to latest patch releases

Co-authored-by: Claude <noreply@anthropic.com>"
git -C "$WORK_DIR/operator" push fork "$SOURCE_BRANCH"
```

Create the cross-fork PR. The body must follow `tektoncd/operator`'s PR template:
```bash
gh pr create \
  --repo tektoncd/operator \
  --base "$OPERATOR_BRANCH" \
  --head "${FORK_USER}:${SOURCE_BRANCH}" \
  --title "chore: bump component versions to latest patch releases" \
  --body "# Changes

Bump component versions in components.yaml to their latest patch releases.

| Component | Old Version | New Version |
|-----------|-------------|-------------|
| chains | v0.26.2 | v0.26.5 |
...

# Submitter Checklist

- [ ] Run \`make test lint\` before submitting a PR
- [ ] Includes [tests](https://github.com/tektoncd/community/blob/master/standards.md#principles) (if functionality changed/added)
- [ ] Includes [docs](https://github.com/tektoncd/community/blob/master/standards.md#principles) (if user facing)
- [x] Commit messages follow [commit message best practices](https://github.com/tektoncd/community/blob/master/standards.md#commit-messages)

_See [the contribution guide](https://github.com/tektoncd/operator/blob/master/CONTRIBUTING.md) for more details._

# Release Notes

\`\`\`release-note
NONE
\`\`\`
"
```

Report the PR URL as a markdown link.

### Clean up

```bash
rm -rf "$WORK_DIR"
```
</step>

<step name="report">
**Write the version comparison report.**

Determine the report path based on mode:

**With version (patch mode):**
```bash
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_DIR="reports/${MAJOR_MINOR}/${VERSION}"
mkdir -p "$REPORT_DIR"
REPORT_FILE="${REPORT_DIR}/operator-bump-${TIMESTAMP}.md"
```

**Without version (latest mode):**
```bash
REPORT_FILE="reports/operator-bump-main.md"
```

Write the report:
```markdown
# Operator Bump: ${VERSION}

**Generated:** ${GENERATED}
**Operator branch:** tektoncd/operator @ ${OPERATOR_BRANCH}
**Mode:** ${MODE}
(If MODE is patch, also include: **Hack release config:** config/downstream/releases/${MAJOR_MINOR}.yaml)

## Component Versions

| Component | GitHub Repo | Current | Latest | Status |
|-----------|-------------|---------|--------|--------|
| ... | ... | ... | ... | ... |

## Result

${RESULT — one of: "All current", "PR created: [#NUM](URL)", "Updated existing PR: [#NUM](URL)", "Updated existing PR description: [#NUM](URL)", "Existing PR [#NUM](URL) by @AUTHOR — skipped", or "Outdated but declined"}
```

Use the **Generated** timestamp in absolute local time:
```bash
GENERATED=$(date +"${TZ_FMT}")
```

Print the summary to the conversation.
</step>
</process>

<success_criteria>
- [ ] Correct operator branch resolved per mode (hack config for patch, `main` for latest)
- [ ] Version comparison uses `sort -V` — never reports a downgrade as outdated
- [ ] User confirmation required before any write operations (clone, commit, PR)
- [ ] PR created via cross-fork pattern using authenticated user's fork
- [ ] Commits use local user identity with Co-authored-by trailer for Claude
- [ ] Patch mode report path: `reports/${MAJOR_MINOR}/${VERSION}/operator-bump-<timestamp>.md`
- [ ] All timestamps absolute local time with timezone; all PR numbers as markdown links
</success_criteria>
