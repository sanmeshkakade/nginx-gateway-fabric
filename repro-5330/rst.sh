#!/usr/bin/env bash
# RST the agent<->control-plane gRPC streams (kind node iptables), so agents reconnect
# on the same uuid. Certs are left untouched. Usage: ./rst.sh [hold_seconds]
# Env: DP=demo CP=nginx-gateway NODE=kind-control-plane
set -uo pipefail
DP="${DP:-demo}"
CP="${CP:-nginx-gateway}"
NODE="${NODE:-kind-control-plane}"
HOLD="${1:-8}"

# custom-columns, not `-o wide` + awk (a pod's "(N ago)" RESTARTS shifts the columns).
CPIP=$(kubectl get pods -n "$CP" --no-headers -o custom-columns=NAME:.metadata.name,IP:.status.podIP \
        | grep -v cert | grep gateway-fabric | awk '{print $2}' | head -1)
AGENTIPS=()
while IFS= read -r ip; do [ -n "$ip" ] && AGENTIPS+=("$ip"); done < <(
  kubectl get pods -n "$DP" --no-headers -o custom-columns=NAME:.metadata.name,IP:.status.podIP \
    | grep gateway-nginx | awk '{print $2}')

if [ -z "$CPIP" ] || [ "${#AGENTIPS[@]}" -eq 0 ]; then
  echo "ERROR: could not resolve CP IP (got '$CPIP') or agent IPs (count ${#AGENTIPS[@]})" >&2
  exit 1
fi
echo "cpIP=$CPIP agents=${AGENTIPS[*]}"

add_rules(){ for ip in "${AGENTIPS[@]}"; do
  docker exec "$NODE" iptables -I FORWARD -s "$ip" -d "$CPIP" -p tcp -j REJECT --reject-with tcp-reset 2>/dev/null
  docker exec "$NODE" iptables -I FORWARD -s "$CPIP" -d "$ip" -p tcp -j REJECT --reject-with tcp-reset 2>/dev/null
done; }
del_rules(){ for ip in "${AGENTIPS[@]}"; do
  docker exec "$NODE" iptables -D FORWARD -s "$ip" -d "$CPIP" -p tcp -j REJECT --reject-with tcp-reset 2>/dev/null
  docker exec "$NODE" iptables -D FORWARD -s "$CPIP" -d "$ip" -p tcp -j REJECT --reject-with tcp-reset 2>/dev/null
done; }

add_rules
# patch some SnippetsFilters so packets hit the rule -> RST
for i in $(seq 0 "$HOLD"); do
  kubectl patch snippetsfilter -n "$DP" churn-sf --type merge \
    -p "{\"spec\":{\"snippets\":[{\"context\":\"http.server.location\",\"value\":\"add_header X-RST \\\"$RANDOM\\\" always;\"}]}}" >/dev/null 2>&1
  kubectl patch snippetsfilter -n "$DP" "sf-$i" --type merge \
    -p "{\"spec\":{\"snippets\":[{\"context\":\"http.server.location\",\"value\":\"add_header X-RST \\\"$RANDOM\\\" always;\"}]}}" >/dev/null 2>&1
  sleep 1
done
del_rules
echo "RST cycle done (hold=${HOLD}s)"
