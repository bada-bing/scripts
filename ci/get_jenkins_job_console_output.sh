#!/usr/bin/env bash
set -euo pipefail

job_url="${1:-}"

if [[ -z "$job_url" || "$job_url" == "-h" || "$job_url" == "--help" ]]; then
  echo "Usage: get_jenkins_job_console_output.sh JENKINS_JOB_URL" >&2
  exit 1
fi

job_url="${job_url%/}"

if [[ "$job_url" =~ /[0-9]+$ ]]; then
  curl -fsSL "$job_url/consoleText"
else
  curl -fsSL "$job_url/lastBuild/consoleText"
fi
