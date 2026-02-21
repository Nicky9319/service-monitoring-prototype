# Grafana Stack Metrics Prototype

A complete FastAPI → Alloy → Prometheus → Grafana metrics pipeline prototype.

## Architecture

```
FastAPI Service (/metrics endpoint)
        ↓ (Scrape every 15s)
    Alloy (Scraper)
        ↓ (Remote Write)
   Prometheus (TSDB)
        ↓ (Query/Visualize)
    Grafana Dashboard
```

**Data Flow:**
- **FastAPI** exposes Prometheus metrics at `/metrics`
- **Alloy** periodically scrapes these metrics from the service
- **Alloy** pushes metrics to Prometheus via remote write API
- **Prometheus** stores the time series data
- **Grafana** queries Prometheus for visualization

## Quick Start

1. **Run the prototype:**
   ```bash
   ./run.sh
   ```

2. **Test the service:**
   ```bash
   curl http://localhost:8000/
   curl http://localhost:8000/health
   curl http://localhost:8000/simulate-load
   ```

3. **View metrics:**
   - Prometheus: http://localhost:9090
   - Grafana: http://localhost:3001 (admin/admin)
   - Alloy UI: http://localhost:3000

4. **Stop everything:**
   ```bash
   ./stop.sh
   ```

## Services

- **FastAPI Service** (port 8000): Exposes Prometheus metrics at `/metrics` endpoint
- **Alloy** (port 3000): Scrapes metrics from service every 15s, forwards to Prometheus via remote write
  - Metrics port: 12345 (for self-monitoring)
  - UI: http://localhost:3000
- **Prometheus** (port 9090): Receives metrics from Alloy, stores time series data
  - Remote write receiver enabled for Alloy
- **Grafana** (port 3001): Queries Prometheus and visualizes metrics
  - Default credentials: admin/admin

## Testing Load

Generate some metrics:
```bash
for i in {1..10}; do curl http://localhost:8000/simulate-load; done
```

## Metrics Available

- `http_requests_total`: Total HTTP requests
- `http_request_duration_seconds`: Request duration
- `active_connections`: Active connections

## Verifying the Pipeline

1. **Check if Alloy is scraping metrics:**
   ```bash
   curl http://localhost:8000/metrics
   ```
   Should return Prometheus format metrics

2. **Check Alloy configuration:**
   - Open Alloy UI: http://localhost:3000
   - Should show "fastapi_service" scrape job running

3. **Check if metrics reached Prometheus:**
   - Open http://localhost:9090
   - Go to "Targets" tab
   - Should show "alloy" and "prometheus" jobs
   - Go to "Graph" and search for metrics like `http_requests_total`

4. **Verify in Grafana:**
   - Open http://localhost:3001
   - Log in with admin/admin
   - Add Prometheus as a data source
   - Create a dashboard with metrics

## Troubleshooting

- **Alloy not scraping:** Check Alloy logs: `docker logs alloy`
- **Metrics not in Prometheus:**
  - Check Prometheus remote write receiver: `docker logs prometheus | grep remote`
  - Verify Alloy can reach host.docker.internal:8000
- **Connection errors:** Ensure FastAPI service is running: `curl http://localhost:8000/health`
- **View current metrics:** `curl http://localhost:8000/metrics`
