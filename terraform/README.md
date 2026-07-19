# Structure
I decided to split the OpenTofu provisioning in two parts.

* [cluster-infra](infra/) for everything leading to a functioning k8s API
* [cluster-config](config/) for everything depending on a k8s API

This way I mitigate long OpenTofu runs and provider dependency.
