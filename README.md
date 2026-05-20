# Full-Stack Gym Records App — GitOps on Azure Kubernetes Service (AKS)

A 3-tier CRUD application for tracking gym workout records (exercises and weights), deployed to AKS using a complete GitOps pipeline. Infrastructure is provisioned by Terraform, images are built and scanned by two CI systems (GitHub Actions and Azure DevOps), and deployments are reconciled by Argo CD.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     AKS Cluster                                 │
│                   namespace: crud-app                           │
│                                                                 │
│  ┌──────────────────┐    /api/    ┌──────────────────────────┐  │
│  │  Frontend        │ ──────────► │  Backend                 │  │
│  │  React + Vite    │            │  Spring Boot 3.2 / Java 21│  │
│  │  nginx:alpine    │            │  /actuator/prometheus     │  │
│  └──────────────────┘            └──────────────┬───────────┘  │
│                                                 │              │
│                                  ┌──────────────▼───────────┐  │
│                                  │  PostgreSQL               │  │
│                                  │  (in-cluster)             │  │
│                                  └──────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
        ▲
        │ GitOps reconciliation
   Argo CD (automated, prune, selfHeal)
        │
   helm/crud-app-chart/values.yaml  ◄── CI updates image tags
        │
   GitHub repository
```

The nginx container proxies `/api/` to `backend:8080`, so the frontend never calls the backend directly across origins.

---

## Technology Stack

**Application**
- **Frontend:** React 19, Vite, JavaScript, served by nginx
- **Backend:** Java 21, Spring Boot 3.2, Spring Data JPA, MapStruct, Lombok, Maven
- **Database:** PostgreSQL (deployed in-cluster via Helm)
- **Observability:** Spring Actuator + Micrometer Prometheus registry (`/actuator/prometheus`)

**DevOps & Infrastructure**
- **Cloud:** Microsoft Azure (AKS, Key Vault, ACR)
- **IaC:** Terraform (modules: ServicePrincipal, KeyVault, AKS)
- **CI:** GitHub Actions (Docker Hub) · Azure DevOps Pipeline (ACR)
- **CD:** Argo CD (GitOps)
- **Packaging:** Helm
- **Security scanning:** Snyk (GitHub Actions) · Trivy (Azure DevOps)
- **Node hardening:** Ansible (OS hardening + k8s-deploy roles)

---

## Project Structure

```
.
├── frontend/               # React + Vite app; nginx.conf proxies /api/ → backend:8080
│   ├── Dockerfile          # Multi-stage: Node 22 build → nginx:alpine serve
│   └── nginx.conf
├── backend/                # Spring Boot REST API (port 8080)
│   ├── Dockerfile          # Single-stage: eclipse-temurin:21-jdk
│   └── pom.xml             # Includes actuator + micrometer-registry-prometheus
├── infrastructure/         # Terraform: AKS cluster, Key Vault, Service Principal
│   └── modules/
│       ├── aks/
│       ├── keyvault/
│       └── ServicePrincipal/
├── helm/
│   └── crud-app-chart/     # Kubernetes manifests for frontend, backend, PostgreSQL
│       └── values.yaml     # Image tags updated by CI pipelines
├── argocd/
│   ├── argocd-app.yaml     # Active: deploys crud-app-chart to crud-app namespace
│   ├── argocd-logging.yaml # Inactive (commented): ELK stack
│   └── argocd-monitoring.yaml # Inactive (commented): Prometheus + Grafana
├── ansible/
│   ├── site.yml            # Master playbook: harden VMs + deploy to k8s
│   ├── deploy.yml          # Zero-downtime deploy playbook (-e image_tag=<sha>)
│   └── harden.yml          # OS hardening playbook
├── .github/workflows/
│   ├── backend.yaml        # GitHub Actions: build → Snyk scan → push to Docker Hub
│   └── frontend.yaml       # GitHub Actions: build → Snyk scan → push to Docker Hub
├── azure-pipelines.yml     # ADO: Validate → Build+Scan(Trivy) → Provision → Deploy
└── OBSERVABILITY.md        # Guide for deploying ELK + Prometheus + Grafana stacks
```

---

## Deployment Guide

### 1. Infrastructure Provisioning (Terraform)

Terraform provisions an AKS cluster, an Azure Key Vault (with randomly generated DB password), and a Service Principal scoped as Contributor on the resource group. The External Secrets Operator reads `db-user` and `db-password` from Key Vault at runtime.

**Prerequisites:** Azure CLI authenticated (`az login`), Terraform installed.

```bash
cd infrastructure
terraform init
terraform plan
terraform apply    # values can be provided in terraform.tfvars
```

Terraform writes a `kubeconfig` file (permissions `0600`) after the cluster is created.

**Required `terraform.tfvars` values:**
| Variable | Description |
|---|---|
| `rgname` | Azure resource group name |
| `location` | Azure region (default: `WestEurope`) |
| `service_principal_name` | Name for the new SP |
| `keyvault_name` | Key Vault name (globally unique) |
| `SUB_ID` | Azure subscription ID |
| `db_username` | PostgreSQL admin username (default: `backend`) |

---

### 2. CI Pipeline — GitHub Actions

Triggers on pushes to `main` when files inside `frontend/` or `backend/` change. Each workflow runs three jobs in sequence:

1. **build** — compiles the app (Maven / npm)
2. **push** — runs Snyk container scan, then pushes image to Docker Hub as `avurlerby/crud-app:<service>-latest`
3. **update-newtag-in-helm-chart** — uses `yq` to update `helm/crud-app-chart/values.yaml` with the new tag, then commits and pushes (`[skip ci]`)

**Required GitHub Secrets:**

| Secret | Purpose |
|---|---|
| `DOCKERHUB_USERNAME` | Docker Hub login |
| `DOCKERHUB_PASSWORD` | Docker Hub login |
| `AZURE_CREDENTIALS` | AKS access for secret sync |
| `TOKEN` | PAT for pushing the values.yaml commit |
| `DB_USER` | PostgreSQL username |
| `DB_PASSWORD` | PostgreSQL password |
| `SNYK_TOKEN` | Snyk container scanning |

**Required GitHub Variables:** `USER_EMAIL`, `USER_NAME` (used for the git commit identity).

---

### 3. CI Pipeline — Azure DevOps (`azure-pipelines.yml`)

A more complete pipeline with four stages that uses immutable git SHA image tags and pushes to Azure Container Registry (ACR).

| Stage | Jobs | Notes |
|---|---|---|
| **Validate** | Terraform fmt/validate, Helm lint | No cloud calls |
| **Build & Scan** | Maven build + tests, npm build, Docker build + Trivy scan, push to ACR | Fails on CRITICAL CVEs |
| **Provision** | Terraform plan (all branches), Terraform apply (main + approval gate) | Manual approval on `production` environment |
| **Deploy** | Update Helm values with SHA tag, wait for Argo CD Synced + Healthy | `[skip ci]` commit |

**Required ADO Variable Group (`crud-app-secrets`):** `ACR_NAME`, `AZURE_SUBSCRIPTION_ID`, `RESOURCE_GROUP`, `AKS_CLUSTER`.

The ADO pipeline uses the git commit SHA as the image tag (e.g., `abc1234`), giving immutable and traceable deployments — unlike the GitHub Actions pipeline which uses `frontend-latest`/`backend-latest`.

---

### 4. Continuous Delivery (Argo CD)

Apply the active application manifest to bootstrap Argo CD:

```bash
kubectl apply -f argocd/argocd-app.yaml
```

Argo CD monitors `helm/crud-app-chart/` on the `main` branch and automatically reconciles any drift:
- **Automated sync** with `prune: true` and `selfHeal: true`
- Retry up to 5 times with 5s backoff
- Deploys to the `crud-app` namespace (created automatically)

When either CI pipeline commits a new image tag to `values.yaml`, Argo CD detects the diff and executes a rolling update with zero downtime.

---

### 5. Ansible (Node Hardening & Deployment)

```bash
# Harden AKS worker VMs and deploy the application
ansible-playbook ansible/site.yml -i ansible/inventory/azure_rm.yml

