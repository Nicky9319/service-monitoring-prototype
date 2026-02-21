from fastapi import FastAPI
from prometheus_client import Counter, Histogram, Gauge, CollectorRegistry, generate_latest
import time
import asyncio
from datetime import datetime

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

# Add a custom business metric for your render farm
render_jobs = Counter(
    'render_jobs_total',
    'Total render jobs processed',
    ['status'],
    registry=registry
)

# Service uptime tracking
service_start_time = time.time()
service_uptime = Gauge(
    'service_uptime_seconds',
    'Service uptime in seconds',
    registry=registry
)

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
    
    # Update uptime
    service_uptime.set(time.time() - service_start_time)
    
    print(f"📊 {request.method} {request.url.path} -> {response.status_code} ({duration:.3f}s)")
    
    return response

@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "message": "Metrics Prototype Service", 
        "timestamp": datetime.now(),
        "uptime_seconds": time.time() - service_start_time
    }

@app.get("/health")
async def health():
    """Health check endpoint"""
    return {
        "status": "healthy", 
        "timestamp": datetime.now(),
        "uptime_seconds": time.time() - service_start_time
    }

@app.get("/metrics")
async def get_metrics():
    """Expose metrics in Prometheus format for Alloy to scrape"""
    print("📈 Metrics endpoint scraped by Alloy")
    
    # Update uptime before returning metrics
    service_uptime.set(time.time() - service_start_time)
    
    return generate_latest(registry).decode('utf-8')

@app.post("/simulate-load")
async def simulate_load():
    """Simulate some processing load"""
    # Simulate work
    processing_time = 0.1
    await asyncio.sleep(processing_time)
    
    return {
        "message": "Load simulated", 
        "processing_time": f"{processing_time}s",
        "timestamp": datetime.now()
    }

@app.post("/simulate-render")
async def simulate_render():
    """Simulate a render job for your render farm"""
    import random
    
    # Simulate render job processing
    processing_time = random.uniform(0.5, 2.0)
    await asyncio.sleep(processing_time)
    
    # Randomly succeed or fail (90% success rate)
    status = "success" if random.random() > 0.1 else "failed"
    render_jobs.labels(status=status).inc()
    
    return {
        "message": f"Render job {status}",
        "processing_time": f"{processing_time:.2f}s",
        "status": status,
        "timestamp": datetime.now()
    }

@app.get("/status")
async def get_status():
    """Get service status and metrics info"""
    metrics_data = generate_latest(registry).decode('utf-8')
    metric_lines = [line for line in metrics_data.split('\n') if line and not line.startswith('#')]
    
    return {
        "status": "running",
        "timestamp": datetime.now(),
        "uptime_seconds": time.time() - service_start_time,
        "metrics_endpoint": "/metrics",
        "metric_series_count": len(metric_lines),
        "alloy_scrape_url": "http://localhost:8000/metrics"
    }

@app.get("/generate-traffic")
async def generate_traffic():
    """Generate some sample traffic for testing metrics"""
    import random
    
    # Simulate multiple requests
    results = []
    for i in range(random.randint(5, 10)):
        # Randomly call different endpoints
        endpoint = random.choice(['health', 'status', 'simulate-load'])
        start_time = time.time()
        
        if endpoint == 'simulate-load':
            await simulate_load()
        
        duration = time.time() - start_time
        results.append({
            "endpoint": endpoint,
            "duration": f"{duration:.3f}s"
        })
        
        # Small delay between requests
        await asyncio.sleep(0.05)
    
    return {
        "message": "Traffic generated",
        "requests_made": len(results),
        "details": results,
        "timestamp": datetime.now()
    }

if __name__ == "__main__":
    import uvicorn
    
    print("🚀 Starting FastAPI Metrics Service")
    print("📊 Metrics available at: http://localhost:8000/metrics")
    print("🔗 Alloy will scrape this endpoint every 15 seconds")
    print("")
    print("🧪 Test endpoints:")
    print("   GET  /              - Root endpoint")
    print("   GET  /health        - Health check")
    print("   GET  /status        - Service status")
    print("   GET  /metrics       - Prometheus metrics (scraped by Alloy)")
    print("   POST /simulate-load - Simulate processing load")
    print("   POST /simulate-render - Simulate render job")
    print("   GET  /generate-traffic - Generate sample traffic")
    print("")
    print("🎯 Pipeline: FastAPI (/metrics) ← Alloy (scrape) → Prometheus")
    
    uvicorn.run(app, host="0.0.0.0", port=8000)