terraform {
  required_version = ">= 1.5.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.40"
    }
  }
}

variable "do_token" {
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
  description = "DigitalOcean API token. When null, uses DIGITALOCEAN_TOKEN from the environment."
}

variable "bucket_name" {
  type        = string
  description = "Globally unique Spaces bucket name for Terraform remote state."
}

variable "region" {
  type        = string
  description = "DigitalOcean region for the Spaces bucket."
  default     = "nyc3"
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
  description = "Spaces bucket name for Terraform remote state."
  value       = digitalocean_spaces_bucket.tfstate.name
}

output "bucket_region" {
  description = "Spaces bucket region."
  value       = digitalocean_spaces_bucket.tfstate.region
}

output "bucket_endpoint" {
  description = "Spaces bucket endpoint URL."
  value       = digitalocean_spaces_bucket.tfstate.bucket_domain_name
}
