# OCI OKE multi-cluster platform

Infrastructure and GitOps configuration for three Oracle Cloud Infrastructure
(OCI) Kubernetes Engine (OKE) clusters:

- `tools` — shared tooling, External Secrets, and Grafana
- `staging` — pre-production workloads
- `production` — production workloads

Each cluster has its own VCN and two worker nodes. The VCNs are connected
through one shared Dynamic Routing Gateway (DRG), providing private network
connectivity between environments without merging their network boundaries.

## Architecture

```text
                         Shared DRG
                       /     |       \
                      /      |        \
              tools VCN  staging VCN  production VCN
                 |          |             |
              tools OKE  staging OKE  production OKE
                 |
       External Secrets + Grafana
```

| Cluster | OKE type | VCN CIDR | Pod CIDR | Service CIDR | Nodes |
|---|---|---|---|---|---:|
| tools | Basic | `10.10.0.0/16` | `10.244.0.0/16` | `10.96.0.0/16` | 2 |
| staging | Enhanced | `10.20.0.0/16` | `10.245.0.0/16` | `10.97.0.0/16` | 2 |
| production | Enhanced | `10.30.0.0/16` | `10.246.0.0/16` | `10.98.0.0/16` | 2 |

The worker nodes use private subnets. The OKE API endpoint and load-balancer
subnets currently use public subnets; review this before adopting the layout
for a stricter production network.

The DRG provides IP routing only. It does not provide Kubernetes service
discovery, pod-network federation, or cross-cluster failover. Keep all VCN,
pod, and service CIDRs unique.

## Repository layout

```text
live/oci/
├── root.hcl
├── drg/                         Shared DRG Terragrunt stack
└── clusters/
    ├── tools/{network,oke,config}
    ├── staging/{network,oke,config}
    └── production/{network,oke,config}

terraform/modules/               Reusable DRG, network, and OKE modules
gitops/core/                     Shared Flux application manifests
gitops/tools/                    Tools Flux root and Grafana
gitops/staging/                  Staging Flux root
gitops/production/               Production Flux root
scripts/deploy-minimal.sh        Sequential deployment helper
docs/MULTI_CLUSTER.md            Detailed design and extraction notes
```

## Requirements

- OCI account with permissions to manage networking, OKE, IAM, and Vault
- OCI CLI configured with a profile
- OpenTofu
- Terragrunt
- `kubectl`
- A Git repository accessible by Flux

Use versions compatible with the existing lock files where possible. The
configuration currently targets the values in `.env.example`, including the
configured Kubernetes version, worker shape, and Oracle Linux image pattern.

## Configuration

Copy the example environment file and fill in real values:

```sh
cp .env.example .env
chmod 600 .env
```

At minimum, set:

```dotenv
OCI_REGION=sa-saopaulo-1
OCI_CONFIG_FILE=/absolute/path/to/.oci/config
OCI_CONFIG_PROFILE=DEFAULT
OCI_COMPARTMENT_ID=ocid1.compartment...
OCI_TENANCY_ID=ocid1.tenancy...
TF_VAR_kubernetes_version=v1.36.1
TF_VAR_worker_shape=VM.Standard.E2.1
TF_VAR_worker_image_pattern=Oracle-Linux-9.7-2026.06.15
TF_VAR_ssh_public_key=ssh-ed25519...
```

The tools configuration creates a software-protected OCI Vault and AES key
when `TF_VAR_vault_id` is not set. Staging and production reuse that Vault;
the deployment helper resolves its OCID from the tools stack automatically.
An existing Vault can be supplied explicitly:

```dotenv
TF_VAR_vault_id=ocid1.vault.oc1...
```

Flux authentication variables are also read from `.env` when the configuration
stack needs to create or update the Git source credentials. Never commit `.env`,
Terraform state, kubeconfigs, private keys, or secret values.

## Deploy

Deploy one cluster at a time. The helper applies the shared DRG, selected VCN,
OKE cluster, node pool, and Kubernetes/Flux configuration in that order.

```sh
CLUSTER_NAME=tools ./scripts/deploy-minimal.sh
CLUSTER_NAME=staging ./scripts/deploy-minimal.sh
CLUSTER_NAME=production ./scripts/deploy-minimal.sh
```

The script stops on the first failed stack. Do not run two deployments at the
same time because the cluster stacks share DRG state and may compete for OCI
capacity.

For individual stacks:

```sh
terragrunt --working-dir live/oci/drg plan
terragrunt --working-dir live/oci/clusters/tools/network plan
terragrunt --working-dir live/oci/clusters/tools/oke plan
terragrunt --working-dir live/oci/clusters/tools/config plan
```

