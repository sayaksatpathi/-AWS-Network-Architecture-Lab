variable "project_name" {
  type = string
}

variable "create_dns" {
  type    = bool
  default = false
}

variable "create_tls" {
  type    = bool
  default = false
}

variable "domain_name" {
  type    = string
  default = ""
}

variable "subdomain" {
  type    = string
  default = "app"
}

variable "alb_dns_name" {
  type = string
}

variable "alb_zone_id" {
  type = string
}
