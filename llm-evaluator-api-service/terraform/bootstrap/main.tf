# One-time bootstrap: creates a Spaces bucket for Terraform remote state.
# Apply locally with local state, then configure backend.hcl for the main stack.
#
#   cd terraform/bootstrap
#   terraform init
#   terraform apply -var="do_token=$DIGITALOCEAN_TOKEN"

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.40"
    }
  }
}

variable "do_token" {
  type      = string
  sensitive = true
}

variable "bucket_name" {
  type    = string
  default = "shadow-llm-proxy-tfstate"
}

variable "region" {
  type    = string
  default = "nyc3"
}

provider "digitalocean" {
  token = var.do_token
}

resource "digitalocean_spaces_bucket" "tfstate" {
  name   = var.bucket_name
  region = var.region
  acl    = "private"
}

output "bucket_name" {
  value = digitalocean_spaces_bucket.tfstate.name
}

output "endpoint" {
  value = "https://${var.region}.digitaloceanspaces.com"
}
