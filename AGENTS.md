# Repository Guidelines

## Project Structure & Module Organization

- `terraform/infra/` provisions OCI networking, the OKE cluster, worker nodes, and kubeconfig.
- `terraform/config/` configures Kubernetes providers and installs Flux plus optional OCI/Kubernetes integrations.
- `gitops/core/` contains Flux, HelmRelease, Kustomize, and application manifests. Use `kustomization.yaml` for the minimal profile and `kustomization.full.yaml` for the complete stack.
- `scripts/` contains operational helpers, including `deploy-minimal.sh`.
- `README.md`, `terraform/README.md`, and `DESIGN.md` describe deployment and architecture. There is no dedicated application source tree or test suite.

## Build, Test, and Development Commands

This is infrastructure code; “build” means validating and applying OpenTofu.

```sh
tofu -chdir=terraform/infra init -backend=false
tofu -chdir=terraform/infra fmt -check
tofu -chdir=terraform/infra validate
tofu -chdir=terraform/infra plan
tofu -chdir=terraform/config init -backend=false
tofu -chdir=terraform/config validate
./scripts/deploy-minimal.sh
```

Run the deployment script only with a populated, uncommitted `.env`. After deployment, set `KUBECONFIG=terraform/.kube.config` and inspect with `kubectl get nodes` and `kubectl get pods -A`.

## Coding Style & Naming Conventions

Use two spaces for HCL/YAML indentation and format HCL with `tofu fmt`. Keep Terraform files focused by concern (`networking.tf`, `k8s.tf`, `subnets.tf`). Use lowercase kebab-case for Kubernetes names and descriptive snake_case for Terraform variables and resources. Keep profile-specific changes in the appropriate Kustomize overlay or manifest directory.

## Testing Guidelines

No automated unit or integration tests are currently defined. Every infrastructure change should pass `tofu fmt -check` and `tofu validate` in each changed stack, followed by a reviewed `tofu plan`. For Kubernetes changes, verify Flux reconciliation with `kubectl get kustomizations -n flux-system` and check affected pods/events.

## Commit & Pull Request Guidelines

Use short, imperative Conventional Commit-style subjects such as `feat:`, `fix:`, `chore(deps):`, or `docs:`. Pull requests should explain the OCI/Kubernetes impact, identify changed profiles or resources, include validation commands and results, and call out required secrets, `.env` values, or cost implications. Never commit `.env`, kubeconfigs, private keys, Terraform state, or generated credentials.

## Security & Configuration Tips

Treat `.env` and `*.tfvars` as sensitive local configuration. Prefer OCI Vault and External Secrets for runtime credentials. Review plans carefully before applying changes that create load balancers, paid compute shapes, public IPs, IAM users, or policies.
