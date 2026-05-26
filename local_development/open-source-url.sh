#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./open-source-url.sh 'http://localhost:3000/browse/<host>/<owner>/<repo>@<ref>/-/blob/<path>?highlightRange=<start>%2C<end>'
  ./open-source-url.sh /Users/miki/src/<repo>/<path> [line]
  ./open-source-url.sh <repo> <path> [line]

Examples:
  ./open-source-url.sh 'http://localhost:3000/browse/github.com/bada-bing/document_management@refs/heads/main/-/blob/README.md?highlightRange=69%2C75'
  ./open-source-url.sh /Users/miki/src/document_management/src/main.ts 42
  ./open-source-url.sh document_management src/main.ts 42
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  usage >&2
  exit 1
}

remote_to_web_url() {
  local remote="$1"

  remote="${remote%.git}"

  case "$remote" in
    git@github.com:*)
      printf 'https://github.com/%s' "${remote#git@github.com:}"
      ;;
    git@gitlab.com:*)
      printf 'https://gitlab.com/%s' "${remote#git@gitlab.com:}"
      ;;
    git@gitlab.*:*)
      local host_and_path="${remote#git@}"
      printf 'https://%s/%s' "${host_and_path%%:*}" "${host_and_path#*:}"
      ;;
    ssh://git@github.com/*)
      printf 'https://github.com/%s' "${remote#ssh://git@github.com/}"
      ;;
    ssh://git@gitlab.com/*)
      printf 'https://gitlab.com/%s' "${remote#ssh://git@gitlab.com/}"
      ;;
    ssh://git@gitlab.*/*)
      local host_and_path="${remote#ssh://git@}"
      printf 'https://%s/%s' "${host_and_path%%/*}" "${host_and_path#*/}"
      ;;
    https://github.com/*|http://github.com/*|https://gitlab.com/*|http://gitlab.com/*|https://gitlab.*/*|http://gitlab.*/*)
      printf '%s' "$remote"
      ;;
    *)
      return 1
      ;;
  esac
}

urlencode_path() {
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

urldecode() {
  local value="${1//+/ }"
  printf '%b' "${value//%/\\x}"
}

ref_to_blob_ref() {
  local ref="$1"

  case "$ref" in
    refs/heads/*)
      printf '%s' "${ref#refs/heads/}"
      ;;
    refs/tags/*)
      printf '%s' "${ref#refs/tags/}"
      ;;
    *)
      printf '%s' "$ref"
      ;;
  esac
}

sourcebot_url_to_source_url() {
  local sourcebot_url="$1"
  local without_scheme without_host browse_path query host repo_path_and_ref repo_path ref path path_and_query
  local owner_repo encoded_path decoded_path blob_ref line_start line_end source_url

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
  encoded_path="$(urlencode_path "$decoded_path")"
  blob_ref="$(ref_to_blob_ref "$ref")"

  if [[ "$host" == github.* ]]; then
    source_url="https://$host/$repo_path/blob/$blob_ref/$encoded_path"
  else
    source_url="https://$host/$repo_path/-/blob/$blob_ref/$encoded_path"
  fi

  if [[ "$query" == *highlightRange=* ]]; then
    line_start="${query#*highlightRange=}"
    line_start="${line_start%%&*}"
    line_start="$(urldecode "$line_start")"
    line_end="${line_start#*,}"
    line_start="${line_start%%,*}"

    if [[ "$line_start" =~ ^[0-9]+$ && "$line_end" =~ ^[0-9]+$ ]]; then
      if [[ "$line_start" = "$line_end" ]]; then
        source_url="$source_url#L$line_start"
      else
        source_url="$source_url#L$line_start-L$line_end"
      fi
    fi
  fi

  printf '%s' "$source_url"
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

if [[ "$1" == http://localhost:3000/browse/* || "$1" == https://localhost:3000/browse/* || "$1" == http://127.0.0.1:3000/browse/* || "$1" == https://127.0.0.1:3000/browse/* ]]; then
  source_url="$(sourcebot_url_to_source_url "$1")" || die "unsupported Sourcebot URL: $1"
  open_url "$source_url"
  exit 0
fi

src_root="/Users/miki/src"

if [[ "$1" = /* ]]; then
  file_path="$1"
  line="${2:-}"
  [[ -e "$file_path" ]] || die "path does not exist: $file_path"
  repo_root="$(git -C "$(dirname "$file_path")" rev-parse --show-toplevel)"
  rel_path="${file_path#"$repo_root"/}"
else
  [[ $# -ge 2 ]] || die "repo and path are required"
  repo_root="$src_root/$1"
  rel_path="$2"
  line="${3:-}"
  [[ -d "$repo_root/.git" ]] || die "not a git repo: $repo_root"
fi

remote="$(git -C "$repo_root" config --get remote.origin.url || true)"
[[ -n "$remote" ]] || die "remote.origin.url is not set for $repo_root"

web_url="$(remote_to_web_url "$remote")" || die "unsupported remote URL: $remote"
commit="$(git -C "$repo_root" rev-parse HEAD)"
encoded_path="$(urlencode_path "$rel_path")"

case "$web_url" in
  https://github.com/*|http://github.com/*)
    url="$web_url/blob/$commit/$encoded_path"
    ;;
  https://gitlab.com/*|http://gitlab.com/*|https://gitlab.*/*|http://gitlab.*/*)
    url="$web_url/-/blob/$commit/$encoded_path"
    ;;
  *)
    die "unsupported code host URL: $web_url"
    ;;
esac

if [[ -n "$line" ]]; then
  [[ "$line" =~ ^[0-9]+$ ]] || die "line must be a number"
  url="$url#L$line"
fi

open_url "$url"
