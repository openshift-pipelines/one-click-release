#!/usr/bin/env bash

VERSION=${1:-nightly}
ENVIRONMENT=${2:-devel}
START_FROM=${3:-BUILD}
NEW_PATCH=${4:-false}
SNAPSHOTS=${5:-}


#Create Task and Pipeline
oc apply -f tasks -f pipelines


tkn pipeline start one-click-release \
  --prefix-name=one-click-release-${VERSION/./-}-$ENVIRONMENT \
  --serviceaccount=konflux-bot-1 \
  --param VERSION=$VERSION \
  --param NEW_PATCH=$NEW_PATCH \
  --param ENVIRONMENT=$ENVIRONMENT \
  --param START_FROM=$START_FROM \
  --param SNAPSHOTS=$SNAPSHOTS \
  --use-param-defaults \
  -w name=source,emptyDir="" \
  --showlog