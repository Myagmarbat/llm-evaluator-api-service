provider "digitalocean" {
  token = var.do_token
}

data "digitalocean_account" "current" {}
