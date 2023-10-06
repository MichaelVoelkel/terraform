
terraform {
  required_version = ">= 0.13"
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
      version = "1.43.0" # 1.44.0 currently buggy: https://github.com/hetznercloud/terraform-provider-hcloud/issues/763
    }
  }
}