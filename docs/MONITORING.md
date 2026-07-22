# Multi-cluster monitoring

Tools owns the central metrics service. Tools, staging, and production each run
their own kube-prometheus-stack collector and remote-write to Mimir through the
private tools OCI Network Load Balancer at `10.10.1.250:8080`. Every collector
adds `cluster` and `environment` labels, so Grafana can query the fleet from one
datasource.

## Components

- `kube-prometheus-stack` in `monitoring`: Prometheus Operator, Prometheus,
  node-exporter, kube-state-metrics, recording rules, alerting rules, and
  Alertmanager.
- Mimir in tools `monitoring`: one `grafana/mimir:3.1.2` all-in-one pod using
  OCI Object Storage for blocks, ruler data, and Alertmanager state.
- Grafana in tools `grafana`: Mimir is the default Prometheus-compatible
  datasource and dashboard sidecar loads the fleet and operations dashboards.

Prometheus retains three days locally and remote-writes to:

```text
http://10.10.1.250:8080/api/v1/push
```

Mimir is queried through:

```text
http://mimir.monitoring.svc.cluster.local:8080/prometheus
```

Mimir is internal-only. The NLB uses a reserved private IP and is reachable
only from the peered cluster networks; there is no public route for its API.

## Storage and provisioning

The tools Terraform stack creates a private Object Storage bucket, a dedicated
IAM customer secret key, and four Vault secrets. External Secrets maps those
Vault values to the `mimir-object-storage` Secret in `monitoring`. The Mimir
bucket uses separate `blocks`, `ruler`, and `alertmanager` prefixes and keeps
30 days of blocks. No access key or secret key is committed to Git.

The Mimir NLB uses the reserved private address `10.10.1.250`. The subnet and
reserved-IP OCIDs are injected into Flux from the Terraform-created
`observability-config` ConfigMap.

Before applying the tools configuration, add a unique OCI IAM contact email to
`.env` (it is intentionally not committed):

```sh
OCI_MIMIR_STORAGE_USER_EMAIL=your-mimir-storage-contact@example.com
```

Apply in this order so the private address exists before the central service is
created:

```sh
set -a; . ./.env; set +a
terragrunt --working-dir live/oci/clusters/tools/network apply
terragrunt --working-dir live/oci/clusters/tools/config apply
```

Then allow Flux to reconcile the collectors and dashboards. Staging and
production do not create another Mimir or Object Storage bucket; they only run
collectors that remote-write to the tools endpoint.

## Verify GitOps

```sh
export KUBECONFIG="$PWD/terraform/.kube.tools.config"
kubectl get kustomization -n flux-system monitoring grafana
kubectl get helmrelease -n monitoring kube-prometheus-stack
kubectl get pods -n monitoring
kubectl get svc -n monitoring mimir
kubectl get externalsecret,secret -n monitoring
```

The monitoring Kustomization waits for External Secrets and Longhorn. Grafana
waits for monitoring so its Mimir datasource is available when it starts.

The Grafana dashboard sidecar imports dashboards organized by product:

- `gitops/tools/grafana/dashboards/kubernetes/`: fleet overview and cluster
  resources.
- `gitops/tools/grafana/dashboards/mimir/`: Mimir and Prometheus health.
- `gitops/tools/grafana/dashboards/platform/`: platform operations.
- `gitops/core/grafana/dashboards/fluxcd/`: Flux control-plane and cluster
  dashboards.
- `gitops/core/grafana/dashboards/bkw/`: BKW product dashboards.

The cluster selector is available on the cluster and operations dashboards.
The `grafana_folder` ConfigMap annotation maps these product groups to Grafana
folders so the repository layout and Grafana UI stay aligned.

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

Grafana's Generic OAuth configuration must set both `allowed_groups` and
`groups_attribute_path = groups`; without the attribute path Grafana cannot
evaluate the Keycloak group claim and rejects otherwise valid users.

## Troubleshooting

```sh
kubectl -n monitoring describe pod -l app.kubernetes.io/name=mimir
kubectl -n monitoring logs deploy/mimir --tail=200
kubectl -n monitoring get prometheus,alertmanager,servicemonitor,podmonitor
kubectl -n monitoring get events --sort-by=.lastTimestamp
```

For staging and production, use the corresponding kubeconfig and verify the
collector's remote-write target and labels:

```sh
kubectl -n monitoring get helmrelease,pods,pvc
kubectl -n monitoring get prometheus kube-prometheus-stack-prometheus -o yaml \
  | rg 'cluster:|environment:|10.10.1.250'
```

If Mimir is unavailable, Grafana's `Prometheus` datasource can be selected as
a temporary fallback. If the Mimir PVC is Pending, check Longhorn health and
available replica capacity before changing the storage class.
