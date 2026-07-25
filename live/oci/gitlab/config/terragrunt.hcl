include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/terraform/gitlab-config"
}

inputs = {
  gitlab_base_url = "https://gitlab.amedsaude.com.br/api/v4/"

  managed_groups = {
    platform = {
      name        = "Platform"
      path        = "platform"
      description = "Platform engineering, infrastructure, and shared services"
      visibility  = "private"
    }
    applications = {
      name        = "Applications"
      path        = "applications"
      description = "Application source code and delivery projects"
      visibility  = "private"
    }
  }

  managed_projects = {
    platform_control = {
      name                   = "Platform Control"
      namespace_group        = "platform"
      description            = "Platform control plane, automation, and infrastructure configuration"
      visibility             = "private"
      initialize_with_readme = true
      default_branch         = "main"
    }
  }
}
