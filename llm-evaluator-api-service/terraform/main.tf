locals {
  # App Platform app names must be 2–32 characters.
  short_name = "llm-eval-api-${var.environment}"
  app_name   = local.short_name

  runtime_env = {
    INFERENCE_API_KEY           = var.inference_api_key
    PRIMARY_MODEL               = var.primary_model
    CANDIDATE_MODEL             = var.candidate_model
    SHADOW_QUEUE_MAX_SIZE       = tostring(var.shadow_queue_max_size)
    SHADOW_MAX_WORKERS          = tostring(var.shadow_max_workers)
    SHADOW_TIMEOUT_SECONDS      = tostring(var.shadow_timeout_seconds)
    SHADOW_ROUTING_PERCENTAGE   = tostring(var.shadow_routing_percentage)
    TRACE_DB_PATH               = "/tmp/traces.db"
    PORT                        = "8000"
  }
}

resource "digitalocean_container_registry" "this" {
  name                   = local.short_name
  subscription_tier_slug = var.registry_tier
  region                 = var.registry_region
}

resource "digitalocean_container_registry_docker_credentials" "this" {
  registry_name = digitalocean_container_registry.this.name
  write         = true
}

resource "digitalocean_app" "this" {
  lifecycle {
    precondition {
      condition     = var.inference_api_key != null && trimspace(var.inference_api_key) != ""
      error_message = "Set INFERENCE_API_KEY (model access key) via TF_VAR_inference_api_key before deploying the app."
    }
  }

  spec {
    name   = local.app_name
    region = var.region

    service {
      name               = "api"
      http_port          = 8000
      instance_count     = var.min_instances
      instance_size_slug = var.instance_size_slug

      image {
        registry_type = "DOCR"
        registry      = digitalocean_container_registry.this.name
        repository    = var.image_repository
        tag           = var.image_tag

        deploy_on_push {
          enabled = false
        }
      }

      health_check {
        initial_delay_seconds = 15
        period_seconds        = 10
        timeout_seconds       = 5
        success_threshold     = 1
        failure_threshold     = 3
        http_path             = "/health"
      }

      autoscaling {
        min_instance_count = var.min_instances
        max_instance_count = var.max_instances

        metrics {
          cpu {
            percent = 70
          }
        }
      }

      dynamic "env" {
        for_each = local.runtime_env
        content {
          key   = env.key
          value = env.value
          type  = env.key == "INFERENCE_API_KEY" ? "SECRET" : "GENERAL"
          scope = "RUN_TIME"
        }
      }
    }

    ingress {
      rule {
        component {
          name = "api"
        }

        match {
          path {
            prefix = "/"
          }
        }
      }
    }
  }

  depends_on = [digitalocean_container_registry.this]
}