Use `apply` only after reviewing the plan. Local state is currently used by the
Terragrunt stacks; move to a locked remote backend before team operation.

## Flux and GitOps

Flux is configured with a separate root for each cluster:

| Cluster | Flux sync path |
|---|---|
| tools | `gitops/tools` |
| staging | `gitops/staging` |
| production | `gitops/production` |

The roots contain cluster-specific Flux `Kustomization` objects and reuse
shared manifests from `gitops/core` where appropriate. The tools root deploys:

- metrics-server
- External Secrets integration
- cert-manager and the Cloudflare DNS01 issuer
- Contour Gateway API ingress with an OCI LoadBalancer
- Grafana

The staging and production roots additionally deploy ExternalDNS. ExternalDNS
is intentionally not included in the current minimal tools root; the tools
cluster can host tooling and Grafana without managing application DNS.

The full stack under `gitops/core/kustomization.full.yaml` is intentionally not
enabled by the minimal roots. Enable additional components only after supplying
their required domains, credentials, storage, and OCI integrations.

Longhorn is an exception: it is enabled explicitly in all three cluster roots
as the baseline distributed block storage layer.

## CloudNativePG

CloudNativePG is installed in the `cnpg-system` namespace in tools, staging,
and production. The Flux configuration pins Helm chart `0.29.0`, which
installs CloudNativePG operator `1.30.0`. The installation creates the
operator and its PostgreSQL CRDs only; it does not create a PostgreSQL
database cluster, users, passwords, or PVCs.

Verify the operator in a cluster with:

```sh
kubectl -n flux-system get kustomization cloudnative-pg
kubectl -n cnpg-system get helmrelease cloudnative-pg
kubectl -n cnpg-system get deployment cloudnative-pg
kubectl get crd | grep postgresql.cnpg.io
```

When creating a database cluster, choose the storage class deliberately:
`oci-bv` uses OKE's native OCI Block Volume CSI and is the current default;
`longhorn` uses the replicated Longhorn layer. Database backups, WAL
archiving, credentials, network policy, and the desired instance count must be
designed before adding a `Cluster` resource.

Flux reads the configured remote Git repository. Changes made locally do not
become persistent Flux state until they are committed and pushed to the branch
configured in the Flux source.

## Contour ingress

Each cluster installs Contour in the `contour` namespace. Contour manages the
`contour` GatewayClass and Gateway API resources, while its Envoy data plane is
published through an OCI LoadBalancer Service. The LoadBalancer receives the
OCI network security group from the Terraform `ingress` module when
`TF_VAR_enable_ingress=true`.

Flux applies this in two stages: the `contour` Kustomization installs the
Contour HelmRelease and Gateway API CRDs first; `contour-gateway` then creates
the GatewayClass, Gateway, and certificate after those CRDs and cert-manager
are ready.

The shared Gateway listens on HTTP and HTTPS for `*.hackyard.dev` in every
cluster. HTTPS uses the cert-manager `letsencrypt` ClusterIssuer and the
Cloudflare DNS01 token stored in OCI Vault. Applications should use
`HTTPRoute` resources with:

```yaml
parentRefs:
  - name: contour
    namespace: contour
```

The previous Envoy Gateway resources and Envoy-specific `SecurityPolicy`
resources are not deployed. Contour does not implement those policies; OIDC
protection for routes that previously used them must be migrated to an
application-side proxy such as oauth2-proxy or another Contour-compatible
external authorization design before enabling those protected routes.

Check the ingress installation and address with:

```sh
kubectl get gatewayclass contour
kubectl -n contour get gateway contour
kubectl -n contour get svc contour-envoy
kubectl get httproute -A
```

The OCI LoadBalancer and public DNS records are billable/externally visible
resources. Do not expose a route until its hostname, certificate, backend, and
Cloudflare policy have been reviewed.

## ExternalDNS

Staging and production run ExternalDNS in the `external-dns` namespace. Both
roots use the self-contained provider configuration from
`gitops/core/external-dns/resources`; this avoids coupling their Flux paths to
the full shared profile. The current minimal tools root does not include
ExternalDNS.

ExternalDNS manages Cloudflare records for `hackyard.dev` from Kubernetes
Services, Ingresses, and Gateway API `HTTPRoute` resources. It uses the
Cloudflare API token synchronized from OCI Vault by External Secrets, and the
token is restricted to the `hackyard.dev` zone. The configured policy is
`sync`, so review route annotations and generated records before exposing a
workload.

Verify ExternalDNS and its credential synchronization with:

```sh
kubectl -n external-dns get pods
kubectl -n external-dns logs deploy/external-dns
kubectl -n external-dns get externalsecret external-secrets
```

