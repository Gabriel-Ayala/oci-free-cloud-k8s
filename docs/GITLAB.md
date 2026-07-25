# GitLab CE VM

GitLab CE is deployed as a dedicated OCI Compute VM rather than as a workload
on OKE. This keeps GitLab independent from the tools cluster and avoids adding
GitLab's PostgreSQL, Redis, and persistent storage requirements to Kubernetes.

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

## First-boot checks

```sh
ssh ubuntu@<public-ip> sudo gitlab-ctl status
ssh ubuntu@<public-ip> sudo gitlab-rake gitlab:check SANITIZE=true
curl --fail --location https://gitlab.amedsaude.com.br/-/health
git clone git@gitlab.amedsaude.com.br:group/project.git
```

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

Do not commit the VM state, kubeconfigs, `.env`, GitLab secrets, or initial
password to this repository.
