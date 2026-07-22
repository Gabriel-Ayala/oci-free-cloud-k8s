# Multi-cluster OCI/OKE deployment

This document describes the split from the original single-cluster Terraform
layout into three independent OKE clusters managed with Terragrunt:

- `tools`: shared tooling and observability
- `staging`: pre-production workloads
- `production`: production workloads

Each cluster starts with two managed worker nodes. The clusters use separate
VCNs and are connected privately through one shared Dynamic Routing Gateway
(DRG).

## What changed from the original repository

The original single-cluster entry points remain under `terraform/infra/` and
`terraform/config/` for compatibility. New deployments use the following
layout instead:

```text
live/oci/
├── root.hcl                         shared provider and local-state settings
├── drg/terragrunt.hcl               one shared DRG
└── clusters/
    ├── tools/
    │   ├── network/terragrunt.hcl   tools VCN and DRG attachment
    │   ├── oke/terragrunt.hcl       tools OKE cluster and node pool
    │   └── config/terragrunt.hcl    Flux and Kubernetes configuration
    ├── staging/
    │   └── network, oke, config      staging equivalents
    └── production/
        └── network, oke, config      production equivalents

terraform/modules/
├── drg/                             shared DRG module
├── cluster-network/                 reusable VCN/network module
└── oke-cluster/                     reusable OKE/node-pool module
```

The deployment helper was updated to:

1. Load and export `.env`.
2. Apply the shared DRG.
3. Apply the selected cluster network.
4. Apply the selected OKE cluster and node pool.
5. Apply Flux/Kubernetes configuration.
6. Stop immediately if any stack fails.

Generated kubeconfigs are cluster-specific and ignored by Git:

```text
terraform/.kube.tools.config
terraform/.kube.staging.config
terraform/.kube.production.config
```

## Current cluster topology

| Cluster | OKE type | VCN CIDR | Pod CIDR | Service CIDR | Workers | Kubeconfig |
|---|---|---|---|---|---:|---|
| tools | `BASIC_CLUSTER` | `10.10.0.0/16` | `10.244.0.0/16` | `10.96.0.0/16` | 2 | `.kube.tools.config` |
| staging | `ENHANCED_CLUSTER` | `10.20.0.0/16` | `10.245.0.0/16` | `10.97.0.0/16` | 2 | `.kube.staging.config` |
| production | `ENHANCED_CLUSTER` | `10.30.0.0/16` | `10.246.0.0/16` | `10.98.0.0/16` | 2 | `.kube.production.config` |

Each VCN contains a public subnet (the VCN base `/24`) and a private worker
subnet in the next `/24`, for example `10.20.1.0/24` for staging. The OKE API endpoint
and service load balancers currently use the public subnet; worker nodes use
the private subnet.

The worker shape and image are selected through `.env`. The deployed setup
currently uses `VM.Standard.E2.1` with an x86 Oracle Linux OKE image matching
the configured Kubernetes version. The image selector must match the worker
architecture; an ARM image cannot be used with an x86 shape.

## Network connectivity

The DRG is shared by all three VCNs. Every cluster network stack creates:

- a VCN;
- public and private subnets;
- internet, NAT, and service gateways;
- security lists and route tables;
- a VCN-to-DRG attachment; and
- routes for the other cluster VCN CIDRs through the DRG.

The DRG provides IP connectivity between VCNs. It does not provide Kubernetes
service discovery, DNS federation, pod-network federation, or automatic
cross-cluster failover. Applications that communicate across clusters must use
private addresses or an explicit multi-cluster solution such as a service mesh
or API gateway.

Keep all VCN, pod, and service CIDRs non-overlapping. When adding a cluster,
add its VCN CIDR to `peer_vcn_cidrs` in every existing network stack and add
the reverse routes in the new stack.

## OCI limits and cluster types

OKE Basic clusters do not add a control-plane charge, but have fewer managed
features. Enhanced clusters provide features such as managed add-ons,
workload identity, node cycling, and enhanced cluster capabilities. Enhanced
clusters are charged separately from worker compute, storage, networking, and
load-balancer resources. Confirm current rates in the OCI price list before
planning long-running environments.

`tools` remains Basic, while staging and production use Enhanced OKE. The type
is set explicitly in:

```text
live/oci/clusters/staging/oke/terragrunt.hcl
live/oci/clusters/production/oke/terragrunt.hcl
```

Check limits before adding more clusters:

