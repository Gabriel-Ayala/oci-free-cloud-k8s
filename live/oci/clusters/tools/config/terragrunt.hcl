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

inputs = {
  cluster_name                    = "tools"
  cluster_id                      = dependency.oke.outputs.k8s_cluster_id
  kubeconfig_path                 = "${get_repo_root()}/terraform/.kube.tools.config"
  gitops_path                     = "gitops/tools"
  enable_external_secrets         = true
  external_secrets_principal_type = "InstancePrincipal"
  create_external_secrets_vault   = true
  enable_github_webhook           = false
  enable_ingress                  = true
  enable_grafana_iam              = true
}
