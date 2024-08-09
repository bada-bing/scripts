# get active branch 
# just an example; no need to do this! use `git branch --show-current` instead

# cut: -f2 - return second field; d is delimiter
git branch | grep \* | cut -d ' ' -f2 