#!/bin/zsh

# Utility script for VSCode tasks to create Gitlab URL for the currently selected file and line number

# Prereq: It is important to define GITLAB_PREFIX as env in the task configuration!

# file=$(echo $1 | sed 's/.*miki\/src\///')
file=${1#*$HOME/src/}

if [ -z "$2" ]
then
  BRANCH="develop"
else
  # current branch - the value of $2 doesn't matter, the condition is just to check if the argument is supplied
  BRANCH=$(git rev-parse --abbrev-ref HEAD)
  echo "current branch: $BRANCH"
fi

echo "file: $file"
echo "branch: $BRANCH"

BRANCH=$(echo $BRANCH | sed 's/\//\\\//g')
# BRANCH_PREFIX_FOLDERS='-\/tree/develop\/'
BRANCH_PREFIX_FILES="\/-\/blob\/$BRANCH\/"

MAIN=$(echo $file | sed "s/\//$BRANCH_PREFIX_FILES/")

echo $GITLAB_PREFIX$MAIN
# paste into clipboard
echo $GITLAB_PREFIX$MAIN | pbcopy