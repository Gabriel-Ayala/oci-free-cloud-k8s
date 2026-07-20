output "k8s_cluster_id" {
  value = oci_containerengine_cluster.this.id
}

output "node_pool_id" {
  value = oci_containerengine_node_pool.this.id
}

output "kubernetes_version" {
  value = var.kubernetes_version
}

output "kubeconfig_path" {
  value = var.kubeconfig_path
}
