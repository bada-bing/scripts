#!/bin/sh

ACTIVE_PROJECT=$(sh ~/src/scripts/local_development/get_active_project.sh)
PROJECT_LOC="$HOME/src/$ACTIVE_PROJECT"
ACTIVE_TASK=$(sh ~/src/scripts/git/current_issue.sh $PROJECT_LOC)

echo $ACTIVE_TASK | tr '[:lower:]' '[:upper:]'