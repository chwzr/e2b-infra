
variable "provider_name" {
  type        = string
  description = "Cloud provider: gcp or aws"

  validation {
    condition     = contains(["gcp", "aws", "hetzner"], var.provider_name)
    error_message = "provider_name must be 'gcp', 'aws', or 'hetzner'"
  }
}

variable "node_pool" {
  type = string
}

variable "loki_port" {
  type = number
}

variable "bucket_name" {
  type = string
}

variable "memory_mb" {
  type    = number
  default = 512
}

variable "cpu_count" {
  type    = number
  default = 1
}

variable "loki_image" {
  type    = string
  default = "grafana/loki:3.6.4"
}

variable "prevent_colocation" {
  type    = bool
  default = false
}

variable "aws_region" {
  type    = string
  default = ""
}

variable "s3_endpoint" {
  type        = string
  default     = ""
  description = "S3-compatible endpoint URL for Hetzner Object Storage"
}

variable "loki_use_v13_schema_from" {
  type    = string
  default = ""
}

variable "loki_config_override" {
  type        = string
  default     = ""
  description = "Custom Loki YAML config. When set, replaces the default provider-specific config entirely."
}
