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
| tools | `ENHANCED_CLUSTER` | `10.10.0.0/16` | `10.244.0.0/16` | `10.96.0.0/16` | 2 | `.kube.tools.config` |
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

The tools root includes the shared metrics and External Secrets resources plus
a standalone Grafana deployment under `gitops/tools/grafana`. Grafana uses a
ClusterIP service and an admin password synchronized from the OCI Vault secret
`grafana-tools-admin-password`; the password is not stored in Git.

The tools Grafana currently uses local basic authentication and the OCI Metrics
datasource plugin. It does not expose a public ingress and does not yet include
the full Prometheus/Alertmanager stack.

To access it locally:

```sh
export KUBECONFIG="$PWD/terraform/.kube.tools.config"
kubectl -n grafana port-forward svc/grafana 3000:80
curl http://127.0.0.1:3000/api/health
```

The Flux path change and manifests must be committed and pushed to the Git
repository configured in `gitops` before Flux can reconcile them permanently.
Until then, a local smoke deployment can be applied with:

```sh
kubectl apply -k gitops/tools/grafana
```

### Contour ingress in every cluster

The three cluster roots each install the shared Contour configuration from
`gitops/core/contour`. The deployment includes:

- Contour with the Gateway API CRDs;
- a `contour` GatewayClass and Gateway in the `contour` namespace;
- Envoy replicas exposed by an OCI `LoadBalancer` Service; and
- an HTTP and HTTPS listener for `*.nce.wtf`.

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
  and standalone Grafana; the full observability stack still requires its
  Prometheus/Alertmanager secrets, domains, persistence, and integrations.
- The current network model allows private VCN routing but does not configure
  cross-cluster service discovery.
- Public OKE API endpoints and public load-balancer subnets should be reviewed
  against the organization’s security requirements.
- Flux roots are separated per cluster under `gitops/tools`, `gitops/staging`,
  and `gitops/production`; the manifests intentionally reuse the shared core
  resources where appropriate.
