# Complete Observability Stack Deployment Guide

This guide explains how to deploy the complete observability stack (Logging + Monitoring) using ArgoCD.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                    AKS Cluster (Kubernetes)                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌──────────────────┐          ┌──────────────────┐                 │
│  │   Application    │          │   Kubernetes     │                 │
│  │  (Backend/Logs)  │          │  (API/Metrics)   │                 │
│  └────────┬─────────┘          └────────┬─────────┘                 │
│           │                             │                           │
│    ┌──────▼─────────────────────────────▼──────┐                    │
│    │     Prometheus Scraper                    │                    │
│    │  - Collects metrics from all components   │                    │
│    │  - Interval: 15s (configurable)           │                    │
│    └──────┬──────────────────────────┬─────────┘                    │
│           │                          │                              │
│    ┌──────▼──────────┐      ┌────────▼──────────┐                  │
│    │  Elasticsearch  │      │   Prometheus      │                  │
│    │  (Log Storage)  │      │  (Metric Storage) │                  │
│    └──────┬──────────┘      └────────┬──────────┘                  │
│           │                          │                              │
│    ┌──────▼──────────┐      ┌────────▼──────────┐                  │
│    │     Kibana      │      │     Grafana       │                  │
│    │  (Log UI)       │      │  (Dashboards)     │                  │
│    └─────────────────┘      └───────────────────┘                  │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
                            ▲
                            │
                       ArgoCD Sync
                     (GitOps Driven)
                            │
                     GitHub Repository
                        (This Repo)
```

## Directory Structure

```
helm/
├── crud-app-chart/          # Main application (Backend, Frontend, Database)
├── logging/                 # ELK Stack (Elasticsearch, Filebeat, Kibana)
│   ├── elasticsearch/
│   ├── filebeat/
│   └── kibana/
└── monitoring/              # Prometheus & Grafana
    ├── prometheus/
    └── grafana/

argocd/
├── argocd-app.yaml          # Main application deployment
├── argocd-logging.yaml       # Logging stack (ELK)
└── argocd-monitoring.yaml    # Monitoring stack (Prometheus + Grafana)
```

## Deployment Steps

### Step 1: Prerequisites
- AKS cluster running
- ArgoCD installed in the cluster
- kubectl access to the cluster

### Step 2: Deploy Logging Stack (ELK)

```bash
# Deploy Elasticsearch, Filebeat, and Kibana
kubectl apply -f argocd/argocd-logging.yaml

# Verify ArgoCD applications are created
kubectl get applications -n argocd

# Monitor deployment status
watch kubectl get pods -n logging
```

**Expected Resources:**
- 1 Elasticsearch pod (centralized log storage)
- 1 Filebeat pod per node (log collector)
- 1 Kibana pod (visualization)

### Step 3: Deploy Monitoring Stack (Prometheus + Grafana)

```bash
# Deploy Prometheus and Grafana
kubectl apply -f argocd/argocd-monitoring.yaml

# Verify ArgoCD applications are created
kubectl get applications -n argocd | grep monitoring

# Monitor deployment status
watch kubectl get pods -n monitoring
```

**Expected Resources:**
- 1 Prometheus pod (metrics storage)
- 1 Grafana pod (dashboarding)

### Step 4: Verify All Components

```bash
# Check all observability namespaces
kubectl get pods -n logging
kubectl get pods -n monitoring

# Check services
kubectl get svc -n logging
kubectl get svc -n monitoring

# Check ArgoCD applications
kubectl get applications -n argocd
```

## Accessing the Dashboards

### Access Prometheus
```bash
kubectl port-forward svc/prometheus 9090:9090 -n monitoring &
# Open: http://localhost:9090
```

### Access Grafana
```bash
kubectl port-forward svc/grafana 3000:3000 -n monitoring &
# Open: http://localhost:3000
# Login: admin / admin (change password!)
```

### Access Kibana (Logs)
```bash
kubectl port-forward svc/kibana-service 5601:5601 -n logging &
# Open: http://localhost:5601
```

## Integration with Backend Application

To collect metrics from your backend application:

### 1. Update Backend Dependencies (pom.xml)

```xml
<!-- Spring Boot Actuator for metrics exposure -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>

<!-- Micrometer Prometheus registry -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

### 2. Configure Actuator (application.yml)

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,metrics,prometheus
  endpoint:
    prometheus:
      enabled: true
```

### 3. Update Backend Helm Chart

Add pod annotations in `helm/crud-app-chart/templates/backend.yaml`:

```yaml
podAnnotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/actuator/prometheus"
```

### 4. Update Backend Image

After making changes, rebuild and push the Docker image:

```bash
# In backend directory
docker build -t avurlerby/crud-app:backend-latest .
docker push avurlerby/crud-app:backend-latest

# GitHub Actions will automatically update helm values.yaml
```

## Data Collection

### Logging Pipeline
```
Backend (stdout) 
    → Docker Container Logs 
    → Filebeat (DaemonSet) 
    → Elasticsearch 
    → Kibana UI
```

### Monitoring Pipeline
```
Kubernetes Components (kubelet, API server, nodes)
Application Metrics (/actuator/prometheus)
    → Prometheus Scraper 
    → Prometheus DB 
    → Grafana Dashboards
```

## Key Metrics & Logs

### Metrics Collected
- **Node Metrics:** CPU, Memory, Disk, Network
- **Pod Metrics:** Resource consumption
- **Application Metrics:** Request rate, latency, JVM metrics
- **Kubernetes Metrics:** API server, kubelet health

### Logs Collected
- Backend application logs (stderr/stdout)
- Frontend access logs (nginx)
- Container system logs
- Kubernetes events

## Updating Configurations

### Change Prometheus Scrape Interval
```bash
# Edit prometheus values
helm/monitoring/prometheus/values.yaml

prometheus:
  scrapeInterval: 30s    # Change from 15s
```

Then commit and push - ArgoCD will auto-sync.

### Change Grafana Admin Password
```bash
# Edit grafana values
helm/monitoring/grafana/values.yaml

grafana:
  adminPassword: "your-new-password"
```

### Add Custom Prometheus Scrape Jobs
Edit `helm/monitoring/prometheus/templates/configmap.yaml` and add your scrape config.

## Troubleshooting

### Pods not starting?
```bash
# Check pod status
kubectl describe pod <pod-name> -n monitoring
kubectl logs <pod-name> -n monitoring
```

### ArgoCD not syncing?
```bash
# Check ArgoCD application status
kubectl describe application aks-prometheus-monitoring -n argocd
kubectl logs -n argocd deployment/argocd-application-controller
```

### Prometheus not scraping backend?
```bash
# Check prometheus targets
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
# Visit: http://localhost:9090/targets
# Look for "backend-app" job - should show UP
```

### No logs in Kibana?
```bash
# Check filebeat status
kubectl logs -n logging -l k8s-app=filebeat
kubectl logs -n logging -l node.type=es-node-master
```

## Next Steps

1. **Create Custom Grafana Dashboards** for business metrics
2. **Set up Prometheus Alerts** for critical thresholds
3. **Configure Alert Routing** via Alertmanager
4. **Integrate with Slack/Teams** for notifications
5. **Export Logs to Cloud** (optional: Azure Monitor, CloudWatch)
6. **Add Custom Metrics** in backend application

## References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Dashboards](https://grafana.com/grafana/dashboards/)
- [Elasticsearch Documentation](https://www.elastic.co/guide/index.html)
- [Kibana Guide](https://www.elastic.co/guide/en/kibana/current/index.html)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