```sh
set -a; source .env; set +a

oci limits resource-availability get \
  --service-name container-engine \
  --limit-name cluster-count \
  --compartment-id "$OCI_COMPARTMENT_ID"

oci limits resource-availability get \
  --service-name container-engine \
  --limit-name enhanced-cluster-count \
  --compartment-id "$OCI_COMPARTMENT_ID"
```

## Configuration

Create a local environment file and never commit it:

```sh
cp .env.example .env
```

Required values:

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

The deployment script exports the file before invoking Terragrunt. This is
important because the OCI provider reads the region, profile, compartment,
SSH key, worker shape, image pattern, and Kubernetes version from environment
variables.

## OCI Vault and External Secrets

All three clusters are configured to install External Secrets and create a
`ClusterSecretStore` named `oracle-vault`. Staging and production use OKE
workload identity; the Basic `tools` cluster uses OCI Instance Principal. No
OCI user, API key, private key, or Kubernetes credential secret is created.

Set the Vault OCID in `.env` before deploying staging or production:

```dotenv
TF_VAR_vault_id=ocid1.vault.oc1...
```

The `tools` configuration creates the software-protected Vault and AES key
automatically when `TF_VAR_vault_id` is empty. Retrieve the created Vault OCID
with:

```sh
set -a; source .env; set +a
terragrunt --working-dir live/oci/clusters/tools/config output -raw external_secrets_vault_id
```

The deployment helper resolves this output automatically when deploying
staging or production. You can also export it manually for direct Terragrunt
commands.

The configuration stack creates a read-only IAM policy scoped to the Vault.
For staging and production it is additionally scoped by cluster OCID,
namespace `external-secrets`, and service account `external-secrets`. For
`tools`, the dynamic group matches compute instances in the configured
compartment; tighten that rule if other compute workloads share the
compartment. The stack installs the External Secrets Helm chart before
creating the `ClusterSecretStore`.

The `tools` Instance Principal path is available on Basic OKE. It avoids
Kubernetes credentials but has a broader node-level trust boundary than
workload identity.

After deployment, verify the operator and store:

```sh
export KUBECONFIG="$PWD/terraform/.kube.staging.config"
kubectl get pods -n external-secrets
kubectl get clustersecretstore oracle-vault
kubectl describe clustersecretstore oracle-vault
```

The deployment was tested on all three clusters with a temporary OCI Vault
secret. `tools` synchronized it through Instance Principal authentication;
staging and production synchronized it through separate Workload Identity
policies scoped to their cluster OCIDs. Each `ExternalSecret` reached
`SecretSynced` and produced the expected Kubernetes Secret. The temporary
Kubernetes resources were removed and the Vault smoke-test secret was
scheduled for deletion; the Vault, key, policies, dynamic group, operators,
and stores remain.

The Vault itself and the secret values are intentionally managed outside this
repository. Create the Vault and its secrets through OCI before applying the
cluster configuration, and do not put secret values in Git or Terraform
variables.

## Deployment

Deploy one cluster at a time:

```sh
CLUSTER_NAME=tools ./scripts/deploy-minimal.sh
CLUSTER_NAME=staging ./scripts/deploy-minimal.sh
CLUSTER_NAME=production ./scripts/deploy-minimal.sh
```

The script is intentionally sequential. Do not run two cluster applies at the
same time because they share the DRG state and may compete for OCI capacity.

After deployment, inspect a cluster with its own kubeconfig:

```sh
export KUBECONFIG="$PWD/terraform/.kube.staging.config"
kubectl get nodes
kubectl get pods -A
kubectl get kustomizations -n flux-system
```

### Per-cluster Flux and Grafana

Each cluster has its own Flux root and sync path:

```text
tools      -> gitops/tools
staging    -> gitops/staging
production -> gitops/production
```

The tools root includes the shared metrics and External Secrets resources,
kube-prometheus-stack, single-process Mimir, and a Grafana deployment under
`gitops/tools/grafana`. Grafana uses a ClusterIP service and an admin password
synchronized from the OCI Vault secret `grafana-tools-admin-password`; the
password is not stored in Git.

The tools Grafana uses direct Keycloak OAuth, the OCI Metrics datasource plugin,
and Mimir as its default Prometheus-compatible datasource. It is exposed
through the tools Contour Gateway at `https://grafana-inova.hackyard.dev`.

To access it locally:

```sh
export KUBECONFIG="$PWD/terraform/.kube.tools.config"
kubectl -n grafana port-forward svc/grafana 3000:80
curl http://127.0.0.1:3000/api/health
```

The tools public route requires the Cloudflare `grafana-inova` record to point
to the tools Contour load balancer. Validate it with:

```sh
curl -I https://grafana-inova.hackyard.dev/
```

The Flux path change and manifests must be committed and pushed to the Git
repository configured in `gitops` before Flux can reconcile them permanently.
Until then, a local smoke deployment can be applied with:

```sh
kubectl apply -k gitops/tools/grafana
```

### CloudNativePG operator

Each cluster installs CloudNativePG through its own Flux root and the shared
`gitops/core/cloudnative-pg` manifests. The pinned Helm chart is `0.29.0`,
installing operator `1.30.0` in `cnpg-system`. The deployment is operator-only:
there is no PostgreSQL `Cluster`, credential Secret, PVC, or backup schedule in
this rollout.

Verify the installation with:

```sh
kubectl -n flux-system get kustomization cloudnative-pg
kubectl -n cnpg-system get helmrelease cloudnative-pg
kubectl -n cnpg-system get deployment cloudnative-pg,pods
kubectl get crd | grep postgresql.cnpg.io
```

The tools cluster now has a concrete PostgreSQL workload for the future
Keycloak deployment in `gitops/core/keycloak-postgres`. It uses three CNPG
instances, three tools workers, and 100 GiB per instance through the native
`oci-bv` OCI Block Volume CSI StorageClass. CNPG initializes database `keycloak`
and owner `keycloak`, and generates `keycloak-postgres-app` for later Keycloak
configuration.

The Barman Cloud CNPG-I plugin sends WAL and scheduled physical backups to the
existing OCI Object Storage bucket at
`s3://oke-longhorn-backups/cnpg/keycloak-postgres/`. The access key is sourced
from OCI Vault through External Secrets, and the ObjectStore retention policy
is 30 days. This is deployed only in tools; staging and production retain the
operator-only CNPG baseline. A restore test and the eventual Keycloak server
resource are intentionally separate changes. OCI S3 compatibility is
configured with path-style addressing, non-chunked-compatible checksum
settings, and bucket inspection permission for Barman's destination check.

### Keycloak Operator in tools

The tools root installs OLM `v0.45.0` from the pinned upstream release
manifests, then subscribes to the OperatorHub `keycloak-operator` package in
the `fast` channel. The operator runs in the dedicated `keycloak` namespace
with an `OwnNamespace` OperatorGroup, so staging and production are not
watched. The initial InstallPlan was manually approved and installed Keycloak
Operator `26.7.0` successfully.

The tools root additionally applies `gitops/core/keycloak`, which deploys two
Keycloak instances using the `keycloak-postgres-rw` service and
`keycloak-postgres-app` Secret. The bootstrap admin password is generated by
OpenTofu, stored in OCI Vault as `keycloak-tools-admin-password`, and synced by
External Secrets. The shared Contour Gateway exposes the default master realm
at `https://keycloak-inova.hackyard.dev` with edge TLS. Custom realms, clients,
and users are not provisioned. Operator upgrades remain manual because an
upgrade can also change the managed Keycloak version.

Verify the deployed service with:

```sh
export KUBECONFIG="$PWD/terraform/.kube.tools.config"
kubectl -n flux-system get kustomization keycloak
kubectl -n keycloak get externalsecret,secret,keycloak,pods,httproute
curl -sk --resolve keycloak-inova.hackyard.dev:443:<CONTOUR_PUBLIC_IP> \
  https://keycloak-inova.hackyard.dev/realms/master/.well-known/openid-configuration
```

### Contour ingress in every cluster

The three cluster roots each install the shared Contour configuration from
`gitops/core/contour`. The deployment includes:

- Contour with the Gateway API CRDs;
- a `contour` GatewayClass and Gateway in the `contour` namespace;
- Envoy replicas exposed by an OCI `LoadBalancer` Service; and
- an HTTP and HTTPS listener for `*.hackyard.dev`.

The Flux resources are deliberately staged. `contour` installs the Helm chart
and its Gateway API CRDs first. `contour-gateway` depends on that Kustomization
and cert-manager-issuer before applying the GatewayClass, Gateway, and
certificate. This prevents Flux dry-run validation from evaluating
`GatewayClass` before the CRD exists.

