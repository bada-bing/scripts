#!/usr/bin/env bash
set -euo pipefail

job_url="${1:-}"
build_count=10

if [[ -z "$job_url" || "$job_url" == "-h" || "$job_url" == "--help" ]]; then
  echo "Usage: get_jenkins_job_builds.sh JENKINS_JOB_URL" >&2
  exit 1
fi

job_url="${job_url%/}"

curl -g -fsSL \
  "$job_url/api/json?tree=builds[number,result,actions[parameters[name,value],causes[userName,shortDescription]]]{0,$build_count}" |
  jq -r '
    .builds[] |
    [
      .number,
      (.result // "RUNNING"),
      ([.actions[]?.parameters[]? | select(.name == "BRANCH_SPECIFIER") | .value][0] // "-"),
      ([.actions[]?.causes[]? | .userName // .shortDescription][0] // "-")
    ] | @tsv
  '
