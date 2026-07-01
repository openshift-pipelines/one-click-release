# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository implements a one-click release workflow for OpenShift Pipelines using Tekton pipelines and Konflux. The goal is to automate the entire release process from build setup through production release with minimal manual intervention.

## Architecture
    
### Release Workflow Stages

The release process is organized into three main phases:

1. **Build Setup**
   - Creates ReleasePlanAdmission in gitlab/konflux-release-data repo
   - Generates RPA/Pyxis configurations from Hack repo
   - Creates new release/patch from Hack repo
   - Updates upstream branches and watches for PRs
   - Applies configuration on Konflux
   - Monitors build status and merges PRs when green
   - Bumps OLM version in operator

2. **Update Sources Workflow**
   - Monitors Konflux builds and retries on failure
   - Triggers component builds after PR merge
   - Updates operator project.yaml with core-snapshot

3. **Release Steps** (Dev/Stage/Production)
   - **Bundle Release**: Updates CSV, builds bundle, releases
   - **Index Release**: Updates OLM with latest bundle snapshot, renders OLM, builds index images for multiple OCP versions
   - **Notifications**: Sends Slack notifications on completion

### Key Components

- **Tekton Pipeline**: `pipelines/openshift-pipelines-release.yaml`
  - Main pipeline orchestrating the release process
  - Configurable parameters: RELEASE, TAG, ENVIRONMENT, INDEX_APPLICATIONS
  - Supports multiple OCP version index images (4-14 through 5-0)

- **Konflux Integration**
  - Uses Konflux for component builds and releases
  - Monitors build status and handles failures
  - Manages ReleasePlanAdmission configurations

- **Hack Repository**
  - Source of truth for release configurations
  - Generates RPA/Pyxis entries to avoid human error
  - PRs are watched and merged automatically when builds are green

## Running the Release Pipeline

The primary way to trigger a release is through the `/release` skill:

```bash
source kube konflux
tkn pipeline start konflux-release-pipeline \
  --serviceaccount=gh-action \
  --param RELEASE=1.21 \
  --param ENVIRONMENT=stage \
  --param TAG=v1.21.2-test \
  --use-param-defaults \
  --showlog
```

### Pipeline Parameters

- `RELEASE`: Release version (e.g., "1.22")
- `NEW_PATCH`: Whether this is a new patch release (default: "false")
- `RELEASE_ACTION`: Specific release action to perform
- `TAG`: Release tag (e.g., "v1.22.2")
- `ENVIRONMENT`: Target environment - "dev", "stage", or "production"
- `INDEX_APPLICATIONS`: List of index applications for different OCP versions
- `REBUILD_COMPONENTS`: Components to rebuild (optional)

## Release Workflow Details

### Monitoring and Error Handling

- If Konflux builds fail, Slack notifications are sent to RC group
- Failed builds trigger automatic retries with 30-minute gaps
- Component builds are monitored and retriggered if not started due to API issues
- Build status is tracked: green builds auto-merge, failed builds notify team

### Version Management

- OLM version is read from bundle.dockerfile (current version)
- Min and Max OCP versions come from olm/config.yaml
- Bundle snapshots are updated in operator project.yaml

### Multi-Environment Support

Index images are built for multiple OCP versions:
- openshift-pipelines-index-4-14 through 4-23
- openshift-pipelines-index-5-0

Each environment (dev/stage/production) follows similar release steps but with different CSV configurations.

## Development Context

- The pipeline uses Tekton tasks referenced by name (e.g., `release-config-task`, `osp-github-pr-processor`)
- Requires Kubernetes/OpenShift cluster access with proper service account (`gh-action`)
- Integrates with GitLab for konflux-release-data repository
- Uses Slack for notifications

## Important Notes

- The release process should complete in a single click with all steps automated
- Human error is minimized by generating configurations from Hack repo rather than manual edits
- PR merge is conditional on build success
- Index releases are independent of specific release versions and contain all bundles for an OCP version
