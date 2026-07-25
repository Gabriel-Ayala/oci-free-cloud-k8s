# GitLab CE

GitLab CE is deployed as a dedicated OCI Compute VM rather than as a workload
on OKE. This keeps GitLab independent from the tools cluster and avoids adding
GitLab's PostgreSQL, Redis, and persistent storage requirements to Kubernetes.

The public service URL is:

```text
https://gitlab.amedsaude.com.br
```

The VM uses an OCI Ampere A1 Flex shape, a persistent OCI Block Volume mounted
at `/var/opt/gitlab`, and the tools public subnet. GitLab's bundled PostgreSQL,
Redis, Gitaly, Puma, Sidekiq, Workhorse, and NGINX run on the VM.

## Provisioning

The stack is under `live/oci/gitlab` and depends on the tools public subnet.
Deploy it after the tools network exists:

```sh
set -a
source .env
set +a
terragrunt --working-dir live/oci/gitlab init
terragrunt --working-dir live/oci/gitlab plan
terragrunt --working-dir live/oci/gitlab apply
terragrunt --working-dir live/oci/gitlab output public_ip
```

The default profile is an Ampere A1 Flex VM with 4 OCPUs, 16 GiB RAM, a 60 GiB
boot volume, and a 200 GiB data volume. Adjust the inputs in
`live/oci/gitlab/terragrunt.hcl` before applying if the GitLab workload grows.

The module selects the newest Canonical Ubuntu 24.04 image matching the chosen
shape. Cloud-init formats and mounts the data volume at `/var/opt/gitlab`, then
installs GitLab CE using the official package repository with
`https://gitlab.amedsaude.com.br` as the external URL. Automatic Let's Encrypt
issuance is disabled during first boot because the DNS record does not exist
until the VM's public IP is known. HTTP-to-HTTPS redirect is enabled from the
beginning, including the ACME challenge exception.

## DNS and access

After the VM is created, create this Cloudflare DNS record using the output IP:

| Name | Type | Target | Proxy |
| --- | --- | --- | --- |
| `gitlab.amedsaude.com.br` | A | `terragrunt output -raw public_ip` | DNS only initially |

Keep the record DNS-only until GitLab HTTPS and SSH access are tested. After
DNS resolves to the VM, enable certificate issuance and reconfigure GitLab:

```sh
sudo tee -a /etc/gitlab/gitlab.rb <<'EOF'
letsencrypt['enable'] = true
letsencrypt['contact_emails'] = ['admin@amedsaude.com.br']
EOF
sudo gitlab-ctl reconfigure
```

If Cloudflare proxying is enabled later, use Full (strict) TLS mode and confirm
that GitLab SSH continues to use the VM's public address.

The tools subnet permits TCP 22, 80, 443, and the existing OKE API port 6443.
The VM firewall and GitLab configuration should still be reviewed after the
first boot.

## Keycloak OIDC and hardening

GitLab uses the existing Keycloak `platform` realm. Create a confidential
Keycloak client named `gitlab` with these values:

| Setting | Value |
| --- | --- |
| Client authentication | On |
| Standard flow | On |
| Direct access grants | Off |
| PKCE method | S256 |
| Valid redirect URI | `https://gitlab.amedsaude.com.br/users/auth/openid_connect/callback` |
| Web origin | `https://gitlab.amedsaude.com.br` |

Install the client secret on the VM with root-only permissions. Do not put it
in Terraform variables, cloud-init metadata, Git, or shell history:

```sh
ssh ubuntu@<public-ip> 'sudo install -o root -g root -m 0600 /dev/stdin /etc/gitlab/oidc-client-secret' < client-secret.txt
```

Then append the OIDC provider configuration and reconfigure GitLab:

```sh
ssh ubuntu@<public-ip> 'sudo tee -a /etc/gitlab/gitlab.rb >/dev/null' <<'EOF'
gitlab_rails['omniauth_auto_link_user'] = ['openid_connect']
gitlab_rails['omniauth_providers'] = [{
  name: 'openid_connect',
  label: 'Keycloak',
  args: {
    name: 'openid_connect',
    scope: ['openid', 'profile', 'email'],
    response_type: 'code',
    issuer: 'https://keycloak-inova.amedsaude.com.br/realms/platform',
    discovery: true,
    client_auth_method: 'basic',
    uid_field: 'sub',
    pkce: true,
    client_options: {
      identifier: 'gitlab',
      secret: File.read('/etc/gitlab/oidc-client-secret').strip,
      redirect_uri: 'https://gitlab.amedsaude.com.br/users/auth/openid_connect/callback'
    }
  }
}]
EOF
ssh ubuntu@<public-ip> 'sudo gitlab-ctl reconfigure'
```

New OIDC users are blocked pending administrator approval. Keep the local
root account available until a Keycloak administrator account has successfully
logged in. Keycloak must enforce MFA for the users or groups allowed to access
GitLab; GitLab’s OIDC bypass for two-factor authentication is disabled.

