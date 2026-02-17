resource "aws_security_group" "this" {
  name        = "${var.project_name}-sg"
  description = "Allow HTTP/HTTPS to Ingress + SSH (open lab)"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH (open lab - not recommended)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP to Ingress"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP to Ingress"
    from_port   = 5601
    to_port     = 5601
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS to Ingress"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
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
    timeout     = "30m"
  }
  associate_public_ip_address = true

  iam_instance_profile = var.instance_profile_name

  tags = {
    Name = "${var.project_name}-ec2"
  }
  provisioner "file" {
    source      = "${path.root}/k8s"
    destination = "/home/ubuntu/k8s"
  }
  provisioner "remote-exec" {


    inline = [
      "exec >> /tmp/terraform-provision.log 2>&1",
      "set -e",
      "echo 'Starting provisioning at $(date)'",

      # ---------------- Docker ----------------
      "echo '=== Installing Docker ==='",
      "sudo apt-get update -y",
      "sudo apt-get install -y ca-certificates curl gnupg unzip",

      "sudo install -m 0755 -d /etc/apt/keyrings",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg",
      "sudo chmod a+r /etc/apt/keyrings/docker.gpg",

      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "sudo apt-get update -y",
      "sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin",

      "sudo systemctl enable docker",
      "sudo systemctl start docker",

      "sudo usermod -aG docker ubuntu",
      "sudo systemctl restart docker",
      "sleep 5",

      # ---------------- kubectl ----------------
      "echo '=== Installing kubectl ==='",
      "curl -LO \"https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\"",
      "sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl",

      # ---------------- Minikube ----------------
      "echo '=== Installing Minikube ==='",
      "curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64",
      "sudo install minikube-linux-amd64 /usr/local/bin/minikube",

      "sudo mkdir -p /home/ubuntu/.minikube /home/ubuntu/.kube",
      "sudo chown -R ubuntu:ubuntu /home/ubuntu/.minikube /home/ubuntu/.kube",

      # Swap
      "echo '=== Setting up swap ==='",
      "sudo fallocate -l 2G /swapfile || true",
      "sudo chmod 600 /swapfile || true",
      "sudo mkswap /swapfile || true",
      "sudo swapon /swapfile || true",
      "echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab",

      # Start Minikube
      "echo '=== Starting Minikube ==='",
      "sudo -u ubuntu -i bash -lc 'minikube start --driver=docker --cpus=2 --memory=4096mb --disk-size=20g --kubernetes-version=stable --force'",

      # Unzip and build Docker image
      "echo '=== Extracting fastapi-demo ==='",
      "cd /home/ubuntu/k8s && unzip -o fastapi-demo.zip",

      "echo '=== Building Docker image ==='",
      "sudo -u ubuntu -H bash -lc 'cd /home/ubuntu/k8s/fastapi-demo && eval $(minikube docker-env) && docker build -t llm-streamlit-app:1.0 .'",

      "echo '=== Verifying Docker image ==='",
      "sudo -u ubuntu -H bash -lc 'eval $(minikube docker-env) && docker images | grep llm-streamlit-app'",

      # Create Kubernetes secret
      "echo '=== Creating Kubernetes secret ==='",
      "sudo -u ubuntu -H bash -lc 'kubectl create secret generic rag-secrets --from-literal=GROQ_API_KEY='var' --dry-run=client -o yaml | kubectl apply -f -'",

      # Apply Kubernetes deployment
      "echo '=== Applying Kubernetes deployment ==='",
      "sudo -u ubuntu -H bash -lc 'kubectl apply -f /home/ubuntu/k8s/k8s-deployment.yaml'",

      # Wait for deployment
      "echo '=== Waiting for deployment rollout ==='",
      "sudo -u ubuntu -H bash -lc 'kubectl rollout status deploy/llm-streamlit-app --timeout=300s || true'",

      # Verify
      "echo '=== Verifying Minikube status ==='",
      "sudo -u ubuntu -i bash -lc 'minikube status'",
      "sudo -u ubuntu -i bash -lc 'kubectl get nodes'",
      "sudo -u ubuntu -i bash -lc 'kubectl get pods -A'",

      # Enable Ingress
      "echo '=== Enabling Ingress addon ==='",
      "sudo -u ubuntu -i minikube addons enable ingress",

      # Wait for Ingress Controller
      "echo '=== Waiting for Ingress Controller ==='",
      "sudo -u ubuntu kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s",

      # Get NodePorts dynamically
      "echo '=== Getting NodePort information ==='",
      "STREAMLIT_PORT=$(sudo -u ubuntu kubectl get svc llm-streamlit-app-svc -o jsonpath='{.spec.ports[0].nodePort}')",
      "KIBANA_PORT=$(sudo -u ubuntu kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')",
      "echo \"Streamlit NodePort: $STREAMLIT_PORT\"",
      "echo \"Kibana Ingress NodePort: $KIBANA_PORT\"",

      # Setup Nginx for Streamlit
      "echo '=== Setting up Nginx for Streamlit ==='",
      "sudo apt-get update -y",
      "sudo apt-get install -y nginx",
      "sudo systemctl enable --now nginx",
      "sudo rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default || true",
      "STREAMLIT_PORT=$(sudo -u ubuntu kubectl get svc llm-streamlit-app-svc -o jsonpath='{.spec.ports[0].nodePort}')",
      "echo \"Streamlit NodePort: $STREAMLIT_PORT\"",
      "echo 'upstream streamlit {' | sudo tee /etc/nginx/conf.d/streamlit-proxy.conf",
      "echo \"    server 192.168.49.2:$STREAMLIT_PORT;\" | sudo tee -a /etc/nginx/conf.d/streamlit-proxy.conf",
      "echo '}' | sudo tee -a /etc/nginx/conf.d/streamlit-proxy.conf",
      "echo 'server {' | sudo tee -a /etc/nginx/conf.d/streamlit-proxy.conf",
      "echo '    listen 80 default_server;' | sudo tee -a /etc/nginx/conf.d/streamlit-proxy.conf",
      "echo '    listen [::]:80 default_server;' | sudo tee -a /etc/nginx/conf.d/streamlit-proxy.conf",
      "echo '    server_name _;' | sudo tee -a /etc/nginx/conf.d/streamlit-proxy.conf",
      "echo '    location / {' | sudo tee -a /etc/nginx/conf.d/streamlit-proxy.conf",
      "echo '        proxy_pass http://streamlit;' | sudo tee -a /etc/nginx/conf.d/streamlit-proxy.conf",
      "echo '        proxy_http_version 1.1;' | sudo tee -a /etc/nginx/conf.d/streamlit-proxy.conf",
      "echo '        proxy_set_header Host $host;' | sudo tee -a /etc/nginx/conf.d/streamlit-proxy.conf",
      "echo '        proxy_set_header X-Real-IP $remote_addr;' | sudo tee -a /etc/nginx/conf.d/streamlit-proxy.conf",
      "echo '        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;' | sudo tee -a /etc/nginx/conf.d/streamlit-proxy.conf",
      "echo '        proxy_set_header X-Forwarded-Proto $scheme;' | sudo tee -a /etc/nginx/conf.d/streamlit-proxy.conf",
      "echo '        proxy_set_header Upgrade $http_upgrade;' | sudo tee -a /etc/nginx/conf.d/streamlit-proxy.conf",
      "echo '        proxy_set_header Connection \"upgrade\";' | sudo tee -a /etc/nginx/conf.d/streamlit-proxy.conf",
      "echo '        proxy_read_timeout 86400;' | sudo tee -a /etc/nginx/conf.d/streamlit-proxy.conf",
      "echo '    }' | sudo tee -a /etc/nginx/conf.d/streamlit-proxy.conf",
      "echo '}' | sudo tee -a /etc/nginx/conf.d/streamlit-proxy.conf",

      # Setup Nginx for Kibana on port 5601
      "echo '=== Setting up Nginx for Kibana on port 5601 ==='",
      "KIBANA_PORT=$(sudo -u ubuntu kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')",
      "echo \"Kibana Ingress NodePort: $KIBANA_PORT\"",
      "echo 'server {' | sudo tee /etc/nginx/conf.d/kibana-separate.conf",
      "echo '    listen 5601;' | sudo tee -a /etc/nginx/conf.d/kibana-separate.conf",
      "echo '    server_name _;' | sudo tee -a /etc/nginx/conf.d/kibana-separate.conf",
      "echo '    location / {' | sudo tee -a /etc/nginx/conf.d/kibana-separate.conf",
      "echo \"        proxy_pass http://192.168.49.2:$KIBANA_PORT;\" | sudo tee -a /etc/nginx/conf.d/kibana-separate.conf",
      "echo '        proxy_http_version 1.1;' | sudo tee -a /etc/nginx/conf.d/kibana-separate.conf",
      "echo '        proxy_set_header Host $host;' | sudo tee -a /etc/nginx/conf.d/kibana-separate.conf",
      "echo '        proxy_set_header X-Real-IP $remote_addr;' | sudo tee -a /etc/nginx/conf.d/kibana-separate.conf",
      "echo '        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;' | sudo tee -a /etc/nginx/conf.d/kibana-separate.conf",
      "echo '        proxy_set_header X-Forwarded-Proto $scheme;' | sudo tee -a /etc/nginx/conf.d/kibana-separate.conf",
      "echo '        proxy_set_header Connection \"\";' | sudo tee -a /etc/nginx/conf.d/kibana-separate.conf",
      "echo '    }' | sudo tee -a /etc/nginx/conf.d/kibana-separate.conf",
      "echo '}' | sudo tee -a /etc/nginx/conf.d/kibana-separate.conf",

      # Test and restart nginx
      "sudo nginx -t",
      "sudo systemctl restart nginx",
      # Elasticsearch settings
      "echo '=== Configuring Elasticsearch settings ==='",
      "sudo sysctl -w vm.max_map_count=262144",
      "echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf",
      "sudo sysctl -p || true",

      # Deploy ELK Stack
      "echo '=== Deploying ELK Stack ==='",
      "sudo chown -R ubuntu:ubuntu /home/ubuntu/k8s",

      "sudo -u ubuntu -i bash -lc 'kubectl apply -f /home/ubuntu/k8s/namespace.yaml'",

      "echo '=== Deploying Elasticsearch ==='",
      "sudo -u ubuntu -i bash -lc 'kubectl apply -f /home/ubuntu/k8s/elasticsearch.yaml'",
      "sudo -u ubuntu -i bash -lc 'kubectl -n logging rollout status statefulset/elasticsearch --timeout=600s || true'",

      "echo '=== Patching Elasticsearch ==='",
      "sudo -u ubuntu -i bash -lc \"kubectl -n logging patch statefulset elasticsearch --type='json' -p='[{\\\"op\\\":\\\"replace\\\",\\\"path\\\":\\\"/spec/template/spec/containers/0/env/1/value\\\",\\\"value\\\":\\\"-Xms512m -Xmx512m -XX:-UseContainerSupport -Dlog4j2.disable.jmx=true -Dcom.sun.management.jmxremote=false -Djdk.disableLastUsageTracking=true\\\"}]' || true\"",

      "sudo -u ubuntu -i bash -lc 'kubectl -n logging delete pod elasticsearch-0 --ignore-not-found=true'",
      "sudo -u ubuntu -i bash -lc 'kubectl -n logging rollout status statefulset/elasticsearch --timeout=600s || true'",
      "sudo -u ubuntu -i bash -lc 'kubectl -n logging get pods'",

      "echo '=== Deploying Logstash ==='",
      "sudo -u ubuntu -i bash -lc 'kubectl apply -f /home/ubuntu/k8s/logstash.yaml'",
      "sudo -u ubuntu -i bash -lc 'kubectl -n logging rollout status deploy/logstash --timeout=600s || true'",

      "echo '=== Deploying Kibana ==='",
      "sudo -u ubuntu -i bash -lc 'kubectl apply -f /home/ubuntu/k8s/kibana.yaml'",
      "sudo -u ubuntu -i bash -lc 'kubectl -n logging rollout status deploy/kibana --timeout=600s || true'",

      "echo '=== Deploying Filebeat ==='",
      "sudo -u ubuntu -i bash -lc 'kubectl apply -f /home/ubuntu/k8s/filebeat.yaml'",
      "sudo -u ubuntu -i bash -lc 'kubectl -n logging rollout restart ds/filebeat'",
      "sudo -u ubuntu -i bash -lc 'kubectl -n logging rollout status ds/filebeat --timeout=180s || true'",

      # Verification
      "echo '=== Filebeat logs ==='",
      "sudo -u ubuntu -i bash -lc 'kubectl -n logging logs ds/filebeat --tail=50 || true'",

      "echo '=== Elasticsearch indices ==='",
      "sudo -u ubuntu -i bash -lc \"kubectl -n logging exec elasticsearch-0 -- sh -lc 'curl -s localhost:9200/_cat/indices?v | grep -i filebeat || true'\"",

      "echo '=== Final verification ==='",
      "sudo -u ubuntu -i bash -lc 'kubectl -n logging get pods'",
      "sudo -u ubuntu -i bash -lc 'kubectl -n logging get svc'",
      "sudo -u ubuntu -i bash -lc 'kubectl -n logging get ingress -o wide || true'",
      "sudo -u ubuntu -i bash -lc 'kubectl -n ingress-nginx get svc ingress-nginx-controller -o wide || true'",
      "sudo -u ubuntu -i bash -lc 'kubectl get all'",

      # Print URLs
      "echo '=== Access URLs ==='",
      "PUB_IP=$(curl -s http://checkip.amazonaws.com)",
      "echo \"STREAMLIT_URL=http://$PUB_IP/\"",
      "echo \"KIBANA_URL=http://$PUB_IP:5601/\"",

      "echo 'Provisioning completed successfully at $(date)'",
      "exit 0"
    ]
  }







}
