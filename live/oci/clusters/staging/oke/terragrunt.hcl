include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/terraform/modules/oke-cluster"
}

dependency "network" {
  config_path = "../network"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    vcn_id            = "ocid1.vcn.oc1..mock"
    public_subnet_id  = "ocid1.subnet.oc1..mock"
    private_subnet_id = "ocid1.subnet.oc1..mock"
  }
}

inputs = {
  cluster_name            = "staging"
  cluster_type            = "ENHANCED_CLUSTER"
  vcn_id                  = dependency.network.outputs.vcn_id
  public_subnet_id        = dependency.network.outputs.public_subnet_id
  private_subnet_id       = dependency.network.outputs.private_subnet_id
  pods_cidr               = "10.245.0.0/16"
  services_cidr           = "10.97.0.0/16"
  kubernetes_worker_nodes = 2
  kubeconfig_path         = "${get_repo_root()}/terraform/.kube.staging.config"
}
