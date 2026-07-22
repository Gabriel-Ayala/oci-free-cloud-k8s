# Tools monitoring

The tools cluster owns the initial monitoring stack for the platform. Staging
and production are not scraped by this deployment yet; their own monitoring
profiles can be added after the tools resource and retention profile are
validated.

## Components

- `kube-prometheus-stack` in `monitoring`: Prometheus Operator, Prometheus,
  node-exporter, kube-state-metrics, recording rules, alerting rules, and
  Alertmanager.
- Mimir in `monitoring`: one `grafana/mimir:3.1.2` pod running the all-in-one
  target with a 15 GiB Longhorn PVC named `mimir-data`.
- Grafana in `grafana`: Mimir is the default Prometheus-compatible datasource;
  the local Prometheus service remains available for troubleshooting.

Prometheus retains three days locally and remote-writes to:

```text
http://mimir.monitoring.svc.cluster.local:8080/api/v1/push
```

Mimir is queried through:

```text
http://mimir.monitoring.svc.cluster.local:8080/prometheus
```

Mimir is internal-only. There is no public route for its API.

## Why this is the initial profile

The tools workers are small and currently run several shared services. A
distributed Mimir chart would add multiple stateful and stateless components,
which is not a good fit for the available memory. The single-process profile
keeps the deployment small while providing remote-write ingestion and a
PromQL-compatible long-term path beyond the Prometheus pod.

Filesystem block storage is supported for a single Mimir node, but it is a
development/small-cluster choice. The volume is protected by the Longhorn
backup policy already configured for tools. It does not provide Mimir HA and it
does not replace an object-storage backup strategy.

Before scaling this beyond the tools cluster:

1. Create dedicated OCI Object Storage buckets or prefixes for Mimir blocks,
   ruler data, and Alertmanager state.
2. Store the OCI S3 credentials in OCI Vault and expose them with External
   Secrets; never put them in Helm values or Git.
3. Configure multiple Mimir replicas with a production-compatible object
   store and memberlist/ring settings.
4. Decide whether each cluster writes to a shared tenant or uses distinct
   tenant IDs, then add authentication and tenant headers.

Grafana's Mimir chart documentation requires external object storage for a
production deployment; the current filesystem profile is deliberately not
presented as production HA. See the upstream guidance at
<https://grafana.com/docs/helm-charts/mimir-distributed/latest/run-production-environment-with-helm/>.

## Verify GitOps

```sh
export KUBECONFIG="$PWD/terraform/.kube.tools.config"
kubectl get kustomization -n flux-system monitoring grafana
kubectl get helmrelease -n monitoring kube-prometheus-stack
kubectl get pods -n monitoring
kubectl get pvc -n monitoring mimir-data
```

The monitoring Kustomization waits for External Secrets and Longhorn. Grafana
waits for monitoring so its Mimir datasource is available when it starts.

## Smoke tests

Check Mimir readiness and its Prometheus API from inside the cluster:

```sh
kubectl -n monitoring run mimir-check --rm -i --restart=Never \
  --image=curlimages/curl:8.16.0 -- \
  curl -fsS http://mimir:8080/ready

kubectl -n monitoring run mimir-query --rm -i --restart=Never \
  --image=curlimages/curl:8.16.0 -- \
  curl -fsS 'http://mimir:8080/prometheus/api/v1/query?query=up'
```

Confirm Prometheus has accepted the remote-write configuration:

```sh
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
curl -fsS http://127.0.0.1:9090/api/v1/status/runtimeinfo
```

Then sign in to <https://grafana-inova.hackyard.dev>, open Explore, select
`Mimir`, and query `up` or `kube_node_info`.

## Troubleshooting

```sh
kubectl -n monitoring describe pod -l app.kubernetes.io/name=mimir
kubectl -n monitoring logs deploy/mimir --tail=200
kubectl -n monitoring get prometheus,alertmanager,servicemonitor,podmonitor
kubectl -n monitoring get events --sort-by=.lastTimestamp
```

If Mimir is unavailable, Grafana's `Prometheus` datasource can be selected as
a temporary fallback. If the Mimir PVC is Pending, check Longhorn health and
available replica capacity before changing the storage class.
