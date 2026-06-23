provider "digitalocean" {
  # When var.do_token is null, reads DIGITALOCEAN_TOKEN from the environment.
  token = var.do_token
}

# Fails fast during plan/apply if the API token is missing or invalid (401).
data "digitalocean_account" "current" {}
