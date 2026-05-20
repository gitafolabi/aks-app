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

### 2. CI Pipelines — Overview

Two independent CI pipelines build and push Docker images. They serve different purposes and use different registries and image tagging strategies:

| | GitHub Actions | Azure DevOps |
|---|---|---|
| **File** | `.github/workflows/frontend.yaml` / `backend.yaml` | `azure-pipelines.yml` |
| **Trigger** | Push to `main` (path-filtered per service) | Push/PR to `main` (excludes `*.md` and `values.yaml`) |
| **Registry** | Docker Hub (`avurlerby/crud-app`) | Azure Container Registry (ACR) |
| **Image tag** | `frontend-latest` / `backend-latest` | Git commit SHA (e.g. `abc1234`) — immutable |
| **Security scan** | Snyk container monitor | Trivy — fails build on CRITICAL CVEs |
| **Infra provisioning** | No | Yes — Terraform plan/apply stage |
| **Scope** | Lightweight, service-scoped | Full pipeline: validate → build → provision → deploy |

---

### 2a. GitHub Actions (`.github/workflows/`)

Two separate workflows — `frontend.yaml` and `backend.yaml` — each triggered independently when their respective directory changes.

**Job flow (same structure for both):**

```
push to main (frontend/** or backend/**)
        │
        ▼
   [build]
   ├── frontend: npm ci → npm run build (Node 20)
   └── backend:  ./mvnw clean install -DskipTests (JDK 21)
        │
        ▼ (needs: build)
   [push]
   ├── docker/setup-buildx
   ├── Login to Docker Hub
   ├── docker build (local, --load, not yet pushed)
   ├── snyk container monitor    ← vulnerability scan (non-blocking: || true)
   └── docker push avurlerby/crud-app:<service>-latest
        │
        ▼ (needs: push)
   [update-newtag-in-helm-chart]
   ├── git pull --rebase origin main   ← avoids race condition
   ├── yq e '.frontend/backend.image.tag = "...-latest"' -i helm/crud-app-chart/values.yaml
   └── git commit -m "Update <service> tag [skip ci]" && git push
```

The `[skip ci]` commit message prevents the values.yaml update from re-triggering the workflow. The rebase-before-modify pattern avoids push conflicts when both frontend and backend pipelines run concurrently.

**Required GitHub Secrets:**

| Secret | Purpose |
|---|---|
| `DOCKERHUB_USERNAME` | Docker Hub login |
| `DOCKERHUB_PASSWORD` | Docker Hub login |
| `AZURE_CREDENTIALS` | AKS access |
| `TOKEN` | PAT with repo write scope (for the values.yaml commit) |
| `DB_USER` | PostgreSQL username |
| `DB_PASSWORD` | PostgreSQL password |
| `SNYK_TOKEN` | Snyk container scanning |

**Required GitHub Variables:** `USER_EMAIL`, `USER_NAME` (git commit identity for the values.yaml push).

---

### 2b. Azure DevOps (`azure-pipelines.yml`)

A four-stage pipeline that covers the full lifecycle from static validation through to a verified deployment. Uses the git commit SHA as the image tag so every image is uniquely and traceably tagged.

**Stage flow:**

```
push/PR to main
        │
        ▼
   [Validate]  ── runs in parallel ──────────────────────┐
   ├── terraform fmt -check -recursive                   │
   ├── terraform init -backend=false                     │
   ├── terraform validate                                │
   └── helm lint helm/crud-app-chart    ◄────────────────┘
        │ (no cloud calls — fast feedback)
        ▼
   [Build & Scan]
   ├── backend: ./mvnw clean package (tests ON) → JUnit results published
   ├── frontend: npm ci → npm run build
   └── docker_build_push (matrix: backend + frontend, runs in parallel)
       ├── az acr login
       ├── docker build -t <ACR>.azurecr.io/<service>:<git-SHA>
       ├── trivy image --exit-code 1 --severity CRITICAL   ← blocks on critical CVEs
       └── docker push → ACR
        │
        ▼
   [Provision]  (main branch only for apply)
   ├── terraform plan → artifact: tfplan
   └── terraform apply  ← requires manual approval on 'production' ADO environment
        │
        ▼
   [Deploy]  (main branch only)
   ├── yq: update .backend.image.tag and .frontend.image.tag to <git-SHA>
   ├── git commit -m "ci: update image tags to <git-SHA> [skip ci]" && push
   └── kubectl wait application/crud-app --for=jsonpath=...=Synced --timeout=300s
       kubectl wait application/crud-app --for=jsonpath=...=Healthy --timeout=300s
```

The final step polls Argo CD directly — the pipeline only marks success after the cluster is confirmed Synced and Healthy.

**Required ADO Variable Group (`crud-app-secrets`):**

| Variable | Purpose |
|---|---|
| `ACR_NAME` | Azure Container Registry name |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription |
| `RESOURCE_GROUP` | Resource group containing the AKS cluster |
| `AKS_CLUSTER` | AKS cluster name (for `az aks get-credentials`) |

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
