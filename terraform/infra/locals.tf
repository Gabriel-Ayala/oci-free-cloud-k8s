locals {
  # OCI VCN DNS labels are limited to 15 characters and cannot contain hyphens.
  vcn_dns_label = substr("${replace(var.cluster_name, "-", "")}vcn", 0, 15)

  worker_availability_domains = length(var.worker_availability_domains) > 0 ? [
    for domain in data.oci_identity_availability_domains.ads.availability_domains : domain
    if contains(var.worker_availability_domains, domain.name)
  ] : data.oci_identity_availability_domains.ads.availability_domains
}
