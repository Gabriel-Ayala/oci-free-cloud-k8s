# Structure
I decided to split the OpenTofu provisioning in two parts.

* [live/oci](../live/oci/) for Terragrunt stack orchestration
* [modules](modules/) for the shared DRG, per-cluster networking, and OKE resources
* [cluster-config](config/) for everything depending on a k8s API

The recommended deployment order is:

1. Shared DRG: `live/oci/drg`
2. Cluster network: `live/oci/clusters/<name>/network`
3. OKE cluster: `live/oci/clusters/<name>/oke`
4. Kubernetes configuration: `live/oci/clusters/<name>/config`

The original [infra](infra/) root is retained for compatibility with existing
single-VCN state and should not be used for new connected clusters.

This way I mitigate long OpenTofu runs and provider dependency.

See [`docs/MULTI_CLUSTER.md`](../docs/MULTI_CLUSTER.md) for the complete
architecture, environment variables, migration notes, limits, and validation
commands used when extracting this layout into a separate repository.
