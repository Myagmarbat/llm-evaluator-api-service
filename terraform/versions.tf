terraform {
  required_version = ">= 1.5.0"

  backend "local" {
    path = "state/dev.tfstate"
  }

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.40"
    }
  }
}
