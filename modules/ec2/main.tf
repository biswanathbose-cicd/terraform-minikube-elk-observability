resource "aws_security_group" "this" {
  name        = "${var.project_name}-sg"
  description = "Allow SSH, HTTP, HTTPS"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # tighten this to your IP in real use
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

resource "aws_instance" "this" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.this.id]
  key_name               = var.key_name
  root_block_device {
    volume_size           = 20    # GB
    volume_type           = "gp3" # modern SSD
    delete_on_termination = true
  }
  connection {
    user        = "ubuntu"
    type        = "ssh"
    private_key = var.private_key_pem
    host        = self.public_ip
  }
  associate_public_ip_address = true

  iam_instance_profile = var.instance_profile_name

  tags = {
    Name = "${var.project_name}-ec2"
  }


  provisioner "remote-exec" {
    inline = [
      # ---------------- Docker ----------------
      "sudo apt-get update -y",
      "sudo apt-get install -y ca-certificates curl gnupg",

      "sudo install -m 0755 -d /etc/apt/keyrings",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg",
      "sudo chmod a+r /etc/apt/keyrings/docker.gpg",

      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "sudo apt-get update -y",
      "sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin",

      "sudo systemctl enable docker",
      "sudo systemctl start docker",

      # ubuntu docker group (effective on next login; we will still start minikube via sudo -u ubuntu)
      "sudo usermod -aG docker ubuntu",
      "sudo systemctl restart docker",
      "sleep 5",

      # ---------------- kubectl ----------------
      "curl -LO \"https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\"",
      "sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl",

      # ---------------- Minikube ----------------
      "curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64",
      "sudo install minikube-linux-amd64 /usr/local/bin/minikube",

      # Ensure ownership (prevents the permission denied issues you saw before)
      "sudo mkdir -p /home/ubuntu/.minikube /home/ubuntu/.kube",
      "sudo chown -R ubuntu:ubuntu /home/ubuntu/.minikube /home/ubuntu/.kube",

      # Start Minikube AS ubuntu (no heredoc, no root profile)
      # IMPORTANT: set memory based on machine; 3000mb safe for >=4GB RAM, reduce if needed.
      "sudo -u ubuntu -i bash -lc 'minikube start --driver=docker --cpus=2 --memory=1500mb --disk-size=20g --force'",

      # Wait until cluster responds (prevents localhost:8080 refused)
      "sudo -u ubuntu -i bash -lc 'kubectl wait --for=condition=Ready nodes --all --timeout=300s'",

      # Verify
      "sudo -u ubuntu -i bash -lc 'minikube status'",
      "sudo -u ubuntu -i bash -lc 'kubectl get nodes'",
      "sudo -u ubuntu -i bash -lc 'kubectl get pods -A'"
    ]
  }



}
