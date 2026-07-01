#!/usr/bin/env bash

VERSION=${1:-1.21}
ENVIRONMENT=${2:-devel}
NEW_PATCH=${3:-false}

#Create Task
oc apply -f tasks -f pipelines


tkn pipeline start konflux-release \
  --serviceaccount=gh-action \
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