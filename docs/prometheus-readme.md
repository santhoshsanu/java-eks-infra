# Prometheus — Architecture, Components & Project Implementation

---

## What is Prometheus?

Prometheus is an open-source **time-series monitoring and alerting toolkit** built at SoundCloud and donated to CNCF (Cloud Native Computing Foundation). It is the de facto standard for monitoring Kubernetes workloads.

**Core idea:** Prometheus **pulls** (scrapes) metrics from targets at regular intervals, stores them as time-series data, and allows querying via PromQL.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Prometheus Server                        │
│                                                             │
│  ┌──────────────┐    ┌──────────────┐   ┌───────────────┐  │
│  │  Retrieval   │    │   Storage    │   │  HTTP Server  │  │
│  │  (Scraper)   │───▶│  (TSDB)      │◀──│  (PromQL API) │  │
│  └──────────────┘    └──────────────┘   └───────────────┘  │
│         │                                       │           │
│    scrape_configs                          /api/v1/query    │
└─────────┼─────────────────────────────────────┼────────────┘
          │                                      │
          ▼                                      ▼
   Target endpoints                         Grafana
   /metrics                                 Alertmanager
```

---

## Core Components

### 1. Prometheus Server
The main component. It does three things:
- **Retrieval** — scrapes metrics from configured targets
- **Storage** — stores data in TSDB (Time Series Database) on disk
- **HTTP API** — exposes PromQL query endpoint for Grafana

### 2. TSDB (Time Series Database)
Prometheus stores all metrics in its own embedded database:
- Data stored on disk at `/prometheus` directory
- Each metric = time series identified by metric name + labels
- Configurable retention period (we use 7 days)
- Format: `metric_name{label1="value1", label2="value2"} numeric_value timestamp`

### 3. Retrieval (Scraper)
- Reads `scrape_configs` from `prometheus.yml`
- Calls `GET /metrics` on each target every `scrape_interval` (15s in our setup)
- Parses Prometheus exposition format
- Stores data in TSDB

### 4. PromQL (Query Language)
- Query language to select and aggregate time-series data
- Used by Grafana to build dashboards
- Examples:
  ```promql
  rate(http_requests_total[5m])           # request rate
  node_memory_MemAvailable_bytes          # node RAM
  kube_pod_status_phase{phase="Running"}  # running pods
  ```

### 5. Alertmanager (separate component)
- Receives alerts from Prometheus
- Routes to Slack, email, PagerDuty
- Not configured in this project yet (Phase 3)

### 6. Service Discovery
- Automatically finds targets in dynamic environments
- Kubernetes SD — discovers pods, nodes, services automatically
- In this project we use **static configs** for simplicity

---

## Pull vs Push Model

```
PULL (Prometheus default):
  Prometheus ──── scrapes ────▶ Target /metrics endpoint
  Prometheus controls timing
  Centralized config

PUSH (alternative tools like StatsD):
  Application ──── pushes ────▶ Monitoring server
  Application controls timing
  Distributed config
```

**Why Prometheus uses PULL:**
- Prometheus knows if a target is down (no metrics = down)
- Centralized scrape config — easy to manage
- Better for Kubernetes dynamic environments

---

## Exporters

Exporters are **adapters** that expose metrics in Prometheus format from systems that don't natively support it.

### How an Exporter Works
```
System (MySQL, Linux, K8s)
        ↓ native API/system calls
Exporter reads data
        ↓ converts to Prometheus format
/metrics endpoint
        ↓ Prometheus scrapes
TSDB storage
```

### Common Exporters

| Exporter | What it monitors | Port |
|----------|-----------------|------|
| **Node Exporter** | EC2/Linux OS metrics (CPU, RAM, disk, network) | 9100 |
| **kube-state-metrics** | Kubernetes object state (pods, deployments, nodes) | 8080 |
| **cAdvisor** | Container resource usage (built into kubelet) | 4194 |
| **Blackbox Exporter** | HTTP/TCP endpoint probing | 9115 |
| **MySQL Exporter** | MySQL database metrics | 9104 |
| **Redis Exporter** | Redis metrics | 9121 |
| **JMX Exporter** | Java/JVM metrics via JMX | 5556 |

### Node Exporter — Metrics It Exposes
```
node_cpu_seconds_total          ← CPU usage per mode (idle, user, system)
node_memory_MemTotal_bytes      ← Total RAM
node_memory_MemAvailable_bytes  ← Available RAM
node_disk_read_bytes_total      ← Disk reads
node_disk_written_bytes_total   ← Disk writes
node_network_receive_bytes_total ← Network received
node_filesystem_avail_bytes     ← Disk space available
node_load1                      ← 1-minute load average
```

### kube-state-metrics — Metrics It Exposes
```
kube_pod_status_phase                      ← Pod phase (Running/Pending/Failed)
kube_pod_container_status_restarts_total   ← Container restart count
kube_deployment_status_replicas            ← Current replicas
kube_deployment_spec_replicas              ← Desired replicas
kube_node_status_condition                 ← Node Ready/NotReady
kube_pod_container_resource_requests       ← CPU/memory requests
kube_pod_container_resource_limits         ← CPU/memory limits
kube_namespace_status_phase                ← Namespace status
```

---

## Prometheus Data Model

### Metric Types

| Type | Description | Example |
|------|-------------|---------|
| **Counter** | Always increases, never decreases | `http_requests_total` |
| **Gauge** | Can go up and down | `node_memory_MemAvailable_bytes` |
| **Histogram** | Distribution of values in buckets | `http_request_duration_seconds` |
| **Summary** | Similar to histogram with quantiles | `rpc_duration_seconds` |

### Labels
Labels add dimensions to metrics:
```
http_requests_total{method="GET", status="200", path="/api/products"} 1547
http_requests_total{method="POST", status="201", path="/api/products"} 23
http_requests_total{method="GET", status="500", path="/api/users"} 3
```

---

## PromQL Quick Reference

```promql
# Current value
node_memory_MemAvailable_bytes

