variable "prefix" {
  type = string
}

variable "network_zone" {
  type    = string
  default = "eu-central"
}

variable "ip_range" {
  type    = string
  default = "10.0.0.0/8"
}

variable "subnet_range" {
  type    = string
  default = "10.0.0.0/24"
}
