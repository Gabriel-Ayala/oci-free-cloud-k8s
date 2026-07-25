# GitLab configuration stack

This stack manages the GitLab application through the official GitLab
Terraform provider. The OCI VM remains managed by `live/oci/gitlab` and
`terraform/modules/gitlab-vm`.

The provider reads authentication from `GITLAB_TOKEN` and the API endpoint from
`GITLAB_BASE_URL`. Use a dedicated administrator or service-account token with
the minimum required lifetime and rotate it regularly. Never put the token in
this repository, a `.tfvars` file, or Terraform CLI arguments.

## Usage

```sh
set -a
source .env
set +a
export GITLAB_BASE_URL=https://gitlab.amedsaude.com.br/api/v4/

terragrunt --working-dir live/oci/gitlab/config init
terragrunt --working-dir live/oci/gitlab/config plan
terragrunt --working-dir live/oci/gitlab/config apply
```

The default configuration manages instance security settings only. Groups and
projects are opt-in through `managed_groups` and `managed_projects` inputs in
`live/oci/gitlab/config/terragrunt.hcl`.

The GitLab Omnibus OIDC configuration and its Keycloak client secret remain
outside this provider stack. They are managed by the VM hardening/cloud-init
configuration and the root-only secret file documented in `docs/GITLAB.md`.

`gitlab_application_settings` is an experimental provider resource and has no
destroy operation. Review its plan carefully before applying changes.
