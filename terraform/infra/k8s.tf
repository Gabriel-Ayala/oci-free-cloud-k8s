resource "oci_containerengine_cluster" "k8s_cluster" {
  compartment_id     = var.compartment_id
  kubernetes_version = var.kubernetes_version
  name               = var.cluster_name
  vcn_id             = module.vcn.vcn_id
  endpoint_config {
    is_public_ip_enabled = true
    subnet_id            = oci_core_subnet.vcn_public_subnet.id
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
    service_lb_subnet_ids = [oci_core_subnet.vcn_public_subnet.id]
  }
}

data "oci_containerengine_cluster_kube_config" "k8s_cluster_kube_config" {
  #Required
  cluster_id = oci_containerengine_cluster.k8s_cluster.id
}

resource "local_file" "kube_config" {
  depends_on      = [oci_containerengine_node_pool.k8s_node_pool]
  content         = data.oci_containerengine_cluster_kube_config.k8s_cluster_kube_config.content
  filename        = var.kubeconfig_path
  file_permission = 0400
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
  query = "[.sources[] | select(.source_name | test(\".*${var.worker_image_pattern}.*OKE-${replace(var.kubernetes_version, "v", "")}-.*\")?) .image_id][0]"
}

resource "oci_containerengine_node_pool" "k8s_node_pool" {
  cluster_id         = oci_containerengine_cluster.k8s_cluster.id
  compartment_id     = var.compartment_id
  kubernetes_version = var.kubernetes_version
  name               = "${var.cluster_name}-node-pool"

  node_metadata = {
    user_data = base64encode(file("files/node-pool-init.sh"))
  }

  node_config_details {
    dynamic "placement_configs" {
      for_each = local.worker_availability_domains

      content {
        availability_domain = placement_configs.value.name
        subnet_id           = oci_core_subnet.vcn_private_subnet.id
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
