# TODO change the location of the .env file where the active project is saved
cat ~/src/raycast-extensions/wa-2/.env | awk -F= '{print $2}'
# TODO add a similar script for active issue
# that script should not be confused with git/current_issue because it should read from the env file as well 
# (since the branch is not the best predictor of the current issue, and also I should be able to dynamically set the issue, e.g., via raycast)