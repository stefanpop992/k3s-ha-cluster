#!/usr/bin/env bash
# Skapar 6 Ubuntu-VM:ar med Multipass (3 control-plane + 3 workers)
# och genererar Ansible-inventory automatiskt.
set -euo pipefail
cd "$(dirname "$0")"

UBUNTU_IMAGE="${UBUNTU_IMAGE:-24.04}"
CP_NODES=(cp1 cp2 cp3)
WORKER_NODES=(worker1 worker2 worker3)
SSH_PUBKEY_FILE="${SSH_PUBKEY_FILE:-$HOME/.ssh/id_ed25519.pub}"

command -v multipass >/dev/null || { echo "Installera Multipass först"; exit 1; }

if [[ ! -f "$SSH_PUBKEY_FILE" ]]; then
  echo "Ingen SSH-nyckel hittad – skapar $SSH_PUBKEY_FILE"
  ssh-keygen -t ed25519 -N "" -f "${SSH_PUBKEY_FILE%.pub}"
fi

cat > cloud-init.yaml <<EOF
#cloud-config
users:
  - default
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - $(cat "$SSH_PUBKEY_FILE")
package_update: true
packages: [curl]
EOF

launch() {
  local name=$1 cpus=$2 mem=$3 disk=$4
  if multipass info "$name" >/dev/null 2>&1; then
    echo "✔ $name finns redan"
  else
    echo "➜ Skapar $name ($cpus CPU, $mem RAM)"
    multipass launch "$UBUNTU_IMAGE" --name "$name" --cpus "$cpus" \
      --memory "$mem" --disk "$disk" --cloud-init cloud-init.yaml
  fi
}

for n in "${CP_NODES[@]}";     do launch "$n" 2 4G 10G; done
for n in "${WORKER_NODES[@]}"; do launch "$n" 2 4G 10G; done

ip_of() { multipass info "$1" --format csv | tail -1 | cut -d, -f3; }

{
  echo "[control_plane]"
  for n in "${CP_NODES[@]}"; do echo "$n ansible_host=$(ip_of "$n")"; done
  echo
  echo "[workers]"
  for n in "${WORKER_NODES[@]}"; do echo "$n ansible_host=$(ip_of "$n")"; done
  echo
  echo "[k3s_cluster:children]"
  echo "control_plane"
  echo "workers"
  echo
  echo "[k3s_cluster:vars]"
  echo "ansible_user=ubuntu"
  echo "ansible_ssh_private_key_file=${SSH_PUBKEY_FILE%.pub}"
  echo "ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'"
} > inventory.ini

echo; echo "Klart! inventory.ini:"; cat inventory.ini
echo; echo "Nästa steg: ansible-playbook site.yml"
