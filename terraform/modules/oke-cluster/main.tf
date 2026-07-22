terraform {
  required_providers {
    jq = {
      source  = "massdriver-cloud/jq"
      version = "0.2.1"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0.0"
    }
    oci = {
      source  = "oracle/oci"
      version = "~> 7.32.0"
    }
  }
}

locals {
  worker_availability_domains = length(var.worker_availability_domains) > 0 ? [
    for domain in data.oci_identity_availability_domains.ads.availability_domains : domain
    if contains(var.worker_availability_domains, domain.name)
  ] : data.oci_identity_availability_domains.ads.availability_domains
}

resource "oci_containerengine_cluster" "this" {
  compartment_id     = var.compartment_id
  kubernetes_version = var.kubernetes_version
  name               = var.cluster_name
  type               = var.cluster_type
  vcn_id             = var.vcn_id

  endpoint_config {
    is_public_ip_enabled = true
    subnet_id            = var.public_subnet_id
  }

  options {
    add_ons {
      is_kubernetes_dashboard_enabled = false
      is_tiller_enabled               = false
    }

    kubernetes_network_config {
      pods_cidr     = var.pods_cidr
      services_cidr = var.services_cidr
    }

    dynamic "open_id_connect_token_authentication_config" {
      for_each = var.enable_oidc_auth ? [1] : []

      content {
        is_open_id_connect_auth_enabled = true
        issuer_url                      = var.oidc_issuer_url
        client_id                       = var.oidc_client_id
        username_claim                  = var.oidc_username_claim
        groups_claim                    = var.oidc_groups_claim
        username_prefix                 = var.oidc_username_prefix
        groups_prefix                   = var.oidc_groups_prefix
        signing_algorithms              = ["RS256"]
      }
    }

    service_lb_subnet_ids = [var.public_subnet_id]
  }
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_id
}

data "oci_containerengine_node_pool_option" "node_pool_options" {
  node_pool_option_id = "all"
  compartment_id      = var.compartment_id
}

data "jq_query" "latest_image" {
  data  = jsonencode({ sources = jsondecode(jsonencode(data.oci_containerengine_node_pool_option.node_pool_options.sources)) })
  query = "[.sources[] | select(.source_name | test(\".*${var.worker_image_pattern}.*OKE-${replace(var.kubernetes_version, "v", "")}-.*\")) | .image_id][0]"
}

resource "oci_containerengine_node_pool" "this" {
  cluster_id         = oci_containerengine_cluster.this.id
  compartment_id     = var.compartment_id
  kubernetes_version = var.kubernetes_version
  name               = "${var.cluster_name}-node-pool"

  node_metadata = {
    user_data = base64encode(file("${path.module}/files/node-pool-init.sh"))
  }

  node_config_details {
    dynamic "placement_configs" {
      for_each = local.worker_availability_domains

      content {
        availability_domain = placement_configs.value.name
        subnet_id           = var.private_subnet_id
      }
    }

    size = var.kubernetes_worker_nodes
  }

  node_shape = var.worker_shape

  dynamic "node_shape_config" {
    for_each = var.worker_shape == "VM.Standard.A1.Flex" ? [1] : []

    content {
      memory_in_gbs = var.worker_memory_in_gbs
      ocpus         = var.worker_ocpus
    }
  }

  node_source_details {
    image_id    = jsondecode(data.jq_query.latest_image.result)
    source_type = "image"

    boot_volume_size_in_gbs = 100
  }

  initial_node_labels {
    key   = "name"
    value = var.cluster_name
  }

  ssh_public_key = var.ssh_public_key
}

data "oci_containerengine_cluster_kube_config" "this" {
  cluster_id = oci_containerengine_cluster.this.id
}

resource "local_file" "kube_config" {
  depends_on      = [oci_containerengine_node_pool.this]
  content         = data.oci_containerengine_cluster_kube_config.this.content
  filename        = var.kubeconfig_path
  file_permission = 0400
}
