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
  cluster_name            = "staging"
  cluster_id              = dependency.oke.outputs.k8s_cluster_id
  gitops_path             = "gitops/staging"
  enable_external_secrets = true
  kubeconfig_path         = "${get_repo_root()}/terraform/.kube.staging.config"
}
