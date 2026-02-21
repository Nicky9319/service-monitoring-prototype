#!/bin/bash

# Grafana Stack Metrics Prototype Setup Script
# Creates a complete FastAPI -> Alloy -> Prometheus pipeline

set -e

echo "🚀 Setting up Grafana Stack Metrics Prototype..."

# Create project directory
PROJECT_DIR="metrics-prototype"
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

echo "📁 Created project directory: $PROJECT_DIR"

# Create main.py - FastAPI service that pushes metrics to Alloy
cat > main.py << 'EOF'
from fastapi import FastAPI, BackgroundTasks
from prometheus_client import Counter, Histogram, Gauge, CollectorRegistry, generate_latest
import httpx
import time
import asyncio
import json
from datetime import datetime
from contextlib import asynccontextmanager

app = FastAPI(title="Metrics Prototype Service")

# Create custom registry for our metrics
registry = CollectorRegistry()

# Define metrics
request_counter = Counter(
    'http_requests_total', 
    'Total HTTP requests', 
    ['method', 'endpoint', 'status'], 
    registry=registry
)

request_duration = Histogram(
    'http_request_duration_seconds', 
    'HTTP request duration', 
    ['method', 'endpoint'],
    registry=registry
)

active_connections = Gauge(
    'active_connections', 
    'Number of active connections',
    registry=registry
)

# Alloy endpoint for pushing metrics
ALLOY_ENDPOINT = "http://localhost:12345/api/v1/push"

async def push_metrics_to_alloy():
    """Push metrics to Alloy endpoint"""
    try:
        # Generate metrics in Prometheus format
        metrics_data = generate_latest(registry).decode('utf-8')
        
        # Prepare payload for Alloy
        payload = {
            "streams": [
                {
                    "labels": "{job=\"fastapi-service\"}",
                    "entries": [
                        {
                            "ts": str(int(time.time() * 1000000000)),  # nanoseconds
                            "line": metrics_data
                        }
                    ]
                }
            ]
        }
        
        async with httpx.AsyncClient() as client:
            response = await client.post(
                ALLOY_ENDPOINT,
                json=payload,
                headers={"Content-Type": "application/json"},
                timeout=5.0
            )
            
            if response.status_code == 200:
                print(f"✅ Metrics pushed successfully at {datetime.now()}")
            else:
                print(f"❌ Failed to push metrics: {response.status_code}")
                
    except Exception as e:
        print(f"🚨 Error pushing metrics: {e}")

async def metrics_pusher():
    """Background task to push metrics every 15 seconds"""
    while True:
        await push_metrics_to_alloy()
        await asyncio.sleep(15)  # Push every 15 seconds

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Start background metrics pusher
    task = asyncio.create_task(metrics_pusher())
    yield
    task.cancel()

app = FastAPI(lifespan=lifespan)

@app.middleware("http")
async def metrics_middleware(request, call_next):
    start_time = time.time()
    active_connections.inc()
    
    response = await call_next(request)
    
    duration = time.time() - start_time
    
    # Record metrics
    request_counter.labels(
        method=request.method,
        endpoint=request.url.path,
        status=str(response.status_code)
    ).inc()
    
    request_duration.labels(
        method=request.method,
        endpoint=request.url.path
    ).observe(duration)
    
    active_connections.dec()
    
    return response

@app.get("/")
async def root():
    """Root endpoint"""
    return {"message": "Metrics Prototype Service", "timestamp": datetime.now()}

@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": datetime.now()}

@app.get("/metrics")
async def get_metrics():
    """Expose metrics in Prometheus format"""
    return generate_latest(registry).decode('utf-8')

@app.post("/simulate-load")
async def simulate_load():
    """Simulate some processing load"""
    # Simulate work
    await asyncio.sleep(0.1)
    return {"message": "Load simulated", "processing_time": "0.1s"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

echo "✅ Created main.py"

# Create requirements.txt
cat > requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
prometheus-client==0.19.0
httpx==0.25.2
EOF

echo "✅ Created requirements.txt"

# Create Alloy configuration
cat > alloy-config.yaml << 'EOF'
// Alloy configuration for receiving and forwarding metrics

// HTTP server to receive pushed metrics
loki.source.api "metrics_receiver" {
  http {
    listen_address = "0.0.0.0"
    listen_port    = 12345
  }
  forward_to = [loki.process.metrics_parser.receiver]
}

// Parse and process metrics
loki.process.metrics_parser" {
  stage.regex {
    expression = "(?P<metrics>.*)"
  }
  
  forward_to = [prometheus.relabel.metrics_processing.receiver]
}

// Prometheus metrics processing
prometheus.relabel.metrics_processing" {
  forward_to = [prometheus.remote_write.default.receiver]
  
  rule {
    source_labels = ["__name__"]
    target_label  = "service"
    replacement   = "fastapi-prototype"
  }
}

// Forward to Prometheus
prometheus.remote_write "default" {
  endpoint {
    url = "http://prometheus:9090/api/v1/write"
    
    queue_config {
      capacity             = 10000
      max_samples_per_send = 5000
      batch_send_deadline  = "5s"
    }
  }
}

// Scrape Alloy's own metrics
prometheus.scrape "alloy_metrics" {
  targets = [{"__address__" = "localhost:12345"}]
  forward_to = [prometheus.remote_write.default.receiver]
  scrape_interval = "30s"
}

