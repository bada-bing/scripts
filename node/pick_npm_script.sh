pick_npm_script () {
  if cat package.json > /dev/null 2>&1; then
      scripts=$(cat package.json | jq .scripts | sed '1d;$d' | fzf --height 40%) # 1d,$d - delete first and last line
 
      if [[ -n $scripts ]]; then
          script_name=$(echo $scripts | awk -F ': ' '{print $1}' | xargs)
          echo "npm run "$script_name;
          npm run $script_name
      else
          echo "Exit: You haven't selected any script"
      fi
  else
      echo "Error: There's no package.json"
  fi
}
