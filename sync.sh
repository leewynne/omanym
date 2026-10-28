#!/usr/bin/env bash
# Keeps a copy of namemyai.org's data in the cache folder and prints it as one
# JSON object for the popup. It downloads again only when the site's version
# (the content hash its build stamps on app.js) has changed, so most runs
# fetch just the home page.
#
#   sync.sh <cache-dir>           check the site, update if needed, print
#   sync.sh <cache-dir> --cached  print the cached copy without going online
#
# Exits 1 when there is nothing to print: no cache, and the site unreachable.
# OMANYM_SITE overrides the site, for the tests.
set -uo pipefail

site=${OMANYM_SITE:-https://namemyai.org}
dir=${1:?usage: sync.sh <cache-dir> [--cached]}
files=(data/characters.json data/sources.json data/roles.json selfnames.json)
ua="Omanym (Omarchy plugin)"

cached() {
  [[ -f $dir/version ]] || return 1
  for f in "${files[@]}"; do [[ -f $dir/${f##*/} ]] || return 1; done
}

fetch() {
  curl -fsSL --compressed --max-time 30 -A "$ua" "$@"
}

update() {
  local version tmp
  version=$(fetch "$site/" | grep -o 'app\.js?v=[0-9a-f]*' | head -1 | cut -d= -f2) || return 1
  [[ -n $version ]] || return 1
  if cached && [[ $(<"$dir/version") == "$version" ]]; then
    return 0
  fi
  mkdir -p "$dir" || return 1
  tmp=$(mktemp -d "$dir/.sync.XXXXXX") || return 1
  for f in "${files[@]}"; do
    # Each file must be a JSON array, so a half-finished deploy or an error
    # page never replaces a good copy.
    if ! fetch -o "$tmp/${f##*/}" "$site/$f?v=$version" || ! jq -e 'type == "array" and length > 0' "$tmp/${f##*/}" >/dev/null 2>&1; then
      rm -rf "$tmp"
      return 1
    fi
  done
  for f in "${files[@]}"; do mv -f "$tmp/${f##*/}" "$dir/${f##*/}"; done
  printf '%s\n' "$version" >"$dir/version"
  rm -rf "$tmp"
}

if [[ ${2:-} != --cached ]]; then
  update || echo "omanym: couldn't update from $site" >&2
fi

cached || exit 1
jq -c -n \
  --rawfile version "$dir/version" \
  --slurpfile characters "$dir/characters.json" \
  --slurpfile sources "$dir/sources.json" \
  --slurpfile roles "$dir/roles.json" \
  --slurpfile selfnames "$dir/selfnames.json" \
  '{version: ($version | rtrimstr("\n")), characters: $characters[0], roles: $roles[0], selfnames: $selfnames[0],
    sources: ($sources[0] | map({slug, combined}))}'