// Also scrape the FastAPI service directly as backup
prometheus.scrape "fastapi_metrics" {
  targets = [{"__address__" = "host.docker.internal:8000"}]
  forward_to = [prometheus.remote_write.default.receiver]
  scrape_interval = "15s"
  metrics_path = "/metrics"
}
EOF

echo "✅ Created alloy-config.yaml"

# Create Prometheus configuration
cat > prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'alloy'
    static_configs:
      - targets: ['alloy:12345']
    scrape_interval: 30s

  - job_name: 'fastapi-service'
    static_configs:
      - targets: ['host.docker.internal:8000']
    metrics_path: /metrics
    scrape_interval: 15s

# Remote write configuration (for receiving from Alloy)
# This is automatically handled by Prometheus
EOF

echo "✅ Created prometheus.yml"

# Create Docker Compose file
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:v2.45.0
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'
      - '--web.enable-remote-write-receiver'  # Enable remote write
    networks:
      - monitoring

  alloy:
    image: grafana/alloy:v1.0.0
    container_name: alloy
    ports:
      - "12345:12345"  # Metrics receiver port
      - "3000:3000"    # Alloy UI
    volumes:
      - ./alloy-config.yaml:/etc/alloy/config.yaml
    command: 
      - "run"
      - "/etc/alloy/config.yaml"
      - "--server.http.listen-addr=0.0.0.0:3000"
    environment:
      - ALLOY_LOG_LEVEL=info
    networks:
      - monitoring
    depends_on:
      - prometheus

  grafana:
    image: grafana/grafana:10.1.0
    container_name: grafana
    ports:
      - "3001:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana_data:/var/lib/grafana
    networks:
      - monitoring
    depends_on:
      - prometheus

volumes:
  prometheus_data:
  grafana_data:

networks:
  monitoring:
    driver: bridge
EOF

echo "✅ Created docker-compose.yml"

# Create run script
cat > run.sh << 'EOF'
#!/bin/bash

echo "🚀 Starting Metrics Prototype..."

# Start Docker services
echo "📦 Starting Docker services..."
docker-compose up -d

# Wait for services to start
echo "⏳ Waiting for services to start..."
sleep 10

# Install Python dependencies
echo "🐍 Installing Python dependencies..."
pip install -r requirements.txt

# Start FastAPI service
echo "🔥 Starting FastAPI service..."
echo "📊 Access points:"
echo "   - FastAPI Service: http://localhost:8000"
echo "   - Prometheus: http://localhost:9090"
echo "   - Alloy UI: http://localhost:3000"
echo "   - Grafana: http://localhost:3001 (admin/admin)"
echo ""
echo "🔥 Starting FastAPI server..."
python main.py
EOF

chmod +x run.sh

echo "✅ Created run.sh"

# Create stop script
cat > stop.sh << 'EOF'
#!/bin/bash

echo "🛑 Stopping Metrics Prototype..."

# Stop FastAPI if running
pkill -f "python main.py" || true

# Stop Docker services
docker-compose down

echo "✅ All services stopped"
EOF

chmod +x stop.sh

echo "✅ Created stop.sh"

# Create README
cat > README.md << 'EOF'
# Grafana Stack Metrics Prototype

A complete FastAPI → Alloy → Prometheus metrics pipeline prototype.

## Architecture

```
FastAPI Service → Push Metrics → Alloy → Prometheus → Grafana
```

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

- **FastAPI** (port 8000): Pushes metrics to Alloy every 15s
- **Alloy** (port 12345): Receives metrics and forwards to Prometheus  
- **Prometheus** (port 9090): Stores metrics
- **Grafana** (port 3001): Visualizes metrics

## Testing Load

Generate some metrics:
```bash
for i in {1..10}; do curl http://localhost:8000/simulate-load; done
```

## Metrics Available

- `http_requests_total`: Total HTTP requests
- `http_request_duration_seconds`: Request duration
- `active_connections`: Active connections

## Troubleshooting

- Check Alloy logs: `docker logs alloy`
- Check Prometheus targets: http://localhost:9090/targets
- View FastAPI metrics: http://localhost:8000/metrics
EOF

echo "✅ Created README.md"

echo ""
echo "🎉 Prototype setup complete!"
echo ""
echo "📁 Project structure:"
echo "   metrics-prototype/"
echo "   ├── main.py                 # FastAPI service"
echo "   ├── requirements.txt        # Python dependencies" 
echo "   ├── docker-compose.yml      # Docker services"
echo "   ├── alloy-config.yaml       # Alloy configuration"
echo "   ├── prometheus.yml          # Prometheus configuration"
echo "   ├── run.sh                  # Start everything"
echo "   ├── stop.sh                 # Stop everything"
echo "   └── README.md               # Documentation"
echo ""
echo "🚀 To start the prototype:"
echo "   cd $PROJECT_DIR"
echo "   ./run.sh"
echo ""
echo "🔗 Access points will be:"
echo "   - FastAPI Service: http://localhost:8000"
echo "   - Prometheus: http://localhost:9090"
echo "   - Alloy UI: http://localhost:3000"
echo "   - Grafana: http://localhost:3001 (admin/admin)"
EOF