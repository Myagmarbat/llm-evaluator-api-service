locals {
  short_name        = "llm-eval-api-${var.environment}"
  manage_registry   = var.environment == "dev"
  registry_name     = var.registry_name
  registry_endpoint = local.manage_registry ? digitalocean_container_registry.main[0].endpoint : data.digitalocean_container_registry.shared[0].endpoint
  image_ref         = "${local.registry_endpoint}/${var.project_name}:${var.image_tag}"
  # CPU-based autoscaling is only supported on dedicated CPU App Platform sizes.
  cpu_autoscaling_enabled = startswith(var.instance_size_slug, "apps-d-") || contains([
    "professional-1l",
    "professional-l",
    "professional-xl",
  ], var.instance_size_slug)
}

# Dev Terraform state owns the account registry; other environments reference it.
moved {
  from = digitalocean_container_registry.main
  to   = digitalocean_container_registry.main[0]
}

resource "digitalocean_container_registry" "main" {
  count                  = local.manage_registry ? 1 : 0
  name                   = var.registry_name
  subscription_tier_slug = "basic"
  region                 = var.region
}

data "digitalocean_container_registry" "shared" {
  count = local.manage_registry ? 0 : 1
  name  = var.registry_name
}

resource "digitalocean_container_registry_docker_credentials" "main" {
  registry_name = local.registry_name
}

resource "digitalocean_app" "main" {
  lifecycle {
    precondition {
      condition     = try(trimspace(var.inference_api_key), "") != ""
      error_message = "inference_api_key must be set when deploying the App Platform service. Pass TF_VAR_inference_api_key or set it in terraform.tfvars."
    }
  }

  spec {
    name   = local.short_name
    region = var.region

    service {
      name               = "api"
      http_port          = 8000
      instance_size_slug = var.instance_size_slug
      instance_count     = local.cpu_autoscaling_enabled ? null : var.fixed_instance_count

      image {
        registry_type = "DOCR"
        registry      = local.registry_name
        repository    = var.project_name
        tag           = var.image_tag
      }

      dynamic "autoscaling" {
        for_each = local.cpu_autoscaling_enabled ? [1] : []
        content {
          min_instance_count = var.autoscaling_min_instances
          max_instance_count = var.autoscaling_max_instances

          metrics {
            cpu {
              percent = var.autoscaling_cpu_percent
            }
          }
        }
      }

      health_check {
        http_path             = "/health"
        initial_delay_seconds = 10
        period_seconds        = 30
        timeout_seconds       = 5
        success_threshold     = 1
        failure_threshold     = 3
      }

      env {
        key   = "TRACE_DB_PATH"
        value = "/tmp/traces.db"
      }

      env {
        key   = "INFERENCE_API_KEY"
        value = var.inference_api_key
        type  = "SECRET"
      }

      env {
        key   = "INFERENCE_BASE_URL"
        value = var.inference_base_url
      }

      env {
        key   = "PRIMARY_MODEL"
        value = var.primary_model
      }

      env {
        key   = "CANDIDATE_MODEL"
        value = var.candidate_model
      }

      env {
        key   = "SHADOW_QUEUE_MAX_SIZE"
        value = tostring(var.shadow_queue_max_size)
      }

      env {
        key   = "SHADOW_MAX_WORKERS"
        value = tostring(var.shadow_max_workers)
      }

      env {
        key   = "SHADOW_TIMEOUT_SECONDS"
        value = tostring(var.shadow_timeout_seconds)
      }

      env {
        key   = "SHADOW_ROUTING_PERCENTAGE"
        value = tostring(var.shadow_routing_percentage)
      }

      env {
        key   = "PRIMARY_TIMEOUT_SECONDS"
        value = tostring(var.primary_timeout_seconds)
      }
    }
  }

  depends_on = [
    digitalocean_container_registry_docker_credentials.main,
  ]
}
