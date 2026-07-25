output "instance_id" {
  value = oci_core_instance.gitlab.id
}

output "public_ip" {
  value = data.oci_core_vnic.gitlab.public_ip_address
}

output "data_volume_id" {
  value = oci_core_volume.gitlab_data.id
}
