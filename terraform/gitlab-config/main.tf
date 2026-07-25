resource "gitlab_application_settings" "instance" {
  count = var.manage_application_settings ? 1 : 0

  admin_mode                                 = true
  allow_project_creation_for_guest_and_below = false
  allow_runner_registration_token            = false
  can_create_group                           = false
  default_branch_name                        = "main"
  default_group_visibility                   = "private"
  default_project_creation                   = 0
  default_project_visibility                 = "private"
  default_snippet_visibility                 = "private"
  dns_rebinding_protection_enabled           = true
  enabled_git_access_protocol                = "ssh"
  gravatar_enabled                           = false
  import_sources                             = ["github", "bitbucket", "bitbucket_server", "fogbugz", "git", "gitlab_project", "gitea", "manifest"]
  password_authentication_enabled_for_git    = false
  password_authentication_enabled_for_web    = true
  pages_domain_verification_enabled          = true
  signup_enabled                             = false
  user_oauth_applications                    = false
}

resource "gitlab_group" "managed" {
  for_each = var.managed_groups

  name                   = each.value.name
  path                   = each.value.path
  description            = each.value.description
  visibility_level       = each.value.visibility
  project_creation_level = each.value.project_creation_level
}

resource "gitlab_project" "managed" {
  for_each = var.managed_projects

  name                   = each.value.name
  namespace_id           = try(gitlab_group.managed[each.value.namespace_group].id, null)
  description            = each.value.description
  visibility_level       = each.value.visibility
  initialize_with_readme = each.value.initialize_with_readme
  default_branch         = each.value.default_branch
  issues_enabled         = each.value.issues_enabled
  merge_requests_enabled = each.value.merge_requests_enabled
  wiki_enabled           = each.value.wiki_enabled
  snippets_enabled       = each.value.snippets_enabled

  lifecycle {
    precondition {
      condition     = try(each.value.namespace_group, null) == null || contains(keys(var.managed_groups), each.value.namespace_group)
      error_message = "managed_projects.namespace_group must reference a key in managed_groups."
    }
  }
}
