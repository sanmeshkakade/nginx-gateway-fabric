#!/usr/bin/env bash
# Churn config + repeatedly RST the agents, watch for "connection not found".
# Usage: ./churn-clean.sh [max_seconds] [rst_every_seconds]
# Env: DP=demo CP=nginx-gateway CTRL=deploy/nginx-gateway-nginx-gateway-fabric
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DP="${DP:-demo}"
CP="${CP:-nginx-gateway}"
CTRL="${CTRL:-deploy/nginx-gateway-nginx-gateway-fabric}"
MAX="${1:-300}"; RST_EVERY="${2:-22}"
LOG=$DIR/clean.log; FOUND=$DIR/CLEAN-FOUND.log
: > "$LOG"; : > "$FOUND"
log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }
PODS(){ kubectl get pods -n "$DP" -o name 2>/dev/null | grep gateway-nginx | sed 's#pod/##'; }
SFS=$(kubectl get snippetsfilter -n "$DP" -o name | sed 's#.*/##')

log "START clean isolation max=${MAX}s rst_every=${RST_EVERY}s"

# churn config so applies stay in flight
( c=0; while :; do for sf in $SFS; do c=$((c+1));
    kubectl patch snippetsfilter -n "$DP" "$sf" --type merge \
      -p "{\"spec\":{\"snippets\":[{\"context\":\"http.server.location\",\"value\":\"add_header X-Churn \\\"$c\\\" always;\"}]}}" >/dev/null 2>&1
    sleep 0.4; done; done ) & A_PID=$!

# RST the agents on an interval
( while :; do bash "$DIR/rst.sh" 8 >>"$LOG" 2>&1; sleep "$RST_EVERY"; done ) & B_PID=$!

cleanup(){ kill $A_PID $B_PID 2>/dev/null; log "stopped loops"; }
trap cleanup EXIT

START=$(date +%s)
while :; do
  now=$(date +%s); el=$((now-START))
  [ "$el" -ge "$MAX" ] && { log "TIMEOUT ${el}s — not caught this run"; exit 1; }

  CNF=0; X509=0; HASHES=""
  for p in $(PODS); do
    c=$(kubectl logs -n "$DP" "$p" -c nginx --since=$((RST_EVERY*2))s 2>/dev/null | grep -c "connection not found")
    x=$(kubectl logs -n "$DP" "$p" -c nginx --since=$((RST_EVERY*2))s 2>/dev/null | grep -c "unknown authority")
    CNF=$((CNF+c)); X509=$((X509+x))
    h=$(kubectl exec -n "$DP" "$p" -c nginx -- sh -c 'find /etc/nginx/conf.d /etc/nginx/includes -type f 2>/dev/null|sort|xargs cat 2>/dev/null|sha256sum' 2>/dev/null | cut -c1-16)
    HASHES="$HASHES $p=$h"
  done
  CPCNF=$(kubectl logs -n "$CP" "$CTRL" -c nginx-gateway --since=$((RST_EVERY*2))s 2>/dev/null | grep -c "connection not found")
  CNF=$((CNF+CPCNF))
  DISTINCT=$(echo "$HASHES" | tr ' ' '\n' | grep = | sed 's/.*=//' | sort -u | grep -c .)

  if [ "$CNF" -gt 0 ]; then
    log ">>> #5330 REPRODUCED at ${el}s: 'connection not found'=$CNF, x509=$X509 (x509=0 => not a TLS issue)"
    {
      echo "=== #5330 at ${el}s  cnf=$CNF x509=$X509 ==="
      echo "hashes:$HASHES   distinct=$DISTINCT"
      for p in $(PODS); do echo "--- $p ---"; kubectl logs -n "$DP" "$p" -c nginx --since=$((RST_EVERY*2))s 2>/dev/null | grep "connection not found" | tail -3; done
    } >> "$FOUND"
    exit 0
  fi
  log "ok el=${el}s cnf=$CNF x509=$X509 distinct_hash=$DISTINCT |$HASHES"
  sleep 5
done
