variable "gitlab_base_url" {
  type        = string
  description = "GitLab API base URL. Must end with /api/v4/."
  default     = "https://gitlab.amedsaude.com.br/api/v4/"

  validation {
    condition     = endswith(var.gitlab_base_url, "/api/v4/")
    error_message = "gitlab_base_url must end with /api/v4/."
  }
}

variable "gitlab_token" {
  type        = string
  description = "Administrative GitLab token. Prefer GITLAB_TOKEN instead of tfvars."
  sensitive   = true
  default     = null
}

variable "manage_application_settings" {
  type        = bool
  description = "Whether this stack manages instance-wide GitLab settings."
  default     = true
}

variable "managed_groups" {
  type = map(object({
    name                   = string
    path                   = string
    description            = optional(string, "")
    visibility             = optional(string, "private")
    project_creation_level = optional(string, "maintainer")
  }))
  description = "Top-level GitLab groups to manage. Empty by default."
  default     = {}
}

variable "managed_projects" {
  type = map(object({
    name                   = string
    namespace_group        = optional(string)
    description            = optional(string, "")
    visibility             = optional(string, "private")
    initialize_with_readme = optional(bool, false)
    default_branch         = optional(string, "main")
    issues_enabled         = optional(bool, true)
    merge_requests_enabled = optional(bool, true)
    wiki_enabled           = optional(bool, false)
    snippets_enabled       = optional(bool, false)
  }))
  description = "GitLab projects to manage. namespace_group references managed_groups keys."
  default     = {}
}
