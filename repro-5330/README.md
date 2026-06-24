# Reproducing #5330 locally

Tools to reproduce [#5330](https://github.com/nginx/nginx-gateway-fabric/issues/5330) on a `kind`
cluster: after an agent reconnects on the same `uuid`, a stale stream's `RemoveConnection` deletes the
live entry, and config applies start failing with `connection not found` (stale upstream IPs).

It needs three things at once:

1. The agent reconnects on the **same uuid** — drop only the gRPC stream with a TCP reset (a pod
   restart gets a new uuid).
2. Config keeps **changing**, so an apply is in flight when the stale cleanup runs.
3. The reset cycle **repeats**, since the window is narrow.

Certs are untouched, so any `connection not found` isn't a TLS issue.

## Prerequisites

- A `kind` cluster (node container `kind-control-plane`).
- NGF from an **unpatched** build (the bug is present on `edge` / 2.6.x), installed in namespace
  `nginx-gateway`, data plane scaled to ~3 replicas.
- `kubectl`, `docker`, `go` on PATH.

Namespaces/names are overridable via env vars (`DP`, `CP`, `CTRL`, `NODE`) — see the top of each script.

## Files

| File | Purpose |
|------|---------|
| `topology.yaml`   | Base: `demo` namespace, backend, Gateway, one route, `churn-sf`. |
| `route.yaml.tmpl` | Template for one HTTPRoute + SnippetsFilter pair. |
| `gen-routes.go`   | Renders N pairs from the template. |
| `apply-routes.sh` | Renders and applies (or deletes) N pairs. |
| `rst.sh`          | One TCP-reset reconnect cycle. |
| `churn-clean.sh`  | Churn loop + repeated `rst.sh`, plus the detector. |

## Steps

```sh
kubectl apply -f topology.yaml
./apply-routes.sh 60          # later: ./apply-routes.sh 60 delete
./churn-clean.sh 180 18
```

`churn-clean.sh` exits `0` on the first `connection not found` (writing `CLEAN-FOUND.log`), or `1` on
timeout. It usually reproduces in ~30–45s, e.g.:

```
>>> #5330 REPRODUCED at 44s: 'connection not found'=2, x509=0
... level=ERROR msg="Failed to send update overview"
    error="rpc error: code = NotFound desc = connection not found" ...
```
