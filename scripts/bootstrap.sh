#!/bin/bash
set -eu

# apparently swap needs to be disabled for best stability
swapoff -a
# action is d, so it deletes lines that contain the word "swap"
sed -i '/swap/d' /etc/fstab

SSH_PORT=${SSH_PORT:-}

echo "Port $SSH_PORT" > /etc/ssh/sshd_config.d/port.conf
systemctl restart sshd

apt-get update
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common