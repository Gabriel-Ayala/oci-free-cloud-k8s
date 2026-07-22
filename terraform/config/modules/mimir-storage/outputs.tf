output "bucket_name" {
  value = oci_objectstorage_bucket.this.name
}

output "namespace" {
  value = data.oci_objectstorage_namespace.this.namespace
}

output "endpoint" {
  value = "${data.oci_objectstorage_namespace.this.namespace}.compat.objectstorage.${var.region}.oci.customer-oci.com"
}
