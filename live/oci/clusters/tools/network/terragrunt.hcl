include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/terraform/modules/cluster-network"
}

dependency "drg" {
  config_path = "../../../drg"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    drg_id             = "ocid1.drg.oc1..mock"
    drg_route_table_id = "ocid1.drgroutetable.oc1..mock"
  }
}

inputs = {
  cluster_name             = "tools"
  vcn_cidr                 = "10.10.0.0/16"
  public_subnet_cidr       = "10.10.0.0/24"
  private_subnet_cidr      = "10.10.1.0/24"
  peer_vcn_cidrs           = ["10.20.0.0/16", "10.30.0.0/16"]
  drg_id                   = dependency.drg.outputs.drg_id
  drg_route_table_id       = dependency.drg.outputs.drg_route_table_id
  reserve_mimir_private_ip = true
  mimir_private_ip_address = "10.10.1.250"
}
