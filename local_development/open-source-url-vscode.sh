#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./open-source-url-vscode.sh 'http://localhost:3000/browse/<host>/<owner>/<repo>@<ref>/-/blob/<path>?highlightRange=<start>%2C<end>'
  ./open-source-url-vscode.sh /Users/miki/src/<repo>/<path> [line]
  ./open-source-url-vscode.sh <repo> <path> [line]

Environment:
  SOURCE_URL_SRC_ROOT=/Users/miki/src
  SOURCE_URL_PRINT_ONLY=1

Examples:
  ./open-source-url-vscode.sh 'http://localhost:3000/browse/github.com/bada-bing/document_management@refs/heads/main/-/blob/README.md?highlightRange=69%2C75'
  ./open-source-url-vscode.sh /Users/miki/src/document_management/src/main.ts 42
  ./open-source-url-vscode.sh document_management src/main.ts 42
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  usage >&2
  exit 1
}

urldecode() {
  local value="${1//+/ }"
  printf '%b' "${value//%/\\x}"
}

urlencode_file_url_path() {
  local path="$1"
  local encoded=""
  local i char hex

  for ((i = 0; i < ${#path}; i++)); do
    char="${path:i:1}"
    case "$char" in
      [a-zA-Z0-9.~_/-])
        encoded+="$char"
        ;;
      *)
        printf -v hex '%%%02X' "'$char"
        encoded+="$hex"
        ;;
    esac
  done

  printf '%s' "$encoded"
}

vscode_file_url() {
  local file_path="$1"
  local line="${2:-}"
  local url

  url="vscode://file$(urlencode_file_url_path "$file_path")"

  if [[ -n "$line" ]]; then
    [[ "$line" =~ ^[0-9]+$ ]] || return 1
    url="$url:$line"
  fi

  printf '%s' "$url"
}

sourcebot_url_to_local_file() {
  local sourcebot_url="$1"
  local src_root="$2"
  local without_scheme without_host browse_path query host repo_path_and_ref repo_path ref path_and_query
  local decoded_path line_start line_end repo_name file_path

  without_scheme="${sourcebot_url#*://}"
  without_host="${without_scheme#*/}"
  browse_path="${without_host#browse/}"
  query=""

  if [[ "$browse_path" == *\?* ]]; then
    query="${browse_path#*\?}"
    browse_path="${browse_path%%\?*}"
  fi

  [[ "$browse_path" == */-/blob/* ]] || return 1

  host="${browse_path%%/*}"
  repo_path_and_ref="${browse_path#*/}"
  path_and_query="${repo_path_and_ref#*/-/blob/}"
  repo_path_and_ref="${repo_path_and_ref%%/-/blob/*}"
  repo_path="${repo_path_and_ref%@*}"
  ref="${repo_path_and_ref##*@}"

  [[ -n "$host" && -n "$repo_path" && -n "$ref" && -n "$path_and_query" ]] || return 1

  decoded_path="$(urldecode "$path_and_query")"
  repo_name="${repo_path##*/}"
  file_path="$src_root/$repo_name/$decoded_path"
  line_start=""

  if [[ "$query" == *highlightRange=* ]]; then
    line_start="${query#*highlightRange=}"
    line_start="${line_start%%&*}"
    line_start="$(urldecode "$line_start")"
    line_end="${line_start#*,}"
    line_start="${line_start%%,*}"

    if [[ ! "$line_start" =~ ^[0-9]+$ || ! "$line_end" =~ ^[0-9]+$ ]]; then
      line_start=""
    fi
  fi

  [[ -e "$file_path" ]] || return 1

  vscode_file_url "$file_path" "$line_start"
}

open_url() {
  local url="$1"

  printf '%s\n' "$url"

  if [[ "${SOURCE_URL_PRINT_ONLY:-}" = "1" ]]; then
    return
  fi

  if command -v open >/dev/null 2>&1; then
    open "$url"
  else
    printf '%s\n' "$url"
  fi
}

if [[ $# -lt 1 || $# -gt 3 ]]; then
  die "invalid arguments"
fi

if [[ "$1" = "-h" || "$1" = "--help" ]]; then
  usage
  exit 0
fi

src_root="${SOURCE_URL_SRC_ROOT:-/Users/miki/src}"

if [[ "$1" == http://localhost:3000/browse/* || "$1" == https://localhost:3000/browse/* || "$1" == http://127.0.0.1:3000/browse/* || "$1" == https://127.0.0.1:3000/browse/* ]]; then
  url="$(sourcebot_url_to_local_file "$1" "$src_root")" || die "could not map Sourcebot URL to an existing local file under $src_root"
  open_url "$url"
  exit 0
fi

if [[ "$1" = /* ]]; then
  file_path="$1"
  line="${2:-}"
  [[ -e "$file_path" ]] || die "path does not exist: $file_path"
else
  [[ $# -ge 2 ]] || die "repo and path are required"
  file_path="$src_root/$1/$2"
  line="${3:-}"
  [[ -e "$file_path" ]] || die "path does not exist: $file_path"
fi

url="$(vscode_file_url "$file_path" "$line")" || die "line must be a number"
open_url "$url"
