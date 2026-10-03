variable "project_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "private_app_subnet_ids" {
  type = list(string)
}

variable "app_sg_id" {
  type = string
}

variable "target_group_arn" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "instance_count" {
  type    = number
  default = 2
}

variable "app_port" {
  type    = number
  default = 8080
}

variable "key_pair_name" {
  type    = string
  default = ""
}

variable "db_endpoint" {
  type    = string
  default = ""
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  type    = string
  default = "dbadmin"
}

variable "db_secret_arn" {
  type    = string
  default = ""
}
