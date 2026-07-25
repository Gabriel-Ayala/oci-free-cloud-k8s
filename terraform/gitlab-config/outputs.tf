output "managed_group_ids" {
  description = "IDs of groups managed by this stack."
  value       = { for key, group in gitlab_group.managed : key => group.id }
}

output "managed_project_ids" {
  description = "IDs of projects managed by this stack."
  value       = { for key, project in gitlab_project.managed : key => project.id }
}
