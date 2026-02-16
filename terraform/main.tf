module "vpc" {
  source             = "./modules/vpc"
  project_name       = var.project_name
  vpc_cidr           = var.vpc_cidr
  public_subnet_cidr = var.public_subnet_cidr
  az                 = var.az
}

module "iam" {
  source       = "./modules/iam"
  project_name = var.project_name
}

module "ec2" {
  source       = "./modules/ec2"
  project_name = var.project_name

  vpc_id        = module.vpc.vpc_id
  subnet_id     = module.vpc.public_subnet_id
  key_name      = aws_key_pair.generated.key_name
  ami_id        = var.ami_id
  instance_type = var.instance_type

  instance_profile_name = module.iam.instance_profile_name
  private_key_pem       = tls_private_key.generated.private_key_pem
  private_key_path      = var.private_key_path # or direct path like "~/.ssh/id_rsa"
  groq_api_key          = var.groq_api_key

}

resource "tls_private_key" "generated" {
  algorithm = "RSA"
}

resource "local_file" "private_key_pem" {
  content  = tls_private_key.generated.private_key_pem
  filename = "MyAWSKey.pem"
}

resource "aws_key_pair" "generated" {
  key_name   = "MyAWSKey"
  public_key = tls_private_key.generated.public_key_openssh

  lifecycle {
    ignore_changes = [key_name]
  }

}

resource "null_resource" "chmod_key" {
  provisioner "local-exec" {
    command = "chmod 600 MyAWSKey.pem"
  }

  depends_on = [local_file.private_key_pem]
}