No DNS record is created for a cluster until an application publishes a
supported, annotated route or service. The Contour LoadBalancer addresses are
cluster-specific; use the address shown by `kubectl -n contour get svc
contour-envoy` when validating the resulting Cloudflare record.

## Longhorn storage

Longhorn is deployed in the `longhorn` namespace in tools, staging, and
production. The HelmRelease uses Longhorn `1.11.1`, the V1 data engine, two
replicas per volume, and the node path `/var/lib/longhorn`. Its `longhorn`
StorageClass is available explicitly in each cluster. OKE's native `oci-bv`
StorageClass is the cluster default; use it when OCI-managed block storage is
preferred. Each cluster has a distinct HTTPS route for the Longhorn UI:

```text
tools      -> https://storage-tools.hackyard.dev
staging    -> https://storage-staging.hackyard.dev
production -> https://storage-production.hackyard.dev
```

The tools DNS record is managed outside the minimal tools ExternalDNS profile;
staging and production records are managed by their respective ExternalDNS
instances. The UI is an administrative surface and must be protected before
being used beyond controlled testing.

OKE Oracle Linux nodes must have `iscsi-initiator-utils`, `nfs-utils`,
`cryptsetup`, and `device-mapper` installed, with `iscsid` enabled and the
`iscsi_tcp` kernel module loaded. The node-pool bootstrap enforces this for new
nodes. Longhorn currently uses the worker boot volume as its storage disk;
dedicated block volumes should be added and configured before production data
is placed on this platform.

Verify Longhorn in a cluster with:

```sh
export KUBECONFIG="$PWD/terraform/.kube.tools.config"
kubectl -n flux-system get kustomization longhorn
kubectl -n longhorn get pods
kubectl get storageclass longhorn
kubectl -n longhorn get nodes.longhorn.io -o wide
kubectl -n longhorn get engineimages.longhorn.io -o wide
```

For a smoke test, create a temporary PVC and Pod using
`storageClassName: longhorn`, write a marker to the mounted volume, recreate
the Pod, and verify the marker remains. Remove the temporary namespace after
the test. Do not use the boot-disk-backed Longhorn disk for production
workloads until capacity, replication, backup, and failure-recovery procedures
are reviewed.

### OCI Block Volume CSI

OKE also deploys Oracle's native Block Volume CSI driver in all three
clusters. The OKE-managed `oci-bv` StorageClass uses the
`blockvolume.csi.oraclecloud.com` provisioner, waits until a Pod is scheduled,
supports `ReadWriteOnce`, and allows online expansion. It is currently the
default StorageClass; this class is created and maintained by OKE, so it is
not duplicated in GitOps.

