# ELK Stack Logging for aks-app

This directory contains Helm charts for deploying the ELK (Elasticsearch, Logstash, Kibana) stack for centralized logging in the aks-app Kubernetes cluster.

## Components

### 1. **Elasticsearch** (elasticsearch/)
- **Role**: Centralized log storage and search engine
- **Version**: 7.16.2
- **Deployment Type**: Single-node cluster
- **Memory**: 256-768 Mi
- **Port**: 9200 (REST API), 9300 (node communication)
- **Service**: `es-master-service:9200`

### 2. **Filebeat** (filebeat/)
- **Role**: Log collector agent
- **Version**: 7.16.2
- **Deployment Type**: DaemonSet (runs on every node)
- **Memory**: 100-200 Mi per instance
- **Function**: Automatically discovers and collects logs from containers in the `app` namespace
- **Configuration**: Kubernetes autodiscover with ConfigMap-based filebeat.yml

### 3. **Kibana** (kibana/)
- **Role**: Log visualization and dashboarding UI
- **Version**: 7.16.2
- **Deployment Type**: Deployment (single replica)
- **Memory**: 384-768 Mi
- **Port**: 5601
- **Service**: `kibana-service:5601`

## Deployment

### Deploy ELK Stack
```bash
# Create logging namespace
kubectl create namespace logging

# Deploy Elasticsearch
helm install elasticsearch ./elasticsearch -n logging

# Deploy Filebeat (collects logs from 'app' namespace)
helm install filebeat ./filebeat -n logging

# Deploy Kibana
helm install kibana ./kibana -n logging
```

### Access Kibana
```bash
# Port-forward to access Kibana UI
kubectl port-forward svc/kibana-service 5601:5601 -n logging

# Open browser: http://localhost:5601
```

## Data Flow

```
Your Application (stdout/stderr)
        ↓
Docker Container Logs
        ↓
Filebeat (DaemonSet) → Autodiscover
        ↓
Elasticsearch (Centralized Storage)
        ↓
Kibana (Search & Visualization)
```

## Configuration Details

### Filebeat Autodiscover
- **Targets**: Containers in `app` namespace (configurable via `appNamespace` in values.yaml)
- **Log Source**: `/var/log/containers/*` (Docker logs directory)
- **Volume Mounts**:
  - `/var/lib/docker/containers` (read-only)
  - `/var/log` (read-only)
  - `/var/lib/filebeat-data` (writable, for state tracking)

### RBAC (Role-Based Access Control)
Filebeat requires:
- `ServiceAccount` in logging namespace
- `ClusterRole` with `get`, `watch`, `list` permissions on namespaces, pods, and nodes
- `ClusterRoleBinding` to bind the role to the service account

## Customization

### Update appNamespace to Collect from Specific Namespace
```yaml
# filebeat/values.yaml
appNamespace: crud  # Change to target namespace
```

### Adjust Resource Limits
```yaml
# elasticsearch/values.yaml
resources:
  requests:
    cpu: 100m
    memory: 512Mi
  limits:
    cpu: 300m
    memory: 768Mi
```

## Troubleshooting

### Check Filebeat Status
```bash
kubectl get daemonset -n logging
kubectl logs -n logging -l k8s-app=filebeat
```

### Check Elasticsearch Health
```bash
kubectl exec -it -n logging es-0 -- curl localhost:9200/_cluster/health
```

### Verify Kibana Connectivity to Elasticsearch
```bash
kubectl logs -n logging -l node.type=kibana-node
```

## Next Steps

1. Configure Kibana to create index patterns
2. Create dashboards for application metrics
3. Set up alerts based on log patterns
4. Consider adding Logstash for advanced log processing
5. Integrate with application structured logging (JSON logs from backend)
