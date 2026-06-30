#!/usr/bin/env bash
# Usage: cluster_status.sh <context> [deployment-name]
CONTEXT=$1
DEPLOYMENT=${2:-""}

if [ -n "$DEPLOYMENT" ]; then
  DATA=$(kubectl get deployments --context "$CONTEXT" --field-selector "metadata.name=$DEPLOYMENT" -o json)
else
  DATA=$(kubectl get deployments --context "$CONTEXT" -o json)
fi

echo "$DATA" | jq -r '
  def bold(s):  "[1m\(s)[0m";
  def green(s): "[32m\(s)[0m";
  def red(s):   "[31m\(s)[0m";
  def cyan(s):  "[36m\(s)[0m";

  def age(ts):
    (now - (ts | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime)) as $secs |
    if $secs < 3600 then "\($secs / 60 | floor)m ago"
    elif $secs < 86400 then "\($secs / 3600 | floor)h ago"
    else "\($secs / 86400 | floor)d ago"
    end;

  def date(ts):
    ts | strptime("%Y-%m-%dT%H:%M:%SZ") | strftime("%Y-%m-%d %H:%M");

  .items[] |
  ((.status.readyReplicas // 0) == .spec.replicas) as $ok |
  ((.status.conditions // []) | map(.lastUpdateTime) | max // .metadata.creationTimestamp) as $since |
  "\(bold(.metadata.name)): \(if $ok then green("OK") else red("NOT OK") end)
deployed: \(cyan(.spec.template.spec.containers[0].image))
since:    \(date($since)) (\(age($since)))
pods:     \(.status.readyReplicas // 0)/\(.spec.replicas)
"
'
