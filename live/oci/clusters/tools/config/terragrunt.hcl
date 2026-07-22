include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/terraform/config"
}

dependency "oke" {
  config_path = "../oke"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    k8s_cluster_id = "ocid1.cluster.oc1..mock"
  }
}

dependency "network" {
  config_path = "../network"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    private_subnet_id        = "ocid1.subnet.oc1..mock"
    mimir_private_ip_id      = "ocid1.privateip.oc1..mock"
    mimir_private_ip_address = "10.10.1.250"
  }
}

inputs = {
  cluster_name                    = "tools"
  cluster_id                      = dependency.oke.outputs.k8s_cluster_id
  kubeconfig_path                 = "${get_repo_root()}/terraform/.kube.tools.config"
  gitops_path                     = "gitops/tools"
  enable_external_secrets         = true
  enable_keycloak                 = true
  external_secrets_principal_type = "InstancePrincipal"
  create_external_secrets_vault   = true
  enable_longhorn_backup          = true
  longhorn_backup_user_email      = get_env("OCI_LONGHORN_BACKUP_USER_EMAIL", "")
  enable_mimir_storage            = true
  mimir_storage_user_email        = get_env("OCI_MIMIR_STORAGE_USER_EMAIL", "")
  private_subnet_id               = dependency.network.outputs.private_subnet_id
  mimir_private_ip_id             = dependency.network.outputs.mimir_private_ip_id
  mimir_private_ip_address        = dependency.network.outputs.mimir_private_ip_address
  enable_github_webhook           = false
  enable_ingress                  = true
  enable_grafana_iam              = true
}
