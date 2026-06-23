variable "do_token" {
  description = "DigitalOcean API token with read/write access."
  type        = string
  sensitive   = true
}

variable "project_name" {
  description = "Prefix for DigitalOcean resources."
  type        = string
  default     = "shadow-llm-proxy"
}

variable "environment" {
  description = "Deployment environment label (e.g. staging, production)."
  type        = string
  default     = "production"
}

variable "region" {
  description = "DigitalOcean App Platform region (e.g. nyc, sfo, ams)."
  type        = string
  default     = "nyc"
}

variable "registry_region" {
  description = "DigitalOcean Container Registry region (e.g. nyc3, sfo3)."
  type        = string
  default     = "nyc3"
}

variable "image_repository" {
  description = "Container image repository name inside DOCR."
  type        = string
  default     = "shadow-llm-proxy"
}

variable "image_tag" {
  description = "Container image tag deployed by App Platform."
  type        = string
  default     = "latest"
}

variable "inference_api_key" {
  description = "DigitalOcean Serverless Inference API key."
  type        = string
  sensitive   = true
}

variable "primary_model" {
  type    = string
  default = "meta-llama/Meta-Llama-3.1-8B-Instruct"
}

variable "candidate_model" {
  type    = string
  default = "meta-llama/Meta-Llama-3.1-8B-Instruct"
}

variable "instance_size_slug" {
  description = "App Platform instance size."
  type        = string
  default     = "professional-xs"
}

variable "min_instances" {
  description = "Minimum App Platform instances (HA floor)."
  type        = number
  default     = 2
}

variable "max_instances" {
  description = "Maximum App Platform instances under autoscaling."
  type        = number
  default     = 10
}

variable "shadow_queue_max_size" {
  type    = number
  default = 100
}

variable "shadow_max_workers" {
  type    = number
  default = 10
}

variable "shadow_timeout_seconds" {
  type    = number
  default = 30
}

variable "shadow_routing_percentage" {
  type    = number
  default = 100
}

variable "registry_tier" {
  description = "DOCR subscription tier (starter or basic)."
  type        = string
  default     = "basic"
}