# Rate of increase per second over last 5 minutes
rate(http_requests_total[5m])

# Filter by label
http_requests_total{status="200"}

# Regex match
http_requests_total{status=~"2.."}    # all 2xx
http_requests_total{status!~"2.."}    # not 2xx

# Aggregate across instances
sum(rate(http_requests_total[5m])) by (method)

# p95 response time
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# CPU usage percentage
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Available memory percentage
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100
```

---

## Implementation in This Project

### Files
```
java-eks-infra/
├── terraform/
│   └── helm.tf                  ← installs Node Exporter + kube-state-metrics
└── monitoring/
    └── prometheus.yaml          ← Prometheus deployment + scrape config
```

### How Prometheus is Deployed

**Prometheus server** — deployed as K8s Deployment via `monitoring/prometheus.yaml`:
```yaml
image: prom/prometheus:v2.50.1
args:
  - "--config.file=/etc/prometheus/prometheus.yml"
  - "--storage.tsdb.retention.time=7d"    # keeps 7 days of data
  - "--web.enable-lifecycle"              # allows config reload
```

**Node Exporter** — deployed as DaemonSet via Helm (Terraform):
```hcl
resource "helm_release" "node_exporter" {
  name       = "node-exporter"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-node-exporter"
  namespace  = "monitoring"
  version    = "4.24.0"
}
```

**kube-state-metrics** — deployed as Deployment via Helm (Terraform):
```hcl
resource "helm_release" "kube_state_metrics" {
  name       = "kube-state-metrics"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-state-metrics"
  namespace  = "monitoring"
  version    = "5.15.2"
}
```

### Scrape Configuration

```yaml
# prometheus.yaml scrape_configs
scrape_configs:

  # Application metrics via OTEL Collector
  - job_name: 'otel-collector'
    targets: ['otel-collector.monitoring.svc.cluster.local:8889']

  # Spring Boot Actuator direct scrape
  - job_name: 'product-catalog-backend'
    targets: ['backend-service.product-catalog.svc.cluster.local:80']
    metrics_path: '/actuator/prometheus'

  # EC2 node metrics
  - job_name: 'node-exporter'
    targets: ['node-exporter-prometheus-node-exporter.monitoring.svc.cluster.local:9100']

  # K8s object metrics
  - job_name: 'kube-state-metrics'
    targets: ['kube-state-metrics.monitoring.svc.cluster.local:8080']

  # Container metrics via kubelet
  - job_name: 'kubernetes-cadvisor'
    kubernetes_sd_configs:
      - role: node
```

### RBAC for K8s Metrics
Prometheus needs ClusterRole to scrape K8s nodes and pods:
```yaml
rules:
  - apiGroups: [""]
    resources: ["nodes", "nodes/proxy", "nodes/metrics", "pods"]
    verbs: ["get", "list", "watch"]
  - nonResourceURLs: ["/metrics", "/metrics/cadvisor"]
    verbs: ["get"]
```

### Data Flow

```
EC2 Node
  └── Node Exporter :9100
          ↓ scraped every 15s
EKS Cluster
  └── kube-state-metrics :8080
          ↓ scraped every 15s
Spring Boot Apps
  └── /actuator/prometheus
          ↓ scraped every 15s
OTEL Collector :8889
          ↓ scraped every 15s
                ↓
          Prometheus TSDB
          (7 days retention)
                ↓ PromQL queries
             Grafana
```

### Accessing Prometheus UI

```bash
# Port forward Prometheus UI locally
kubectl port-forward svc/prometheus 9090:9090 -n monitoring

# Open browser → http://localhost:9090
# Status → Targets → verify all jobs are UP
# Graph → type PromQL queries
```

### Verifying Targets are UP

```bash
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
```
Open `http://localhost:9090/targets` — all jobs should show `UP`:
```
otel-collector          → UP
product-catalog-backend → UP
node-exporter           → UP
kube-state-metrics      → UP
kubernetes-cadvisor     → UP
prometheus              → UP
```

---

## Key Takeaways

1. Prometheus **pulls** metrics — targets expose `/metrics` endpoint
2. Exporters are **adapters** — Node Exporter for OS, kube-state-metrics for K8s
3. All data stored as **time-series** with labels
4. **PromQL** is used to query data
5. **Grafana** reads from Prometheus via HTTP API
6. In this project — Node Exporter and kube-state-metrics installed via **Helm** managed by **Terraform**
7. Prometheus needs **ClusterRole RBAC** to scrape Kubernetes nodes
