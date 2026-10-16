variable "region" {
  type    = string
  default = "us-east-1"
}

variable "perfil" {
  description = "perfil de ~/.aws con las llaves de user_cli"
  type        = string
  default     = "user_cli"
}

variable "tipo_ec2" {
  type    = string
  default = "t3.micro"
}

variable "tipo_rds" {
  type    = string
  default = "db.t4g.micro"
}
