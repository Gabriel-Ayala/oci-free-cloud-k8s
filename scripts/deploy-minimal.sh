#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v tofu >/dev/null 2>&1; then
  echo "OpenTofu (tofu) is required but was not found in PATH." >&2
  exit 1
fi

if [[ ! -f "$repo_root/.env" ]]; then
  echo "Missing $repo_root/.env; copy .env.example first." >&2
  exit 1
fi

# shellcheck disable=SC1091
source "$repo_root/.env"

: "${OCI_COMPARTMENT_ID:?Set OCI_COMPARTMENT_ID in .env}"
: "${OCI_REGION:?Set OCI_REGION in .env}"

export TF_VAR_compartment_id="$OCI_COMPARTMENT_ID"
export TF_VAR_region="$OCI_REGION"
export TF_VAR_git_url="https://github.com/Gabriel-Ayala/oci-free-cloud-k8s.git"
export TF_VAR_gh_org="Gabriel-Ayala"
export TF_VAR_gh_repository="oci-free-cloud-k8s"
export TF_VAR_git_auth_enabled=false
export TF_VAR_enable_github_webhook=false
export TF_VAR_enable_external_secrets=false
export TF_VAR_enable_ingress=false
export TF_VAR_enable_grafana_iam=false

infra_dir="$repo_root/terraform/infra"
config_dir="$repo_root/terraform/config"

tofu -chdir="$infra_dir" init -backend=false -input=false
tofu -chdir="$infra_dir" apply -input=false -auto-approve

if [[ ! -f "$repo_root/terraform/.kube.config" ]]; then
  echo "OpenTofu did not create terraform/.kube.config" >&2
  exit 1
fi

tofu -chdir="$config_dir" init -backend=false -input=false
tofu -chdir="$config_dir" apply -input=false -auto-approve

echo "Minimal deployment completed."
echo "Use: export KUBECONFIG=\"$repo_root/terraform/.kube.config\""
