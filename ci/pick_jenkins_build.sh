#!/usr/bin/env bash
set -euo pipefail

job_url="${1:-}"
build_count=10

if [[ -z "$job_url" || "$job_url" == "-h" || "$job_url" == "--help" ]]; then
  echo "Usage: pick_jenkins_build.sh JENKINS_JOB_URL" >&2
  echo "Returns the full URL of the selected build (for use with get_jenkins_job_console_output.sh)" >&2
  exit 1
fi

job_url="${job_url%/}"

selected=$(
  curl -g -fsSL \
    "$job_url/api/json?tree=builds[number,timestamp,result,actions[parameters[name,value],causes[userName,shortDescription]]]{0,$build_count}" |
  jq -r '
    .builds[] |
    [
      .number,
      (.result // "RUNNING"),
      (.timestamp / 1000 | strftime("%Y-%m-%d %H:%M")),
      ([.actions[]?.causes[]? | .userName // .shortDescription][0] // "-"),
      ([.actions[]?.parameters[]? | select(.name == "BRANCH_SPECIFIER") | .value][0] // "-")
    ] | @tsv
  ' |
  column -t -s $'\t' |
  fzf --prompt="Select build > " --header="NUM    RESULT     TRIGGERED             BY                    BRANCH"
)

[[ -z "$selected" ]] && exit 0

build_number=$(echo "$selected" | awk '{print $1}')
echo "$job_url/$build_number"
