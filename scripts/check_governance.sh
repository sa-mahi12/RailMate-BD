#!/usr/bin/env bash
set -Eeuo pipefail
[ "$(git branch --show-current)" = main ] || { echo 'Current branch is not main' >&2; exit 2; }
local_branches="$(git for-each-ref --format='%(refname:short)' refs/heads)"
[ "$local_branches" = main ] || { echo "Extra local branches: $local_branches" >&2; exit 3; }
remote_branches="$(git ls-remote --heads origin | awk '{sub("refs/heads/", "", $2); print $2}')"
[ "$remote_branches" = main ] || { echo "Extra remote branches: $remote_branches" >&2; exit 4; }
case "$(git remote get-url origin)" in *RailMate-BD.git|*RailMate-BD) ;; *) echo 'Unexpected code repository remote' >&2; exit 5;; esac
printf 'GOVERNANCE OK: only main local and remote, expected code repo name.\n'
