provider "hcloud" {
    token = var.hcloud_token
}

resource "hcloud_ssh_key" "k8s_admin_key" {
  name       = "k8s_admin_key"
  public_key = file(var.ssh_public_key_filepath)
}

resource "hcloud_network" "network" {
    name = "kubenet"
    ip_range = "10.88.0.0/16"
}

resource "hcloud_network_subnet" "kubenet" {
  network_id = hcloud_network.network.id
  type = "server"
  network_zone = "eu-central"
  ip_range   = "10.88.0.0/16"
}

resource "hcloud_server" "master" {
    count = var.master_node_count
    name = "${var.cluster_name}-master-${count.index + 1}"
    location = var.location
    server_type = var.master_type
    image = var.node_image
    ssh_keys = [hcloud_ssh_key.k8s_admin_key.id]

    connection {
        host = self.ipv4_address
        type = "ssh"
        private_key = file(var.ssh_private_key_filepath)
    }

    provisioner "file" {
        source = "scripts/bootstrap.sh"
        destination = "/root/bootstrap.sh"
    }

    provisioner "remote-exec" {
        inline = ["SSH_PORT=${var.ssh_port} bash /root/bootstrap.sh"]
    }
}

resource "hcloud_server" "worker" {
    count = var.worker_node_count
    name = "${var.cluster_name}-worker-${count.index + 1}"
    location = var.location
    server_type = var.worker_type
    image = var.node_image
    ssh_keys = [hcloud_ssh_key.k8s_admin_key.id]

    connection {
        host = self.ipv4_address
        type = "ssh"
        private_key = file(var.ssh_private_key_filepath)
    }

    provisioner "file" {
        source = "scripts/bootstrap.sh"
        destination = "/root/bootstrap.sh"
    }

    provisioner "remote-exec" {
        inline = ["SSH_PORT=${var.ssh_port} bash /root/bootstrap.sh"]
    }
}

resource "null_resource" "setup_master" {
    depends_on = [ hcloud_network.network ]

    # well, more master nodes would not work actually because we
    # run "too much" on all masters
    count = var.master_node_count

    connection {
        host = hcloud_server.master[count.index].ipv4_address
        type = "ssh"
        private_key = file(var.ssh_private_key_filepath)
        port = var.ssh_port
    }

    provisioner "file" {
        source = "scripts/setup-kubernetes.sh"
        destination = "/root/setup-kubernetes.sh"
    }

    provisioner "remote-exec" {
        inline = ["HCLOUD_TOKEN=${var.hcloud_token} NETWORK_ID=${hcloud_network.network.id} ON_MASTER_NODE=1 DOCKER_VERSION=${var.docker_version} KUBERNETES_VERSION=${var.kubernetes_version} bash /root/setup-kubernetes.sh"]
    }
}

resource "null_resource" "setup_worker" {
    count = var.worker_node_count

    connection {
        host = hcloud_server.worker[count.index].ipv4_address
        type = "ssh"
        private_key = file(var.ssh_private_key_filepath)
        port = var.ssh_port
    }

    provisioner "file" {
        source = "scripts/setup-kubernetes.sh"
        destination = "/root/setup-kubernetes.sh"
    }

    provisioner "remote-exec" {
        inline = ["DOCKER_VERSION=${var.docker_version} KUBERNETES_VERSION=${var.kubernetes_version} bash /root/setup-kubernetes.sh"]
    }
}

resource "hcloud_load_balancer" "lb" {
    name = "lb"
    load_balancer_type = "lb11"
    location = var.location
}

resource "hcloud_load_balancer_service" "lb_service" {
    load_balancer_id = hcloud_load_balancer.lb.id
    protocol = "tcp"
    destination_port = 8080
    listen_port = 8080
}

resource "hcloud_load_balancer_target" "lb_target" {
    count = var.worker_node_count
    load_balancer_id = hcloud_load_balancer.lb.id
    type = "server"
    server_id = hcloud_server.worker[count.index].id
}