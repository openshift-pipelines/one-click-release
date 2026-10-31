---
name: openshift-pipelines:release
description: "One Click release of openshfit-pipelines"
allowed-tools: Bash, Read, Write
metadata:
  user-invocable: "true"
---
# RHACM Add-on Tekton-Kueue

## Phase 1 — Gather
**Start immediately when invoked. Do not wait for the user to prompt you.**


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