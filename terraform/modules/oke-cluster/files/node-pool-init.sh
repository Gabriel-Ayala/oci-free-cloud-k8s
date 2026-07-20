#!/bin/bash

/usr/libexec/oci-growfs -y

curl --fail -H "Authorization: Bearer Oracle" -L0 http://169.254.169.254/opc/v2/instance/metadata/oke_init_script | base64 --decode >/var/run/oke-init.sh
bash /var/run/oke-init.sh

# Longhorn's default V1 data engine uses iSCSI to attach volumes. OKE's
# Oracle Linux image normally includes these packages, but ensure the node
# remains usable if the image contents change.
if command -v dnf >/dev/null 2>&1; then
  dnf install -y iscsi-initiator-utils nfs-utils cryptsetup device-mapper
fi
modprobe iscsi_tcp || true
systemctl enable --now iscsid
