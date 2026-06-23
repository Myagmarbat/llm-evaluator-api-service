output "app_url" {
  description = "Live URL of the deployed App Platform service."
  value       = digitalocean_app.main.live_url
}

output "app_id" {
  description = "DigitalOcean App Platform application ID."
  value       = digitalocean_app.main.id
}

output "registry_endpoint" {
  description = "Container registry endpoint for docker login and push."
  value       = local.registry_endpoint
}

output "registry_name" {
  description = "Shared container registry name."
  value       = local.registry_name
}

output "image_reference" {
  description = "Full image reference for the deployed container."
  value       = local.image_ref
}
