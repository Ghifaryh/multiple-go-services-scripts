#!/bin/bash

# Script to stop all Go services
# Usage: ./stop-services.sh

API_DIR="/home/gip/apps/api"

echo "🛑 Stopping Go services..."

# Stop akademik-service
# Always check for running processes, regardless of PID file
RUNNING_PIDS=$(pgrep -f "akademik-service" 2>/dev/null | grep -v "^$$$")
if [ -z "$RUNNING_PIDS" ]; then
    RUNNING_PIDS=$(pgrep -f "backend-data-master" 2>/dev/null | grep -v "^$$$")
fi

if [ -f "$API_DIR/akademik-service.pid" ]; then
    AKADEMIK_PID=$(cat "$API_DIR/akademik-service.pid")
    if ps -p $AKADEMIK_PID > /dev/null 2>&1; then
        echo "Stopping akademik-service (PID: $AKADEMIK_PID)..."
        kill $AKADEMIK_PID 2>/dev/null
        sleep 1
        # Force kill if still running
        if ps -p $AKADEMIK_PID > /dev/null 2>&1; then
            echo "Force killing akademik-service..."
            kill -9 $AKADEMIK_PID 2>/dev/null
            sleep 1
        fi
    fi
    rm -f "$API_DIR/akademik-service.pid"
fi

# Always check for any remaining processes and kill them
if [ -n "$RUNNING_PIDS" ] || pgrep -f "backend-data-master" > /dev/null 2>&1; then
    if [ -z "$RUNNING_PIDS" ]; then
        RUNNING_PIDS=$(pgrep -f "backend-data-master" 2>/dev/null | grep -v "^$$$")
    fi
    if [ -n "$RUNNING_PIDS" ]; then
        echo "Found akademik-service processes: $RUNNING_PIDS"
        echo $RUNNING_PIDS | xargs kill 2>/dev/null
        sleep 1
        # Force kill if still running
        REMAINING=$(pgrep -f "akademik-service" 2>/dev/null | grep -v "^$$$")
        if [ -z "$REMAINING" ]; then
            REMAINING=$(pgrep -f "backend-data-master" 2>/dev/null | grep -v "^$$$")
        fi
        if [ -n "$REMAINING" ]; then
            echo "Force killing remaining akademik-service processes..."
            echo $REMAINING | xargs kill -9 2>/dev/null
            sleep 1
        fi
    fi
fi

# Final check
FINAL_CHECK=$(pgrep -f "akademik-service" 2>/dev/null | grep -v "^$$$")
if [ -z "$FINAL_CHECK" ]; then
    FINAL_CHECK=$(pgrep -f "backend-data-master" 2>/dev/null | grep -v "^$$$")
fi
if [ -z "$FINAL_CHECK" ]; then
    echo "✅ akademik-service stopped"
else
    echo "❌ Failed to stop akademik-service (PIDs still running: $FINAL_CHECK)"
fi

# Stop profile-service
# Always check for running processes, regardless of PID file
RUNNING_PIDS=$(pgrep -f "profile-service" 2>/dev/null | grep -v "^$$$")

if [ -f "$API_DIR/profile-service.pid" ]; then
    PROFILE_PID=$(cat "$API_DIR/profile-service.pid")
    if ps -p $PROFILE_PID > /dev/null 2>&1; then
        echo "Stopping profile-service (PID: $PROFILE_PID)..."
        kill $PROFILE_PID 2>/dev/null
        sleep 1
        # Force kill if still running
        if ps -p $PROFILE_PID > /dev/null 2>&1; then
            echo "Force killing profile-service..."
            kill -9 $PROFILE_PID 2>/dev/null
            sleep 1
        fi
    fi
    rm -f "$API_DIR/profile-service.pid"
fi

# Always check for any remaining processes and kill them
if [ -n "$RUNNING_PIDS" ] || pgrep -f "profile-service" > /dev/null 2>&1; then
    if [ -z "$RUNNING_PIDS" ]; then
        RUNNING_PIDS=$(pgrep -f "profile-service" 2>/dev/null | grep -v "^$$$")
    fi
    if [ -n "$RUNNING_PIDS" ]; then
        echo "Found profile-service processes: $RUNNING_PIDS"
        echo $RUNNING_PIDS | xargs kill 2>/dev/null
        sleep 1
        # Force kill if still running
        REMAINING=$(pgrep -f "profile-service" 2>/dev/null | grep -v "^$$$")
        if [ -n "$REMAINING" ]; then
            echo "Force killing remaining profile-service processes..."
            echo $REMAINING | xargs kill -9 2>/dev/null
            sleep 1
        fi
    fi
fi

# Final check
FINAL_CHECK=$(pgrep -f "profile-service" 2>/dev/null | grep -v "^$$$")
if [ -z "$FINAL_CHECK" ]; then
    echo "✅ profile-service stopped"