# Zero-downtime rolling deploy with a specific image tag
ansible-playbook ansible/deploy.yml -e "image_tag=abc1234"
```

The `site.yml` master playbook:
- Runs the `os-hardening` role against the `role_worker` host group (AKS nodes via Azure dynamic inventory)
- Runs the `k8s-deploy` role against localhost to update cluster deployments

---

## Security

- No hardcoded secrets in application code.
- Terraform provisions Azure Key Vault; the External Secrets Operator syncs `db-user` and `db-password` into the cluster at runtime.
- Service Principal role assignments are scoped to the resource group (not subscription).
- DB password is randomly generated by Terraform (`random_password`, 16 chars with specials).
- Docker images are scanned for vulnerabilities: Snyk in GitHub Actions, Trivy (CRITICAL exit-code 1) in Azure DevOps.
- Separate `.github/workflows/snyk-security.yml` provides ongoing dependency scanning.

---

## Observability

The backend already exposes Prometheus metrics via Spring Actuator at `/actuator/prometheus`. The ELK and Prometheus+Grafana Helm charts exist under `helm/logging/` and `helm/monitoring/`, and their Argo CD applications are defined (but currently commented out) in `argocd/argocd-logging.yaml` and `argocd/argocd-monitoring.yaml`.

See **[OBSERVABILITY.md](OBSERVABILITY.md)** for full deployment instructions, access commands, and configuration details.

---

## Local Development

**Backend** (runs on port 8080):
```bash
cd backend
./mvnw spring-boot:run
```

**Frontend** — add a Vite dev proxy so `/api/` calls reach the local backend:

```js
// vite.config.js
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': { target: 'http://localhost:8080', rewrite: path => path.replace(/^\/api/, '') }
    }
  }
})
```

Then:
```bash
cd frontend
npm install
npm run dev
```

> Without the proxy, the frontend's `API_BASE_URL = "/api"` calls hit the Vite dev server itself and return 404. In production (Docker/K8s), nginx handles this proxy automatically via `nginx.conf`.