The VM baseline also disables SSH password/root login, enables Fail2ban and
unattended security updates, restricts GitLab TLS to TLS 1.2/1.3, enables HSTS,
disables TLS session tickets, disables public signup, and rate-limits Git HTTP
Basic authentication attempts.

## GitLab configuration stack

GitLab resources and instance settings are managed separately from the OCI VM:

```text
live/oci/gitlab/                  VM stack
live/oci/gitlab/config/           Terragrunt wrapper
terraform/modules/gitlab-vm/      reusable OCI VM module
terraform/gitlab-config/          GitLab provider stack
```

Set `GITLAB_TOKEN` and run the configuration stack only after GitLab is
reachable:

```sh
set -a
source .env
set +a
export GITLAB_BASE_URL=https://gitlab.amedsaude.com.br/api/v4/
terragrunt --working-dir live/oci/gitlab/config plan
```

The stack defaults to instance security settings and creates no groups or
projects until they are explicitly added to `managed_groups` and
`managed_projects`. The provider supports groups, projects, memberships,
variables, protected branches, runners, and hooks; keep tokens and secret
values outside the repository.

### Managed groups

The configuration stack currently manages these private top-level groups:

| Group | Path | Purpose |
| --- | --- | --- |
| Platform | `platform` | Infrastructure, platform engineering, and shared services |
| Applications | `applications` | Application source code and delivery projects |

Add projects under these groups by editing `managed_projects` in
`live/oci/gitlab/config/terragrunt.hcl`. A project’s `namespace_group` must
reference either `platform` or `applications`.


After changing the configuration:

```sh
set -a
source .env
set +a
export GITLAB_BASE_URL=https://gitlab.amedsaude.com.br/api/v4/
terragrunt --working-dir live/oci/gitlab/config plan
terragrunt --working-dir live/oci/gitlab/config apply
```

Do not create or rename managed groups manually in the GitLab UI; Terraform
state is the source of truth for resources declared in the stack.

## Administrator access

The initial Omnibus administrator is `root`. Retrieve the one-time bootstrap
password directly on the VM and change it immediately:

```sh
ssh ubuntu@<public-ip>
sudo cat /etc/gitlab/initial_root_password
```

Use the local root account as an emergency break-glass account until Keycloak
login has been tested with an administrator identity. OIDC users are initially
blocked for administrator approval. Git operations use SSH keys or GitLab
personal/deploy tokens; Git HTTP password authentication is disabled.

## First-boot checks

```sh
ssh ubuntu@<public-ip> sudo gitlab-ctl status
ssh ubuntu@<public-ip> sudo gitlab-rake gitlab:check SANITIZE=true
curl --fail --location --silent --show-error \
  https://gitlab.amedsaude.com.br/users/sign_in >/dev/null
curl --fail --location --silent --show-error \
  https://keycloak-inova.amedsaude.com.br/realms/platform/.well-known/openid-configuration \
  | jq -e '.issuer == "https://keycloak-inova.amedsaude.com.br/realms/platform"'
git clone git@gitlab.amedsaude.com.br:group/project.git
```

Confirm the sign-in page contains the `Sign in with Keycloak` button. For a
provider health check, verify the Keycloak client callback remains exactly
`https://gitlab.amedsaude.com.br/users/auth/openid_connect/callback`.

The initial root password is available only on the VM:

```sh
sudo cat /etc/gitlab/initial_root_password
```

Change it immediately and create a non-root administrator account.

## Backups

GitLab application backups and OCI block-volume backups are separate. Configure
both before storing important repositories:

```sh
sudo gitlab-backup create
sudo gitlab-rake gitlab:backup:verify BACKUP=<backup-id>
```

Create an OCI backup policy for the `gitlab-data` volume and periodically test
restoring the volume and GitLab backup to an isolated VM. Repository data,
database data, uploaded artifacts, and the GitLab secrets file must all be
covered by the recovery procedure.

At minimum, retain:

- GitLab application backups from `/var/opt/gitlab/backups`.
- The `gitlab-data` OCI Block Volume or its OCI volume backups.
- `/etc/gitlab/gitlab-secrets.json`.
- `/etc/gitlab/gitlab.rb`, including the OIDC configuration.
- The Keycloak GitLab client secret, stored separately with restricted access.

Test both a GitLab application restore and a complete VM/volume recovery
before relying on the installation for production repositories.

## Upgrade and maintenance

Check the current status before upgrades:

```sh
ssh ubuntu@<public-ip> sudo gitlab-ctl status
ssh ubuntu@<public-ip> sudo gitlab-rake gitlab:check SANITIZE=true
ssh ubuntu@<public-ip> sudo gitlab-ctl backup-etc
```

Create and verify a backup before upgrading GitLab. Keep the GitLab package
version pinned in `gitlab_package_version` when a controlled upgrade is
required; otherwise the VM module installs the newest package available from
the GitLab repository during provisioning. Re-run `gitlab-ctl reconfigure`
after changing `/etc/gitlab/gitlab.rb`.

Do not commit the VM state, kubeconfigs, `.env`, GitLab secrets, or initial
password to this repository.
