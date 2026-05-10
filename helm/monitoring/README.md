# Monitoring Stack - Prometheus & Grafana

This directory contains Helm charts for deploying Prometheus and Grafana monitoring stack for the aks-app Kubernetes cluster.

## Components

### 1. **Prometheus** (prometheus/)
- **Role**: Metrics collection and time-series database
- **Version**: v2.45.0
- **Memory**: 256-512 Mi
- **Port**: 9090
- **Service**: `prometheus:9090`
- **Retention**: 15 days (configurable)

**What it monitors:**
- Kubernetes API server
- Kubernetes nodes and kubelet
- Container metrics
- Backend application (Spring Boot with `/actuator/prometheus`)

### 2. **Grafana** (grafana/)
- **Role**: Metrics visualization and dashboarding
- **Version**: 10.0.0
- **Memory**: 128-512 Mi
- **Port**: 3000
- **Service**: `grafana:3000`
- **Default User**: admin
- **Default Password**: admin (⚠️ change in production!)

**Includes:**
- Pre-configured Prometheus data source
- Sample Kubernetes cluster monitoring dashboard
- Support for custom dashboards

## Deployment with ArgoCD

### Step 1: Deploy Monitoring Stack via ArgoCD

```bash
# Apply the ArgoCD Application manifests for monitoring
kubectl apply -f argocd/argocd-monitoring.yaml

# Verify deployment
kubectl get applications -n argocd | grep monitoring
```

### Step 2: Deploy Logging Stack via ArgoCD (Optional, already deployed)

```bash
# Apply the ArgoCD Application manifests for logging
kubectl apply -f argocd/argocd-logging.yaml

# Verify deployment
kubectl get applications -n argocd | grep logging
```

### Step 3: Access the Tools

#### Access Prometheus
```bash
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
# Open: http://localhost:9090
```

#### Access Grafana
```bash
kubectl port-forward svc/grafana 3000:3000 -n monitoring
# Open: http://localhost:3000
# Login with: admin / admin
```

#### Access Kibana (Logging)
```bash
kubectl port-forward svc/kibana-service 5601:5601 -n logging
# Open: http://localhost:5601
```

## Data Flow

```
Application Metrics (stdout + Kubernetes API)
        ↓
Prometheus (Scrapes metrics from all components)
        ↓
Grafana (Visualizes metrics via dashboards)
        ↓
User Dashboard (http://localhost:3000)
```

## Backend Integration

To enable metrics collection from your backend:

### 1. Add Spring Boot Actuator to Backend
```xml
<!-- pom.xml -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

### 2. Configure Actuator in Backend
```yaml
# application.yml
management:
  endpoints:
    web:
      exposure:
        include: health,metrics,prometheus
  endpoint:
    prometheus:
      enabled: true
```

### 3. Add Pod Annotations to Backend Deployment
```yaml
# helm/crud-app-chart/templates/backend.yaml
podAnnotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/actuator/prometheus"
```

## Metrics Available

### Kubernetes Metrics
- Node CPU, Memory, Disk usage
- Pod resource consumption
- Container network I/O
- Kubelet health

### Application Metrics (if Actuator enabled)
- HTTP request rates & latency
- JVM memory, GC, threads
- Database query metrics
- Custom business metrics

## Creating Custom Dashboards

1. **Access Grafana** at http://localhost:3000
2. **Create a new dashboard** or import from Grafana community library
3. **Add panels** with Prometheus queries
4. **Example queries:**
   ```
   # Container CPU usage
   sum(rate(container_cpu_usage_seconds_total[5m])) by (pod_name)
   
   # Container memory usage
   sum(container_memory_usage_bytes) by (pod_name)
   
   # HTTP requests per second
   rate(http_requests_total[1m])
   ```

## Troubleshooting

### Check Prometheus Scrape Status
```bash
kubectl exec -it -n monitoring prometheus-xxxx -- curl localhost:9090/api/v1/targets
```

### Check Backend Metrics Endpoint
```bash
kubectl port-forward svc/backend 8080:8080 -n default
curl http://localhost:8080/actuator/prometheus
```

### View Prometheus Logs
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=monitoring-prometheus
```

### View Grafana Logs
```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=monitoring-grafana
```

## Configuration

### Adjust Prometheus Scrape Interval
```yaml
# helm/monitoring/prometheus/values.yaml
prometheus:
  scrapeInterval: 30s    # Default: 15s
  evaluationInterval: 30s
  retentionTime: 30d     # Default: 15d
```

### Change Grafana Admin Password
```yaml
# helm/monitoring/grafana/values.yaml
grafana:
  adminPassword: "your-secure-password"
```

## Customization

### Add Custom Scrape Job
Edit `helm/monitoring/prometheus/templates/configmap.yaml` and add under `scrape_configs`:

```yaml
- job_name: 'custom-service'
  static_configs:
  - targets: ['custom-service:9090']
```

## Next Steps

1. **Enable Actuator in Backend** (see Backend Integration section)
2. **Create Custom Dashboards** for application-specific metrics
3. **Set up Alerts** based on thresholds
4. **Integrate with Alertmanager** for alert notifications
5. **Add Loki** for log aggregation (alternative to ELK)
