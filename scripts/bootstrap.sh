#!/bin/bash
set -eu

sed -i '/nameserver 185.12.64.1/d' /run/systemd/resolve/resolv.conf
sed -i '/2a01:4ff:ff00::add:1/d' /run/systemd/resolve/resolv.conf
sed -i '/search ./d' /run/systemd/resolve/resolv.conf

cp /run/systemd/resolve/resolv.conf /etc/resolv-static.conf

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