The HTTPS listener depends on the per-cluster cert-manager and issuer
Kustomizations. The certificate is issued through Cloudflare DNS01 using the
Cloudflare token already expected in OCI Vault under `cloudflare-api-token`.
The Terraform ingress module supplies the OCI load-balancer network security
group through the `oci-lb-sg-id` ConfigMap. Enable that module for each
cluster before expecting public traffic:

```dotenv
TF_VAR_enable_ingress=true
```

Routes in shared applications now target the Contour Gateway:

```yaml
parentRefs:
  - name: contour
    namespace: contour
```

Validate the result with:

```sh
kubectl get gatewayclass contour
kubectl -n contour get gateway contour
kubectl -n contour get deploy,svc,pods
kubectl get httproute -A
```

### Longhorn storage in every cluster

The tools, staging, and production roots each install Longhorn from
`gitops/core/longhorn`. The deployment uses chart version `1.11.1`, the V1
data engine, two replicas per volume, and the default disk at
`/var/lib/longhorn` on each worker. It creates the `longhorn` StorageClass for
explicit selection. OKE's native `oci-bv` StorageClass remains the default
class in each cluster. Longhorn exposes the UI through a cluster-specific route:
`storage-tools.hackyard.dev`, `storage-staging.hackyard.dev`, or
`storage-production.hackyard.dev`. The tools DNS record is outside the minimal
tools ExternalDNS profile; staging and production manage their records through
separate ExternalDNS owner IDs. Protect this administrative UI before general
use.

The Oracle Linux worker bootstrap installs the Longhorn host dependencies and
enables `iscsid`/`iscsi_tcp`. Existing nodes must receive the same prerequisite
change before the controller is enabled. Verify the installation with:

```sh
kubectl -n flux-system get kustomization longhorn
kubectl -n longhorn get pods
kubectl get storageclass longhorn
kubectl -n longhorn get nodes.longhorn.io,engineimages.longhorn.io -o wide
```

The rollout was smoke-tested in all three clusters with a 1 GiB PVC and Pod;
each volume became healthy and mounted successfully, and the tools test also
retained a marker after Pod recreation. The default disk is the worker boot
volume, so dedicated OCI Block Volumes, capacity planning, backups, and
recovery testing are required before production data is entrusted to Longhorn.

#### OCI Block Volume CSI option

OKE supplies and manages the Oracle Block Volume CSI driver in all three
clusters. The `oci-bv` StorageClass uses the
`blockvolume.csi.oraclecloud.com` provisioner, has
`WaitForFirstConsumer` binding, supports `ReadWriteOnce`, and permits
expansion. It dynamically creates and attaches OCI Block Volumes without
requiring a separate GitOps controller or StorageClass manifest. Select it
explicitly in a PVC with `storageClassName: oci-bv`.

This is the recommended second storage path for single-node stateful workloads
that need OCI-native volume operations, snapshots, or Block Volume backups.
It is not a replacement for Longhorn replication and does not provide RWX.
Use OCI File Storage CSI for shared filesystem semantics. Verify the OKE
installation with:

```sh
kubectl get storageclass oci-bv
kubectl -n kube-system get daemonset csi-oci-node
```

The tools cluster was validated with a temporary 50 GiB PVC and Pod: the
volume bound, mounted, accepted a marker write, and was removed with the test
namespace. The same OKE-managed class and CSI node plugin are present in
staging and production.

#### OCI Object Storage backup plan

The tools config owns a private versioned `oke-longhorn-backups` bucket, a
dedicated IAM user/customer secret key, a bucket-scoped policy, and three Vault
secrets containing the S3 credentials and OCI endpoint. External Secrets
consumes the shared credentials in all clusters, while Longhorn uses a
separate prefix per cluster:

```text
tools      -> s3://oke-longhorn-backups@sa-saopaulo-1/tools/
staging    -> s3://oke-longhorn-backups@sa-saopaulo-1/staging/
production -> s3://oke-longhorn-backups@sa-saopaulo-1/production/
```

The recurring backup job runs daily at 02:00 UTC, retains seven backups per
volume, and performs a full backup after seven incremental backups. Object
Storage lifecycle deletion is not enabled by default. Set
`OCI_LONGHORN_BACKUP_USER_EMAIL` in the uncommitted `.env`, apply the tools
config first, then allow Flux to reconcile staging and production. Terraform
state contains the customer secret key, so protect it as sensitive state.

### ExternalDNS in staging and production

