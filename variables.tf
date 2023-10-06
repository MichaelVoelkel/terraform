variable "cluster_name" {
}

variable "hcloud_token" {
}

variable "master_node_count" {
}

variable "worker_node_count" {
}

variable "ssh_port" {
    default = 12345
}

variable "node_image" {
  description = "Image"
  default     = "ubuntu-22.04"
}

variable "master_type" {
  description = "cax is Ampere"
  default     = "cax21"
}

variable "worker_type" {
  description = "cax is Ampere"
  default     = "cax21"
}

variable "ssh_private_key_filepath" {
  description = "Private key identifying local trusted machine allowed to access cluster"
}

variable "ssh_public_key_filepath" {
  description = "Public key of this local trusted machine allowed to access cluster"
}

variable "location" {
  default = "hel1"
}

variable "docker_version" {
  default = "24.0"
}

variable "kubernetes_version" {
  default = "1.28.0"
}