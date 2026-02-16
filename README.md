# Terraform Minikube ELK Observability 🚀

This project demonstrates how to use **Terraform** to provision **AWS infrastructure**, deploy **Minikube**, and set up an **ELK (Elasticsearch, Logstash, Kibana) observability stack on Kubernetes**.

The goal is to show **Infrastructure as Code (IaC)** in action — from **zero infrastructure** to a **fully working Kubernetes + observability setup**, using a single Terraform workflow.

---

## 🧱 What This Project Builds

After running the Terraform scripts, the following components are created:

### AWS Infrastructure
- VPC
- Public Subnet
- Internet Gateway
- Route Table
- Security Group
- EC2 Instance (used as Minikube host)

### Kubernetes Layer (on EC2)
- Minikube cluster
- Kubernetes namespaces for:
  - Application workloads
  - Logging & observability

### Observability Stack (ELK)
- Elasticsearch
- Logstash
- Kibana
- Fluent Bit (for log shipping)

---

## 📁 Repository Structure

```text
terraform/
├── k8s/                 # Kubernetes YAML manifests
│   ├── elasticsearch/
│   ├── logstash/
│   ├── kibana/
│   └── fluent-bit/
│
├── modules/             # Terraform reusable modules
│   ├── vpc/
│   ├── ec2/
│   └── security-group/
│
├── main.tf              # Root Terraform configuration
├── providers.tf         # AWS provider configuration
├── variables.tf         # Input variables
├── outputs.tf           # Output values
├── versions.tf          # Terraform & provider versions
└── README.md