Staging and production each run a separate ExternalDNS deployment in the
`external-dns` namespace. Their Flux roots reference
`gitops/core/external-dns/resources`, which contains the namespace,
Cloudflare-backed HelmRelease, and an ExternalSecret that reads the
`cloudflare-api-token` key from the shared OCI Vault through the
`oracle-vault` ClusterSecretStore.

ExternalDNS is restricted to the `hackyard.dev` zone and manages A records
from Services, Ingresses, CRD sources, and Gateway API HTTPRoutes. It uses
`sync` policy and excludes targets in `10.0.0.0/8`, so route annotations and
generated records must be reviewed before exposing workloads. The current
minimal tools root does not deploy ExternalDNS.

Check the DNS controller and its secret synchronization in either cluster:

```sh
export KUBECONFIG="$PWD/terraform/.kube.staging.config"
kubectl -n external-dns get pods
kubectl -n external-dns get helmrelease external-dns
kubectl -n external-dns get externalsecret external-secrets
kubectl -n external-dns logs deploy/external-dns
```

No application record is expected until a workload publishes a supported
annotated Service, Ingress, or HTTPRoute. The Contour load-balancer addresses
are cluster-specific and can be found with:

```sh
kubectl -n contour get svc contour-envoy
```

The former Envoy Gateway and its Envoy-specific OIDC `SecurityPolicy` objects
were removed. Contour does not consume those policies, so protected routes
must use an external authorization component or application-level OIDC before
they are enabled.

For lower-level operations, apply the stacks in this order:

```sh
terragrunt --working-dir live/oci/drg apply
terragrunt --working-dir live/oci/clusters/staging/network apply
terragrunt --working-dir live/oci/clusters/staging/oke apply
terragrunt --working-dir live/oci/clusters/staging/config apply
```

Use `plan` first for changes to an existing environment. The helper uses
`-auto-approve` because it is intended for a populated local `.env`; review a
plan manually before using it in a shared or production workflow.

## Splitting this into a new repository

When extracting this implementation from the original repository, preserve
the following groups:

1. `live/oci/` and its Terragrunt files.
2. `terraform/modules/drg/`, `terraform/modules/cluster-network/`, and
   `terraform/modules/oke-cluster/`.
3. `terraform/config/` and the GitOps tree required by the selected profile.
4. `scripts/deploy-minimal.sh`.
5. `.env.example`, `.gitignore`, `README.md`, and this document.

Do not copy generated or sensitive files:

- `.env`;
- Terraform/OpenTofu state and lock data generated inside live stacks;
- `.terragrunt-cache/` and `.terraform/` directories;
- kubeconfigs;
- OCI private keys; or
- GitHub, Vault, Flux, and Kubernetes credentials.

Before moving existing infrastructure, decide whether the new repository will
use the existing local state or a shared remote state backend. Never apply the
new Terragrunt stacks against the same OCI resources without first preserving
or importing their state; otherwise OpenTofu may try to recreate resources.

Recommended extraction validation:

```sh
terragrunt hcl fmt --check live/oci
tofu fmt -check terraform/modules
bash -n scripts/deploy-minimal.sh

for stack in \
  live/oci/drg \
  live/oci/clusters/tools/network \
  live/oci/clusters/tools/oke \
  live/oci/clusters/tools/config \
  live/oci/clusters/staging/network \
  live/oci/clusters/staging/oke \
  live/oci/clusters/staging/config \
  live/oci/clusters/production/network \
  live/oci/clusters/production/oke \
  live/oci/clusters/production/config; do
  terragrunt --working-dir "$stack" validate
done
```

## Known limitations and follow-up work

- Local state is suitable for a personal deployment but not ideal for team
  operations. Move each stack to a locked remote backend before collaboration.
- The `tools` minimal profile installs Flux, metrics-server, External Secrets,
  Contour, Grafana, kube-prometheus-stack, and single-process Mimir. Mimir is
  intentionally single-node with filesystem storage; HA and OCI Object Storage
  are follow-up work before production-scale metrics retention. See
  `docs/MONITORING.md` for the operating guide.
- The current network model allows private VCN routing but does not configure
  cross-cluster service discovery.
- Public OKE API endpoints and public load-balancer subnets should be reviewed
  against the organization’s security requirements.
- Flux roots are separated per cluster under `gitops/tools`, `gitops/staging`,
  and `gitops/production`; the manifests intentionally reuse the shared core
  resources where appropriate.
