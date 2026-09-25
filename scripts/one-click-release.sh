#!/usr/bin/env bash

VERSION=${1:-nightly}
ENVIRONMENT=${2:-devel}
NEW_PATCH=${3:-false}

#Create Task and Pipeline
oc apply -f tasks -f pipelines


tkn pipeline start one-click-release \
  --prefix-name=one-click-release-${VERSION/./-}-$ENVIRONMENT \
  --serviceaccount=konflux-bot-1 \
  --param VERSION=$VERSION \
  --param NEW_PATCH=$NEW_PATCH \
  --param ENVIRONMENT=$ENVIRONMENT \
  --use-param-defaults \
  -w name=source,emptyDir="" \
  --showlog

#tkn task start konflux-release-task \
#  --serviceaccount=gh-action \
#  --param APPLICATION=openshift-pipelines-core-1-22 \
#  --param ENVIRONMENT=stage \
#  --showlog
#
#tkn task start konflux-release-task \
#  --serviceaccount=gh-action \
#  --param APPLICATION=openshift-pipelines-bundle-1-22 \
#  --param ENVIRONMENT=stage \
#  --showlog