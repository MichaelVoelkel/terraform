#!/bin/bash
set -eux

ON_MASTER_NODE=${ON_MASTER_NODE:-}

# make kernel modules loading at reboot
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# activate kernel modules NOW
modprobe overlay
modprobe br_netfilter

# verify that they exist
lsmod | grep br_netfilter
lsmod | grep overlay

# tell kubernetes that we use an external cloud-provider, that is,
# let it use the one from Hetzner;
# CCM acts as interim layer to let K8s use Hetzner's functionalities
mkdir -p /etc/systemd/system/kubelet.service.d
echo 'Environment="KUBELET_EXTRA_ARGS=--cloud-provider=external"
' > /etc/systemd/system/kubelet.service.d/20-hetzner-cloud.conf

# install containerd
ARCH=$(dpkg --print-architecture)
wget https://github.com/containerd/containerd/releases/download/v1.6.2/containerd-1.6.2-linux-${ARCH}.tar.gz
tar Czxvf /usr/local containerd-1.6.2-linux-${ARCH}.tar.gz
wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
mv containerd.service /usr/lib/systemd/system/
systemctl daemon-reload
systemctl enable --now containerd

# install runc, which seems to be needed for actually running the containers,
# although it seems containers still run but cgroup via systemd only works via runc (?);
# cgroups say which resources are allocated to processes
# "online" also says that CRI-O (container runtime interface to run OCI (open container interface
# which is what Kubernetes uses)) does "definitely" not work without runc;
# see also CRI-O docs, especially architecture: https://cri-o.io/
wget https://github.com/opencontainers/runc/releases/download/v1.1.6/runc.${ARCH}
install -m 755 runc.${ARCH} /usr/local/sbin/runc

# TBD: we'd need to install CNI tools probably for having some stuff that K8s needs? Let's try to omit to learn

# Install K8s
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
        deb http://packages.cloud.google.com/apt/ kubernetes-xenial main
EOF

apt-get update

echo "
Package: kubelet
Pin: version ${KUBERNETES_VERSION}-*
Pin-Priority: 1000
" >/etc/apt/preferences.d/kubelet

echo "
Package: kubeadm
Pin: version ${KUBERNETES_VERSION}-*
Pin-Priority: 1000
" >/etc/apt/preferences.d/kubeadm

# and finally
apt-get install -y kubeadm kubectl kubelet

cat <<EOF | tee /etc/sysctl.d/k8s.conf
# Allow IP forwarding for kubernetes
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                = 1
net.ipv6.conf.default.forwarding   = 1
EOF

# load settings from all configuration files
sysctl --system

echo "MV: sysctl --system"

if [[ -n $ON_MASTER_NODE ]] ;then
    echo "MV: on master node"

    kubeadm config images pull
    
    # this apparently installs the control plane
    kubeadm init \
        --pod-network-cidr=10.244.0.0/16 \
        --kubernetes-version=v$KUBERNETES_VERSION \
        --ignore-preflight-errors=NumCPU \
        --upload-certs \
        --apiserver-cert-extra-sans 10.0.0.1 \
        --skip-phases=addon/kube-proxy # apparently needed on ubuntu22 to postpone to later

    ip addr
    IP=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

    # TBD: IP should work as control-plane-endpoint but does not seem like it, so we use
    # localhost, but this should be strange enough
    #kubeadm init phase addon kube-proxy \
    #    --control-plane-endpoint="127.0.0.1:6443" \
    #    --pod-network-cidr="10.244.0.0/16"

    ctr ns ls

    ctr -n k8s.io containers list

    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    export KUBECONFIG=/etc/kubernetes/admin.conf


    kubectl get nodes

    kubectl config view

    kubectl cluster-info dump

    if [[ -n $HCLOUD_TOKEN ]]; then
        echo "Token is set."
    else
        echo "Token is not set."
    fi

    echo "Network ID is $NETWORK_ID"
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: hcloud
  namespace: kube-system
stringData:
  token: "$HCLOUD_TOKEN"
  network: "$NETWORK_ID"
---
apiVersion: v1
kind: Secret
metadata:
  name: hcloud-csi
  namespace: kube-system
stringData:
  token: "$HCLOUD_TOKEN"
EOF

    # cloud controller manager, whatever it may do
    kubectl apply -f https://raw.githubusercontent.com/hetznercloud/hcloud-cloud-controller-manager/master/deploy/ccm-networks.yaml
    
    # flannel (which is like calico or cicero or...)
    kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

    # As Kubernetes with the external cloud provider flag activated will add a taint to uninitialized nodes,
    # the cluster critical pods need to be patched to tolerate these
    kubectl -n kube-flannel patch ds kube-flannel-ds \
        --type json -p \
        '[{"op":"add","path":"/spec/template/spec/tolerations/-",' \
        '"value":{"key":"node.cloudprovider.kubernetes.io/uninitialized","value":"true","effect":"NoSchedule"}}]'

    kubectl -n kube-system patch deployment coredns \
        --type json -p \
        '[{"op":"add","path":"/spec/template/spec/tolerations/-",' \
        '"value":{"key":"node.cloudprovider.kubernetes.io/uninitialized","value":"true","effect":"NoSchedule"}}]'

    # taints explained: https://community.hetzner.com/tutorials/install-kubernetes-cluster

    # Hetzner container storage interface
    kubectl apply -f https://raw.githubusercontent.com/hetznercloud/csi-driver/main/deploy/kubernetes/hcloud-csi.yml

    echo "MV: USE THIS"
    echo ""
    cat /etc/kubernetes/admin.conf
fi