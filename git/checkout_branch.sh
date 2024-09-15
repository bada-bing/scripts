# Use FZF to change to the active branch
cb() {
  local branches branch
  branches=$(git --no-pager branch) &&
  branch=$(echo "$branches" | fzf +m) && # +m is opposite of -m (--multi)
  git checkout $(echo "$branch" | awk '{print $1}' | sed "s/.* //")
}