Use it explicitly for workloads that should use OCI Block Volume instead of
Longhorn:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
spec:
  storageClassName: oci-bv
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
```

OCI Block Volume is a good fit for stateful workloads that need native OCI
attach/detach, volume expansion, and OCI Block Volume snapshots/backups. It
does not provide Longhorn's replica layer, and a volume is normally attached
to one node at a time. Use Longhorn when Kubernetes-level replication or
Longhorn backup workflows are required. For shared `ReadWriteMany` storage,
evaluate OCI File Storage CSI separately; `oci-bv` is not an RWX solution.

Verify the native driver and class with:

```sh
kubectl get storageclass oci-bv
kubectl -n kube-system get daemonset csi-oci-node
```

The tools cluster was smoke-tested with a temporary 50 GiB PVC and Pod. The
PVC bound through `oci-bv`, the Pod mounted the volume and wrote a marker, and
the namespace deletion removed the test resources. Production use still
requires a reviewed OCI Block Volume backup, retention, and restore procedure.

### Longhorn backup plan with OCI services

The tools Terraform stack creates a private, versioned OCI Object Storage
bucket named `oke-longhorn-backups`, a dedicated IAM user/customer secret key,
and a bucket-scoped policy. The S3-compatible access key, secret key, and OCI
Object Storage endpoint are stored in the shared OCI Vault and synchronized to
each cluster by External Secrets. Longhorn uses a separate prefix per cluster:

```text
s3://oke-longhorn-backups@sa-saopaulo-1/tools/
s3://oke-longhorn-backups@sa-saopaulo-1/staging/
s3://oke-longhorn-backups@sa-saopaulo-1/production/
```

Each cluster receives a default-group recurring backup at 02:00 UTC, retains
seven backups per volume, and performs a full backup after seven incremental
backups. Object Storage versioning is enabled; automatic deletion is not
configured, so review storage growth before adding a lifecycle policy.
Terraform state contains the generated customer secret key and must remain
protected or be moved to encrypted remote state.

Set `OCI_LONGHORN_BACKUP_USER_EMAIL` in the uncommitted `.env` before applying
the tools config. The tools stack must be applied first because it owns the
bucket, IAM credentials, and Vault secrets; staging and production only read
those Vault secrets through their existing External Secrets policies.

Verify the backup integration in each cluster:

```sh
export KUBECONFIG="$PWD/terraform/.kube.tools.config"
kubectl -n longhorn get externalsecret longhorn-backup-credentials
kubectl -n longhorn get secret longhorn-backup-credentials
kubectl -n longhorn get recurringjob daily-object-storage-backup
kubectl -n longhorn get backuptarget default
```

Before production use, create a test PVC, run a manual backup, restore it as a
new volume, and verify application data. Object Storage backups protect
Longhorn volume data; they do not replace application-consistent database
dumps or an OCI Block Volume backup strategy for unrelated compute disks.

The tools rollout was smoke-tested with a temporary 1 GiB PVC: data was
written, a Longhorn backup reached `Completed`, and OCI Object Storage listed
the resulting objects under the `tools/` prefix. The temporary workload was
removed after the test; the successful backup remains in the bucket as a
recovery artifact.

## External Secrets and OCI Vault

All clusters expose a `ClusterSecretStore` named `oracle-vault`.

- `tools` uses OCI Instance Principal because it is a Basic OKE cluster.
- `staging` and `production` use OKE Workload Identity.

The tools Grafana administrator password is stored in OCI Vault under the
secret name `grafana-tools-admin-password`. It is synchronized into the
`grafana-admin-credentials` Kubernetes Secret by an `ExternalSecret`. Secret
values are never stored in Git.

Check the integration after deployment:

```sh
export KUBECONFIG="$PWD/terraform/.kube.tools.config"
kubectl get pods -n external-secrets
kubectl get clustersecretstore oracle-vault
kubectl get externalsecret -A
```

## Grafana in tools

Grafana is a standalone HelmRelease in the `grafana` namespace. It uses a
ClusterIP service behind the tools Contour Gateway, local basic authentication,
disabled persistence, and the OCI Metrics datasource plugin. Its public route
is `https://grafana-inova.hackyard.dev`; Cloudflare DNS must point that name to
the tools Contour load-balancer address.

Access it locally with:

```sh
export KUBECONFIG="$PWD/terraform/.kube.tools.config"
kubectl -n grafana port-forward svc/grafana 3000:80
```

Then open `http://127.0.0.1:3000`. The health endpoint can be tested with:

```sh
curl http://127.0.0.1:3000/api/health
```

The public route can be checked after DNS and certificate propagation with:

```sh
curl -I https://grafana-inova.hackyard.dev/
```

The Grafana OCI IAM policy is managed by Terraform. Review and tighten the
dynamic-group matching rule if other compute workloads share the compartment.

## Validation and operations

Format and validate the infrastructure:

```sh
terragrunt hcl fmt --check live/oci
tofu -chdir=terraform/config fmt -check
tofu -chdir=terraform/config validate
```

Validate the GitOps manifests:

```sh
kubectl kustomize gitops/tools >/dev/null
kubectl kustomize gitops/staging >/dev/null
kubectl kustomize gitops/production >/dev/null
```

Inspect a deployed cluster:

```sh
export KUBECONFIG="$PWD/terraform/.kube.staging.config"
kubectl get nodes
kubectl get pods -A
kubectl get kustomizations -n flux-system
kubectl get events -A --sort-by=.lastTimestamp
```

Cluster-specific kubeconfigs are generated at:

```text
terraform/.kube.tools.config
terraform/.kube.staging.config
terraform/.kube.production.config
```

## Security and cost notes

- Review every OpenTofu plan before applying changes.
- Treat `.env`, `*.tfvars`, Terraform state, kubeconfigs, and OCI credentials as sensitive.
- Prefer Vault and External Secrets for runtime credentials.
- Review public API endpoints, public load-balancer subnets, node shapes, storage,
  and enhanced OKE features against the intended budget and security posture.
- Use compartment- and cluster-scoped IAM policies wherever possible.
- The current tools Instance Principal trust boundary is node-level; Workload
  Identity is the preferred model for workloads requiring narrower access.

## Further documentation

- [`docs/MULTI_CLUSTER.md`](docs/MULTI_CLUSTER.md) — architecture, networking,
  deployment order, validation, and repository extraction guidance
- [`terraform/README.md`](terraform/README.md) — original Terraform stack details
- [`DESIGN.md`](DESIGN.md) — original design notes
