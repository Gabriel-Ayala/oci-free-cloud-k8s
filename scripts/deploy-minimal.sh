#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v terragrunt >/dev/null 2>&1; then
  echo "Terragrunt is required but was not found in PATH." >&2
  exit 1
fi

if [[ ! -f "$repo_root/.env" ]]; then
  echo "Missing $repo_root/.env; copy .env.example first." >&2
  exit 1
fi

# shellcheck disable=SC1091
set -a
source "$repo_root/.env"
set +a

export OCI_CONFIG_FILE="${OCI_CONFIG_FILE:-}"
export OCI_CONFIG_PROFILE="${OCI_CONFIG_PROFILE:-DEFAULT}"

: "${OCI_COMPARTMENT_ID:?Set OCI_COMPARTMENT_ID in .env}"
: "${OCI_REGION:?Set OCI_REGION in .env}"

cluster_name="${CLUSTER_NAME:-tools}"

if [[ -z "${TF_VAR_vault_id:-}" && "$cluster_name" != "tools" ]]; then
  tools_config="$repo_root/live/oci/clusters/tools/config"
  if [[ -d "$tools_config" ]]; then
    TF_VAR_vault_id="$(terragrunt --working-dir "$tools_config" output -raw external_secrets_vault_id 2>/dev/null || true)"
    export TF_VAR_vault_id
  fi
fi

if [[ "$cluster_name" != "tools" && -z "${TF_VAR_vault_id:-}" ]]; then
  echo "TF_VAR_vault_id must reference an existing OCI Vault when deploying $cluster_name." >&2
  exit 1
fi

if [[ ! "$cluster_name" =~ ^[a-z][a-z0-9-]{0,62}[a-z0-9]$ ]]; then
  echo "CLUSTER_NAME must start with a letter, end with a letter or number, and contain only lowercase letters, numbers, and hyphens." >&2
  exit 1
fi

cluster_root="$repo_root/live/oci/clusters/$cluster_name"
if [[ ! -d "$cluster_root" ]]; then
  echo "Unknown cluster '$cluster_name'. Add its Terragrunt stack under $cluster_root first." >&2
  exit 1
fi

run_stack() {
  local stack_path="$1"
  echo "Applying $stack_path"
  if ! terragrunt --working-dir "$stack_path" apply -input=false -auto-approve; then
    echo "Deployment failed in $stack_path; stopping." >&2
    exit 1
  fi
}

run_stack "$repo_root/live/oci/drg"
run_stack "$cluster_root/network"
run_stack "$cluster_root/oke"
run_stack "$cluster_root/config"

kubeconfig_path="${KUBECONFIG_PATH:-$repo_root/terraform/.kube.${cluster_name}.config}"
if [[ ! -f "$kubeconfig_path" ]]; then
  echo "Terragrunt did not create $kubeconfig_path" >&2
  exit 1
fi

echo "Minimal deployment completed."
echo "Cluster: $cluster_name"
echo "Use: export KUBECONFIG=\"$kubeconfig_path\""
