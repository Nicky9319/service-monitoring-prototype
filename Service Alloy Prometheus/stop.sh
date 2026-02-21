#!/bin/bash

echo "🛑 Stopping Metrics Prototype..."

# Stop FastAPI if running
pkill -f "python main.py" || true

# Stop Docker services
docker-compose down

echo "✅ All services stopped"
