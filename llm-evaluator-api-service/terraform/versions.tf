terraform {
  required_version = ">= 1.6.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.40"
    }
  }

  # Local state for development. CI/CD overrides with Spaces via:
  #   terraform init -backend-config=backend.hcl
  backend "local" {
    path = "terraform.tfstate"
  }
}
