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
`longhorn` StorageClass is available explicitly in each cluster; OKE's native
`oci-bv` StorageClass is the cluster default. The node bootstrap enables the
required iSCSI service and installs the NFS/cryptsetup/device-mapper packages.
The current disk is the worker boot volume; production requires a dedicated
storage-disk design and backup/recovery runbook before using it for important
data. Each cluster exposes the UI through its own route:
`storage-tools.hackyard.dev`, `storage-staging.hackyard.dev`, or
`storage-production.hackyard.dev`. This administrative surface must be
protected before general use.

Longhorn backups use OCI Object Storage through its S3-compatible API. The
tools Terraform stack owns a private versioned bucket, a dedicated IAM user
and customer secret key, and the bucket policy. Credentials and the endpoint
are stored in the shared OCI Vault and exposed to all clusters through
External Secrets. Each cluster uses a separate bucket prefix and a daily
default-group backup with seven retained backups and a periodic full backup.
Object Storage lifecycle deletion is intentionally not enabled until storage
growth and recovery requirements are reviewed.

OKE also provides the Oracle Block Volume CSI driver in every cluster. The
OKE-managed `oci-bv` StorageClass uses `blockvolume.csi.oraclecloud.com`,
provisions OCI Block Volumes with `ReadWriteOnce`, waits for Pod scheduling,
and supports expansion. It is the preferred class when native OCI volume
lifecycle, OCI snapshots, and OCI Block Volume backups are more important than
Longhorn replication. It is not managed by GitOps because OKE owns the class.
Workloads select it with `storageClassName: oci-bv`; workloads that need
Longhorn select `storageClassName: longhorn`. OCI File Storage CSI should be
evaluated separately for `ReadWriteMany` requirements.

The deployed tools baseline includes Grafana with the OCI Metrics datasource
plugin, direct Keycloak authentication, and a Contour route. It also runs
kube-prometheus-stack and a single-process Mimir deployment. Prometheus keeps a
short local retention window and remote-writes to Mimir, which Grafana uses as
its default Prometheus-compatible datasource. Mimir uses a 15 GiB Longhorn
volume with filesystem storage for this small-cluster profile; it must move to
OCI Object Storage and multiple replicas before production-scale use.

CloudNativePG is installed in all three clusters as an operator-only baseline.
The Flux roots point to the shared `gitops/core/cloudnative-pg` manifests,
which install chart `0.29.0` and operator `1.30.0` in `cnpg-system`. The tools
cluster additionally deploys `keycloak-postgres`: three CNPG instances with
100 GiB PVCs using the native `oci-bv` OCI Block Volume CSI StorageClass. The
cluster initializes the `keycloak` database and owner, and CNPG generates the
`keycloak-postgres-app` Secret consumed by the tools Keycloak resource.

Tools also installs the Barman Cloud CNPG-I plugin and an ObjectStore backed by
the existing OCI Object Storage bucket, using the dedicated prefix
`cnpg/keycloak-postgres/`, Vault-sourced credentials, WAL archiving, and a
30-day retention policy. Staging and production remain operator-only. OCI S3 compatibility requires path-style
addressing and the Barman checksum workaround; the backup IAM user is also
allowed to inspect this specific bucket so existing-bucket checks succeed.

The tools cluster also installs OLM `v0.45.0` and the Keycloak Operator through
the OperatorHub catalog. The Subscription uses the `fast` channel with manual
InstallPlan approval and an `OwnNamespace` OperatorGroup in `keycloak`. This
keeps the identity operator scoped to the tools cluster and its own namespace.
The `gitops/core/keycloak` manifests deploy two Keycloak instances at
`https://keycloak-inova.hackyard.dev`, using the CNPG read-write service and
the dedicated `platform` realm. OpenTofu generates the bootstrap admin password and
stores it in OCI Vault; External Secrets creates the bootstrap Secret. The
HTTPRoute uses the shared Contour Gateway with edge TLS. Cloudflare DNS uses
an explicit DNS-only A record for `keycloak-inova.hackyard.dev` pointing to
the tools LoadBalancer; it must not fall through to the proxied wildcard
record for another cluster. The realm provides direct OIDC clients for the
Kubernetes API, Grafana, and the protected Longhorn UIs.

Staging and production use native OKE OIDC with Keycloak as the issuer. Their
Kubernetes APIs map the `preferred_username` and `groups` claims with an
`oidc:` prefix and authorize them through GitOps-managed RBAC. The tools cluster
remains OCI IAM-authenticated while it is a Basic cluster; OKE requires an
Enhanced VCN-native cluster for external OIDC.

Each Longhorn UI is fronted by a dedicated OAuth2 Proxy deployment using a
Keycloak client and an environment-specific group. Dex and Teleport remain
optional manifests only and are not part of the active authentication stack.
See [`docs/CLUSTER_ACCESS.md`](docs/CLUSTER_ACCESS.md).

The full profile also contains Dex, Teleport, S3 proxy, Lychee, and Flux
add-ons. These are not part of the current minimal cluster roots and are not
considered deployed until explicitly enabled and validated.

## Cost and security boundaries

Enhanced OKE control planes, worker compute, public API endpoints, OCI
LoadBalancers, storage, and public DNS are separate operational and cost
considerations. Review plans and current OCI pricing before changing the
cluster type or exposing a service. Local Terragrunt state is suitable for a
personal deployment; use locked remote state for team operation.
