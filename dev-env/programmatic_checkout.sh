#!/bin/bash
#
# Programmatically and safely checkout a git branch.
#
# This script implements the following workflow:
# 1. Stashes any uncommitted changes in the current branch.
# 2. Switches to the default branch (e.g., main) and pulls the latest changes.
# 3. Switches to the target branch and rebases it on top of the default branch.
# 4. Applies any stashes that were previously created for the target branch.
# 5. If the most recent commit on the target branch is a "WIP" commit,
#    it "unpacks" it so the work is in the working directory.

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <branch-name>"
  exit 1
fi

TARGET_BRANCH="$1"
CURRENT_BRANCH=$(git branch --show-current)

# 1. Stash changes on the current branch if it's dirty
if [ -n "$(git status --porcelain)" ]; then
  echo "Working directory is dirty. Stashing changes from '$CURRENT_BRANCH'." 
  # The stash message will help us find it later if we switch back
  git stash push --include-untracked -m "autostash: $CURRENT_BRANCH"
else
  echo "Working directory is clean. Nothing to stash."
fi

# 2. Update the default branch
DEFAULT_BRANCH=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | cut -d' ' -f5 || echo "")

if [ -z "$DEFAULT_BRANCH" ]; then
    if git show-ref --verify --quiet refs/heads/main; then
        DEFAULT_BRANCH="main"
    elif git show-ref --verify --quiet refs/heads/master; then
        DEFAULT_BRANCH="master"
    else
        echo "Error: Could not determine the default branch." >&2
        echo "Please ensure 'origin' remote is configured or a 'main'/'master' branch exists." >&2
        exit 1
    fi
fi

echo "Updating default branch '$DEFAULT_BRANCH'..."
git checkout "$DEFAULT_BRANCH"
git pull --rebase

# 3. Checkout and rebase the target branch
echo "Checking out '$TARGET_BRANCH' and rebasing onto '$DEFAULT_BRANCH'..."
git checkout "$TARGET_BRANCH"
git rebase "$DEFAULT_BRANCH"

# 4. Apply any relevant stashes to the target branch
# We look for the most recent stash matching our convention for this branch.
STASH_ID=$(git stash list --pretty='format:%gd:%gs' | grep "autostash: $TARGET_BRANCH" | head -n 1 | cut -d: -f1)

if [ -n "$STASH_ID" ]; then
  echo "Found stash '$STASH_ID' for branch '$TARGET_BRANCH'. Applying..."
  git stash pop "$STASH_ID"
else
  echo "No 'autostash' found for '$TARGET_BRANCH'."
fi

# 5. "Unpack" a WIP commit if it exists
# Per user request, if there's a WIP commit, unpack it.
# Using mixed reset to keep the changes in the working directory.
LAST_COMMIT_MSG=$(git log -1 --pretty=%B)
if echo "$LAST_COMMIT_MSG" | grep -qi "wip"; then
    echo "Found 'WIP' commit. Unpacking it into working directory."
    git reset HEAD~1
fi

echo "✅ Successfully switched to branch '$TARGET_BRANCH'."
