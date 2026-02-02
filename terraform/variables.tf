variable "aws_region" {
  type    = string
  default = "us-east-1"

}

variable "project_name" {
  type    = string
  default = "ec2-k8s-ins"
}

variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.10.1.0/24"
}

variable "az" {
  type    = string
  default = "us-east-1a"
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}



variable "ami_id" {
  type        = string
  description = "AMI ID to use for EC2"
  default     = "ami-0b6c6ebed2801a5cb"
}