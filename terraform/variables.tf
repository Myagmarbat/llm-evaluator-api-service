variable "do_token" {
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
  description = "DigitalOcean API token. When null, the provider uses DIGITALOCEAN_TOKEN from the environment."
}

variable "inference_api_key" {
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
  description = "API key for DigitalOcean Inference. Required when deploying the App Platform service."
}

variable "environment" {
  type        = string
  description = "Deployment environment (e.g. dev, staging, prod)."
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  type        = string
  description = "DigitalOcean region for the container registry and App Platform."
  default     = "nyc3"
}

variable "project_name" {
  type        = string
  description = "Project and container image repository name."
  default     = "llm-evaluator-api-service"
}

variable "image_tag" {
  type        = string
  description = "Container image tag to deploy."
  default     = "latest"
}

variable "instance_size_slug" {
  type        = string
  description = "App Platform instance size. CPU autoscaling requires a dedicated CPU plan (apps-d-* or professional-*)."
  default     = "apps-d-1vcpu-0.5gb"
}

variable "inference_base_url" {
  type        = string
  description = "Base URL for the inference API."
  default     = "https://inference.do-ai.run"
}

variable "primary_model" {
  type        = string
  description = "Primary LLM model identifier."
  default     = "meta-llama/Meta-Llama-3.1-8B-Instruct"
}

variable "candidate_model" {
  type        = string
  description = "Candidate LLM model identifier for shadow evaluation."
  default     = "meta-llama/Meta-Llama-3.1-8B-Instruct"
}

variable "shadow_queue_max_size" {
  type        = number
  description = "Maximum number of pending shadow evaluation tasks."
  default     = 100
}

variable "shadow_max_workers" {
  type        = number
  description = "Maximum concurrent shadow evaluation workers per instance."
  default     = 10
}

variable "shadow_timeout_seconds" {
  type        = number
  description = "Timeout in seconds for candidate LLM requests."
  default     = 30
}

variable "shadow_routing_percentage" {
  type        = number
  description = "Percentage of requests routed to shadow evaluation (0-100)."
  default     = 100
}

variable "primary_timeout_seconds" {
  type        = number
  description = "Timeout in seconds for primary LLM requests."
  default     = 60
}
