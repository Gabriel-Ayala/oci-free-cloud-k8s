# Platform design

This document records the implemented baseline. Detailed commands and
extraction notes are in [`README.md`](README.md) and
[`docs/MULTI_CLUSTER.md`](docs/MULTI_CLUSTER.md).

## Infrastructure

The repository provisions three independent OCI OKE clusters with Terragrunt:

| Cluster | OKE type | Purpose | Workers |
|---|---|---|---:|
| tools | `BASIC_CLUSTER` | shared tooling, ingress, and Grafana | 2 |
| staging | `ENHANCED_CLUSTER` | pre-production workloads | 2 |
| production | `ENHANCED_CLUSTER` | production workloads | 2 |

Each cluster has its own VCN, public subnet, private worker subnet, pod CIDR,
and service CIDR. A shared DRG provides private VCN-to-VCN routing. The DRG
does not provide pod federation, service discovery, or failover; all CIDRs must
remain unique.

The deployment layers are intentionally separate:

1. shared DRG;
2. per-cluster network and DRG attachment;
3. per-cluster OKE control plane and two-node pool; and
4. per-cluster Flux/Kubernetes configuration.

## GitOps

Flux has an independent sync root for each cluster:

```text
tools      -> gitops/tools
staging    -> gitops/staging
production -> gitops/production
```

The current minimal profiles install metrics-server, External Secrets,
cert-manager, Contour, and Longhorn. Tools also installs Grafana. Staging and
production install ExternalDNS. The optional
`gitops/core/kustomization.full.yaml` profile contains additional services and
must only be enabled after their credentials, domains, storage, and IAM are
provided.

## Ingress and DNS

Contour is the ingress controller in all three clusters. Its Envoy data plane
runs as two replicas behind an OCI LoadBalancer Service. Each cluster creates
a Gateway API `Gateway` with HTTP and HTTPS listeners for `*.hackyard.dev`.
Cert-manager obtains the wildcard certificate using the Cloudflare DNS01
issuer and the Cloudflare token stored in OCI Vault.

ExternalDNS is enabled in staging and production. It watches Services,
Ingresses, CRD sources, and Gateway API HTTPRoutes, is filtered to the
`hackyard.dev` zone, and manages A records with `sync` policy. The tools
Grafana route uses `grafana-inova.hackyard.dev`; its Cloudflare record is
managed outside the current minimal tools ExternalDNS profile. ExternalDNS
uses a unique TXT owner ID per cluster so staging and production do not manage
or delete each other’s records.

Contour routes must reference the shared Gateway:

```yaml
parentRefs:
  - name: contour
    namespace: contour
```

Contour does not consume the former Envoy Gateway `SecurityPolicy` resources.
Protected applications require an application-side or compatible external
authorization design.

## Secret management and identity

OCI Vault stores runtime credentials. External Secrets creates one
`ClusterSecretStore` named `oracle-vault` per cluster:

- tools authenticates with OCI Instance Principal;
- staging and production authenticate with OKE Workload Identity.

The Cloudflare token is stored under `cloudflare-api-token`; the tools Grafana
administrator password is stored under `grafana-tools-admin-password`. Secret
values are never committed to Git. The staging and production IAM policies
are scoped to the cluster, namespace, service account, and Vault. The tools
Instance Principal policy is node-level and should be tightened if other
workloads share the compartment.

## Storage, observability, and optional services

Longhorn is deployed in all three clusters with its V1 data engine, two
replicas per volume, and `/var/lib/longhorn` as the default disk. The
`longhorn` StorageClass is default in each cluster. The node bootstrap enables
the required iSCSI service and installs the NFS/cryptsetup/device-mapper
packages. The current disk is the worker boot volume; production requires a
dedicated storage-disk design and backup/recovery runbook before using it for
important data. Each cluster exposes the UI through its own route:
`storage-tools.hackyard.dev`, `storage-staging.hackyard.dev`, or
`storage-production.hackyard.dev`. This administrative surface must be
protected before general use.

The deployed tools baseline includes standalone Grafana with the OCI Metrics
datasource plugin, local basic authentication, no persistent volume, and a
Contour route. The full Prometheus/Alertmanager stack is present only in the
optional core profile and requires its own secrets, storage, and routes.

The full profile also contains Dex, Teleport, S3 proxy, Lychee, and Flux
add-ons. These are not part of the current minimal cluster roots and are not
considered deployed until explicitly enabled and validated.

## Cost and security boundaries

Enhanced OKE control planes, worker compute, public API endpoints, OCI
LoadBalancers, storage, and public DNS are separate operational and cost
considerations. Review plans and current OCI pricing before changing the
cluster type or exposing a service. Local Terragrunt state is suitable for a
personal deployment; use locked remote state for team operation.
