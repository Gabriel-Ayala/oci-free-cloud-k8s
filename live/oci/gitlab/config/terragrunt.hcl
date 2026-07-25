include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/terraform/gitlab-config"
}

inputs = {
  gitlab_base_url = "https://gitlab.amedsaude.com.br/api/v4/"
}
