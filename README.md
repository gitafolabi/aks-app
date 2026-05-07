# 🚀 Full-Stack CRUD Application with GitOps on Azure Kubernetes Service (AKS)

This repository contains a full-stack 3-tier application (Frontend, Backend, Database) alongside a complete DevOps and GitOps pipeline. It automates the infrastructure provisioning, build, and deployment to Azure Kubernetes Service (AKS) utilizing industry-standard tools like Terraform, GitHub Actions, Helm, and Argo CD.

## 📌 Architecture Overview

The system is built around a modern microservices-style 3-tier architecture:

- **Frontend:** A React.js web application built with Vite (`frontend/`).
- **Backend:** A RESTful API built with Java 21 and Spring Boot (`backend/`).
- **Database:** PostgreSQL running inside the AKS cluster, deployed alongside the application.

Each tier is containerized with Docker. The GitOps pipeline ensures that any changes merged to the repository or updates to the infrastructure configurations are automatically reconciled and deployed in the cluster.

---

## 🛠️ Technology Stack

**Application:**
- **Frontend:** React 19, Vite, JavaScript
- **Backend:** Java 21, Spring Boot 3.2, MapStruct, Lombok, Maven
- **Database:** PostgreSQL

**DevOps & Infrastructure:**
- **Cloud Provider:** Microsoft Azure
- **Infrastructure as Code (IaC):** Terraform
- **Container Orchestration:** Azure Kubernetes Service (AKS)
- **CI/CD:** GitHub Actions (CI) & Argo CD (CD)
- **Package Manager:** Helm (for Kubernetes deployments)
- **Containerization:** Docker & Docker Hub

---

## 🏗️ Project Structure

- `frontend/`: React + Vite application source code and Dockerfile.
- `backend/`: Java Spring Boot application source code, Maven configuration, and Dockerfile.
- `infrastructure/`: Terraform code to provision Azure resources (AKS, Key Vault, Service Principal).
- `helm/crud-app-chart/`: Helm chart containing Kubernetes manifests for frontend, backend, and PostgreSQL deployments.
- `argocd/`: Argo CD application manifests.
- `.github/workflows/`: CI pipelines for building and pushing Docker images and updating the Helm chart.

---

## 🚀 Deployment Guide

### 1. Infrastructure Provisioning (Terraform)

The infrastructure is modularly defined using Terraform. It automatically creates an AKS cluster, a Key Vault for managing secrets securely, and an Azure AD Service Principal.

**Prerequisites:**
- An active Azure subscription
- Azure CLI installed and authenticated (`az login`)
- Terraform installed

**Steps:**
1. Navigate to the `infrastructure/` directory:
   ```bash
   cd infrastructure
   ```
2. Initialize Terraform to download the required providers:
   ```bash
   terraform init
   ```
3. Review the resources to be created:
   ```bash
   terraform plan
   ```
4. Provision the infrastructure (you may need to provide variable values in `terraform.tfvars`):
   ```bash
   terraform apply
   ```

### 2. Continuous Integration (GitHub Actions)

Upon merging code changes to the `main` branch, the GitHub Actions workflows (`frontend.yaml` and `backend.yaml`) automatically trigger:
1. **Build:** Compiles the application and builds the Docker image.
2. **Push:** Pushes the new image to Docker Hub (`avurlerby/crud-app`).
3. **Update Manifests:** Uses `yq` to update the Helm chart (`values.yaml`) with the newly built image tags.
4. **Secret Management:** Syncs necessary database credentials into the AKS cluster as Kubernetes secrets.

**Required GitHub Secrets:**
- `DOCKERHUB_USERNAME`, `DOCKERHUB_PASSWORD`
- `AZURE_CREDENTIALS` (for AKS access)
- `TOKEN` (Personal Access Token for Git push)
- `DB_USER`, `DB_PASSWORD` (PostgreSQL credentials)
- **Repository Variables:** `USER_EMAIL`, `USER_NAME`

### 3. Continuous Delivery (Argo CD)

Argo CD handles the continuous deployment to the AKS cluster following GitOps principles.
- Apply the Argo CD application definition found in the `argocd/` directory to your cluster.
- Argo CD will continuously monitor the `helm/crud-app-chart/` directory in this repository.
- Whenever GitHub Actions updates the image tags in `values.yaml`, Argo CD detects the drift and automatically synchronizes the new state with the AKS cluster, executing rolling updates with zero downtime.

---

## 🛡️ Security
- No hardcoded secrets inside the application code.
- Infrastructure provisions an Azure Key Vault for central secret storage.
- External secrets operator handling the secret sync from Azure Key Vault. 
- The CI pipeline creates necessary runtime secrets securely in the cluster.

## 🏃 Local Development
To run the project locally without Docker/Kubernetes:

**Backend:**
```bash
cd backend
./mvnw spring-boot:run
```

**Frontend:**
```bash
cd frontend
npm install
npm run dev
```
