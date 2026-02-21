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
