include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/terraform/modules/gitlab-vm"
}

dependency "tools_network" {
  config_path = "../clusters/tools/network"

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    public_subnet_id = "ocid1.subnet.oc1..mock"
  }
}

inputs = {
  subnet_id             = dependency.tools_network.outputs.public_subnet_id
  external_url          = "https://gitlab.amedsaude.com.br"
  shape                 = "VM.Standard.A1.Flex"
  ocpus                 = 4
  memory_in_gbs         = 16
  data_volume_size_in_gbs = 200
}
