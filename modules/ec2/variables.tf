variable "project_name" { type = string }

variable "vpc_id" { type = string }
variable "subnet_id" { type = string }

variable "ami_id" {
  type    = string
  default = "ami-0b6c6ebed2801a5cb"
}
variable "instance_type" { type = string }
variable "key_name" { type = string }

variable "instance_profile_name" {
  type        = string
  description = "IAM instance profile name from iam module"
}

variable "private_key_pem" {
  type      = string
  sensitive = true
}