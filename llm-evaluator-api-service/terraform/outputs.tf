output "app_url" {
  description = "Public HTTPS URL for the shadow LLM proxy."
  value       = digitalocean_app.this.live_url
}

output "app_id" {
  description = "DigitalOcean App Platform application ID."
  value       = digitalocean_app.this.id
}

output "registry_endpoint" {
  description = "DOCR endpoint for docker push."
  value       = digitalocean_container_registry.this.endpoint
}

output "registry_name" {
  description = "DOCR registry name."
  value       = digitalocean_container_registry.this.name
}

output "image_reference" {
  description = "Full image reference for the currently deployed tag."
  value       = "${digitalocean_container_registry.this.endpoint}/${var.image_repository}:${var.image_tag}"
}
