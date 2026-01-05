#!/bin/bash

# Script to check status of all Go services
# Usage: ./status-services.sh

API_DIR="/home/gip/apps/api"

echo "📊 Service Status:"
echo ""

# Check akademik-service
if [ -f "$API_DIR/akademik-service.pid" ]; then
    AKADEMIK_PID=$(cat "$API_DIR/akademik-service.pid")
    if ps -p $AKADEMIK_PID > /dev/null 2>&1; then
        echo "✅ akademik-service: RUNNING (PID: $AKADEMIK_PID)"
    else
        echo "❌ akademik-service: NOT RUNNING (stale PID file)"
        # Check if it's actually running without PID file (check both patterns)
        RUNNING_PID=$(pgrep -f "akademik-service" 2>/dev/null | grep -v "^$$$" | head -1)
        if [ -z "$RUNNING_PID" ]; then
            RUNNING_PID=$(pgrep -f "backend-data-master" 2>/dev/null | grep -v "^$$$" | head -1)
        fi
        if [ -n "$RUNNING_PID" ] && ps -p $RUNNING_PID > /dev/null 2>&1; then
            echo "⚠️  akademik-service: RUNNING (PID: $RUNNING_PID, no PID file)"
        fi
    fi
else
    # Check both patterns: "akademik-service" and "backend-data-master"
    RUNNING_PID=$(pgrep -f "akademik-service" 2>/dev/null | grep -v "^$$$" | head -1)
    if [ -z "$RUNNING_PID" ]; then
        RUNNING_PID=$(pgrep -f "backend-data-master" 2>/dev/null | grep -v "^$$$" | head -1)
    fi
    if [ -n "$RUNNING_PID" ] && ps -p $RUNNING_PID > /dev/null 2>&1; then
        echo "⚠️  akademik-service: RUNNING (PID: $RUNNING_PID, no PID file)"
    else
        echo "❌ akademik-service: NOT RUNNING"
    fi
fi

# Check profile-service
if [ -f "$API_DIR/profile-service.pid" ]; then
    PROFILE_PID=$(cat "$API_DIR/profile-service.pid")
    if ps -p $PROFILE_PID > /dev/null 2>&1; then
        echo "✅ profile-service:  RUNNING (PID: $PROFILE_PID)"
    else
        echo "❌ profile-service:  NOT RUNNING (stale PID file)"
        # Check if it's actually running without PID file
        RUNNING_PID=$(pgrep -f "profile-service" 2>/dev/null | grep -v "^$$$" | head -1)
        if [ -n "$RUNNING_PID" ] && ps -p $RUNNING_PID > /dev/null 2>&1; then
            echo "⚠️  profile-service:  RUNNING (PID: $RUNNING_PID, no PID file)"
        fi
    fi
else
    RUNNING_PID=$(pgrep -f "profile-service" 2>/dev/null | grep -v "^$$$" | head -1)
    if [ -n "$RUNNING_PID" ] && ps -p $RUNNING_PID > /dev/null 2>&1; then
        echo "⚠️  profile-service:  RUNNING (PID: $RUNNING_PID, no PID file)"
    else
        echo "❌ profile-service:  NOT RUNNING"
    fi
fi

# Check ami-service
if [ -f "$API_DIR/ami-service.pid" ]; then
    AMI_PID=$(cat "$API_DIR/ami-service.pid")
    if ps -p $AMI_PID > /dev/null 2>&1; then
        echo "✅ ami-service:      RUNNING (PID: $AMI_PID)"
    else
        echo "❌ ami-service:      NOT RUNNING (stale PID file)"
        # Check if it's actually running without PID file (check multiple patterns)
        RUNNING_PID=$(pgrep -f "ami-service" 2>/dev/null | grep -v "^$$$" | head -1)
        if [ -z "$RUNNING_PID" ]; then
            # Check for "server" process listening on port 8082
            if command -v lsof > /dev/null 2>&1; then
                RUNNING_PID=$(lsof -ti :8082 2>/dev/null | head -1)
            elif command -v netstat > /dev/null 2>&1; then
                RUNNING_PID=$(netstat -tlnp 2>/dev/null | grep ":8082 " | awk '{print $7}' | cut -d'/' -f1 | head -1)
            elif command -v ss > /dev/null 2>&1; then
                RUNNING_PID=$(ss -tlnp 2>/dev/null | grep ":8082 " | grep -oP 'pid=\K[0-9]+' | head -1)
            fi
        fi
        if [ -n "$RUNNING_PID" ] && ps -p $RUNNING_PID > /dev/null 2>&1; then
            echo "⚠️  ami-service:      RUNNING (PID: $RUNNING_PID, no PID file)"
        fi
    fi
else
    # Check multiple patterns: "ami-service", port 8082, or "cmd/server" in ami-service context
    RUNNING_PID=$(pgrep -f "ami-service" 2>/dev/null | grep -v "^$$$" | head -1)
    if [ -z "$RUNNING_PID" ]; then
        # Check for process listening on port 8082
        if command -v lsof > /dev/null 2>&1; then
            RUNNING_PID=$(lsof -ti :8082 2>/dev/null | head -1)
        elif command -v netstat > /dev/null 2>&1; then
            RUNNING_PID=$(netstat -tlnp 2>/dev/null | grep ":8082 " | awk '{print $7}' | cut -d'/' -f1 | head -1)
        elif command -v ss > /dev/null 2>&1; then
            RUNNING_PID=$(ss -tlnp 2>/dev/null | grep ":8082 " | grep -oP 'pid=\K[0-9]+' | head -1)
        fi
    fi
    if [ -n "$RUNNING_PID" ] && ps -p $RUNNING_PID > /dev/null 2>&1; then
        echo "⚠️  ami-service:      RUNNING (PID: $RUNNING_PID, no PID file)"
    else
        echo "❌ ami-service:      NOT RUNNING"
    fi
fi

echo ""
echo "Log files:"
echo "  akademik-service: $API_DIR/logs/akademik-service.log"
echo "  profile-service:  $API_DIR/logs/profile-service.log"
echo "  ami-service:      $API_DIR/logs/ami-service.log"