else
    echo "❌ Failed to stop profile-service (PIDs still running: $FINAL_CHECK)"
fi

# Stop ami-service
# Always check for running processes, regardless of PID file
# Check for process listening on port 8082 first (the actual binary)
RUNNING_PIDS=""
if command -v lsof > /dev/null 2>&1; then
    RUNNING_PIDS=$(lsof -ti :8082 2>/dev/null | grep -v "^$$$")
elif command -v netstat > /dev/null 2>&1; then
    RUNNING_PIDS=$(netstat -tlnp 2>/dev/null | grep ":8082 " | awk '{print $7}' | cut -d'/' -f1 | grep -v "^$$$")
elif command -v ss > /dev/null 2>&1; then
    RUNNING_PIDS=$(ss -tlnp 2>/dev/null | grep ":8082 " | grep -oP 'pid=\K[0-9]+' | grep -v "^$$$")
fi
# Also check for go run processes
GO_RUN_PIDS=$(pgrep -f "ami-service" 2>/dev/null | grep -v "^$$$")
if [ -n "$GO_RUN_PIDS" ]; then
    if [ -n "$RUNNING_PIDS" ]; then
        RUNNING_PIDS="$RUNNING_PIDS $GO_RUN_PIDS"
    else
        RUNNING_PIDS="$GO_RUN_PIDS"
    fi
fi

if [ -f "$API_DIR/ami-service.pid" ]; then
    AMI_PID=$(cat "$API_DIR/ami-service.pid")
    if ps -p $AMI_PID > /dev/null 2>&1; then
        echo "Stopping ami-service (PID: $AMI_PID)..."
        kill $AMI_PID 2>/dev/null
        sleep 1
        # Force kill if still running
        if ps -p $AMI_PID > /dev/null 2>&1; then
            echo "Force killing ami-service..."
            kill -9 $AMI_PID 2>/dev/null
            sleep 1
        fi
    fi
    rm -f "$API_DIR/ami-service.pid"
fi

# Always check for any remaining processes and kill them
if [ -n "$RUNNING_PIDS" ]; then
    echo "Found ami-service processes: $RUNNING_PIDS"
    echo $RUNNING_PIDS | xargs kill 2>/dev/null
    sleep 1
    # Force kill if still running - check port 8082 again
    REMAINING=""
    if command -v lsof > /dev/null 2>&1; then
        REMAINING=$(lsof -ti :8082 2>/dev/null | grep -v "^$$$")
    elif command -v netstat > /dev/null 2>&1; then
        REMAINING=$(netstat -tlnp 2>/dev/null | grep ":8082 " | awk '{print $7}' | cut -d'/' -f1 | grep -v "^$$$")
    elif command -v ss > /dev/null 2>&1; then
        REMAINING=$(ss -tlnp 2>/dev/null | grep ":8082 " | grep -oP 'pid=\K[0-9]+' | grep -v "^$$$")
    fi
    GO_RUN_REMAINING=$(pgrep -f "ami-service" 2>/dev/null | grep -v "^$$$")
    if [ -n "$GO_RUN_REMAINING" ]; then
        if [ -n "$REMAINING" ]; then
            REMAINING="$REMAINING $GO_RUN_REMAINING"
        else
            REMAINING="$GO_RUN_REMAINING"
        fi
    fi
    if [ -n "$REMAINING" ]; then
        echo "Force killing remaining ami-service processes..."
        echo $REMAINING | xargs kill -9 2>/dev/null
        sleep 1
    fi
fi

# Final check - check port 8082
FINAL_CHECK=""
if command -v lsof > /dev/null 2>&1; then
    FINAL_CHECK=$(lsof -ti :8082 2>/dev/null | grep -v "^$$$")
elif command -v netstat > /dev/null 2>&1; then
    FINAL_CHECK=$(netstat -tlnp 2>/dev/null | grep ":8082 " | awk '{print $7}' | cut -d'/' -f1 | grep -v "^$$$")
elif command -v ss > /dev/null 2>&1; then
    FINAL_CHECK=$(ss -tlnp 2>/dev/null | grep ":8082 " | grep -oP 'pid=\K[0-9]+' | grep -v "^$$$")
fi
GO_RUN_FINAL=$(pgrep -f "ami-service" 2>/dev/null | grep -v "^$$$")
if [ -n "$GO_RUN_FINAL" ]; then
    if [ -n "$FINAL_CHECK" ]; then
        FINAL_CHECK="$FINAL_CHECK $GO_RUN_FINAL"
    else
        FINAL_CHECK="$GO_RUN_FINAL"
    fi
fi
if [ -z "$FINAL_CHECK" ]; then
    echo "✅ ami-service stopped"
else
    echo "❌ Failed to stop ami-service (PIDs still running: $FINAL_CHECK)"
fi

echo ""
echo "✅ All services stopped"
