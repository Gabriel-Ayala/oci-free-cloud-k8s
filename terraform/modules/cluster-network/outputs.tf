output "vcn_id" {
  value = module.vcn.vcn_id
}

output "public_subnet_id" {
  value = oci_core_subnet.public.id
}

output "private_subnet_id" {
  value = oci_core_subnet.private.id
}

output "mimir_private_ip_id" {
  value = try(oci_core_private_ip.mimir[0].id, "")
}

output "mimir_private_ip_address" {
  value = try(oci_core_private_ip.mimir[0].ip_address, "")
}
