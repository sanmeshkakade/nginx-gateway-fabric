#!/usr/bin/env bash
# Render and apply (or delete) N HTTPRoute + SnippetsFilter pairs via gen-routes.go.
# Usage:
#   ./apply-routes.sh [count] [apply|delete]    # defaults: 60 apply
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
N="${1:-60}"
ACTION="${2:-apply}"
( cd "$DIR" && go run gen-routes.go "$N" ) | kubectl "$ACTION" -f -
