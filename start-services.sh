#!/bin/bash

# Script to start all Go services in the background
# Usage: ./start-services.sh

API_DIR="/home/gip/apps/api"
LOG_DIR="$API_DIR/logs"

# Create logs directory if it doesn't exist
mkdir -p "$LOG_DIR"

echo "🚀 Starting Go services..."

# Function to check if a service is already running
check_service_running() {
    local service_name=$1
    if [ -f "$API_DIR/${service_name}.pid" ]; then
        local pid=$(cat "$API_DIR/${service_name}.pid")
        if ps -p $pid > /dev/null 2>&1; then
            return 0  # Running
        fi
    fi
    # Also check via pgrep
    if pgrep -f "$service_name" > /dev/null 2>&1; then
        return 0  # Running
    fi
    # Special case: akademik-service runs as "backend-data-master"
    if [ "$service_name" = "akademik-service" ]; then
        if pgrep -f "backend-data-master" > /dev/null 2>&1; then
            return 0  # Running
        fi
        # Also check if port 8080 is in use (akademik-service default port)
        if command -v lsof > /dev/null 2>&1; then
            if lsof -i :8080 > /dev/null 2>&1; then
                return 0  # Port in use, likely the service
            fi
        elif command -v netstat > /dev/null 2>&1; then
            if netstat -tln 2>/dev/null | grep -q ":8080 "; then
                return 0  # Port in use
            fi
        elif command -v ss > /dev/null 2>&1; then
            if ss -tln 2>/dev/null | grep -q ":8080 "; then
                return 0  # Port in use
            fi
        fi
    fi
    # Check if port 8082 is in use (ami-service default port)
    if [ "$service_name" = "ami-service" ]; then
        if command -v lsof > /dev/null 2>&1; then
            if lsof -i :8082 > /dev/null 2>&1; then
                return 0  # Port in use, likely the service
            fi
        elif command -v netstat > /dev/null 2>&1; then
            if netstat -tln 2>/dev/null | grep -q ":8082 "; then
                return 0  # Port in use
            fi
        elif command -v ss > /dev/null 2>&1; then
            if ss -tln 2>/dev/null | grep -q ":8082 "; then
                return 0  # Port in use
            fi
        fi
    fi
    return 1  # Not running
}

# Function to start a service
start_service() {
    local service_name=$1
    local service_dir="$API_DIR/$service_name"

    # Check if already running
    if check_service_running "$service_name"; then
        # Try to find the PID
        local existing_pid=$(pgrep -f "$service_name" 2>/dev/null | head -1)
        if [ -z "$existing_pid" ] && [ "$service_name" = "akademik-service" ]; then
            existing_pid=$(pgrep -f "backend-data-master" 2>/dev/null | head -1)
        fi
        if [ -z "$existing_pid" ] && [ -f "$API_DIR/${service_name}.pid" ]; then
            existing_pid=$(cat "$API_DIR/${service_name}.pid" 2>/dev/null)
        fi
        if [ -n "$existing_pid" ]; then
            echo "⚠️  $service_name is already running (PID: $existing_pid), skipping..."
        else
            echo "⚠️  $service_name appears to be running (port conflict or process detected), skipping..."
        fi
        return 0  # Already running is OK, not an error
    fi

    # Check if directory exists
    if [ ! -d "$service_dir" ]; then
        echo "❌ Error: Directory $service_dir does not exist"
        return 1
    fi

    # Change to service directory
    if ! cd "$service_dir"; then
        echo "❌ Error: Failed to change to directory $service_dir"
        return 1
    fi

    # Remove stale PID file if exists
    rm -f "$API_DIR/${service_name}.pid"

    echo "Starting $service_name..."

    # Determine the correct go run command based on service structure
    local go_run_cmd="."
    if [ "$service_name" = "ami-service" ] && [ -f "cmd/server/main.go" ]; then
        go_run_cmd="./cmd/server"
    fi

    # Start the service
    nohup go run $go_run_cmd > "$LOG_DIR/${service_name}.log" 2>&1 &
    local go_pid=$!

    # Wait for go run to compile and start the binary (go run exits after starting)
    sleep 3

    # Find the actual service binary process
    # For akademik-service, look for backend-data-master
    # For profile-service, look for profile-service
    # For ami-service, look for process listening on port 8082
    local actual_pid=""
    if [ "$service_name" = "akademik-service" ]; then
        # Wait a bit more for the binary to start
        sleep 1
        actual_pid=$(pgrep -f "backend-data-master" 2>/dev/null | grep -v "^$$$" | head -1)
    elif [ "$service_name" = "ami-service" ]; then
        # Wait a bit more for the binary to start
        sleep 1
        # Check for process listening on port 8082
        if command -v lsof > /dev/null 2>&1; then
            actual_pid=$(lsof -ti :8082 2>/dev/null | head -1)
        elif command -v netstat > /dev/null 2>&1; then
            actual_pid=$(netstat -tlnp 2>/dev/null | grep ":8082 " | awk '{print $7}' | cut -d'/' -f1 | head -1)
        elif command -v ss > /dev/null 2>&1; then
            actual_pid=$(ss -tlnp 2>/dev/null | grep ":8082 " | grep -oP 'pid=\K[0-9]+' | head -1)
        fi
        # Fallback to pgrep if port check didn't work
        if [ -z "$actual_pid" ]; then
            actual_pid=$(pgrep -f "ami-service" 2>/dev/null | grep -v "^$$$" | head -1)
        fi
    else
        actual_pid=$(pgrep -f "$service_name" 2>/dev/null | grep -v "^$$$" | head -1)
    fi

    # If we couldn't find the actual process, check if go run is still running
    # (it might still be compiling)
    if [ -z "$actual_pid" ]; then
        if ps -p $go_pid > /dev/null 2>&1; then
            # go run is still running, wait a bit more
            sleep 2
            if [ "$service_name" = "akademik-service" ]; then
                actual_pid=$(pgrep -f "backend-data-master" 2>/dev/null | grep -v "^$$$" | head -1)
            elif [ "$service_name" = "ami-service" ]; then
                # Check for process listening on port 8082
                if command -v lsof > /dev/null 2>&1; then
                    actual_pid=$(lsof -ti :8082 2>/dev/null | head -1)
                elif command -v netstat > /dev/null 2>&1; then
                    actual_pid=$(netstat -tlnp 2>/dev/null | grep ":8082 " | awk '{print $7}' | cut -d'/' -f1 | head -1)
                elif command -v ss > /dev/null 2>&1; then
                    actual_pid=$(ss -tlnp 2>/dev/null | grep ":8082 " | grep -oP 'pid=\K[0-9]+' | head -1)
                fi
                # Fallback to pgrep if port check didn't work
                if [ -z "$actual_pid" ]; then
                    actual_pid=$(pgrep -f "ami-service" 2>/dev/null | grep -v "^$$$" | head -1)
                fi
            else
                actual_pid=$(pgrep -f "$service_name" 2>/dev/null | grep -v "^$$$" | head -1)
            fi
        fi
    fi

    # Check if the service actually started
    if [ -z "$actual_pid" ]; then
        echo "❌ Error: $service_name failed to start (binary process not found)"
        echo "   Check logs: $LOG_DIR/${service_name}.log"
        # Check for common errors in the log
        if [ -f "$LOG_DIR/${service_name}.log" ]; then
            if grep -q "address already in use" "$LOG_DIR/${service_name}.log" 2>/dev/null; then
                echo "   💡 Port conflict detected - another process is using the port"
                echo "   💡 Try: ./stop-services.sh to stop all services first"
            fi
        fi
        return 1
    fi

    # Verify the process is actually running
    if ! ps -p $actual_pid > /dev/null 2>&1; then
        echo "❌ Error: $service_name process died immediately (PID: $actual_pid)"
        echo "   Check logs: $LOG_DIR/${service_name}.log"
        return 1
    fi

    # Save the actual binary PID (not the go run PID)
    echo $actual_pid > "$API_DIR/${service_name}.pid"
    echo "✅ $service_name started (PID: $actual_pid)"
    return 0
}

# Start akademik-service
start_service "akademik-service"
AKADEMIK_STARTED=$?

# Wait a moment before starting the next service
sleep 2

# Start profile-service
start_service "profile-service"
PROFILE_STARTED=$?

# Wait a moment before starting the next service
sleep 2

# Start ami-service
start_service "ami-service"
AMI_STARTED=$?

echo ""
echo "📋 Service Status:"
if [ $AKADEMIK_STARTED -eq 0 ]; then
    # Try to get PID from file first, then from pgrep (check both patterns)
    AKADEMIK_PID=$(cat "$API_DIR/akademik-service.pid" 2>/dev/null)
    if [ -z "$AKADEMIK_PID" ]; then
        AKADEMIK_PID=$(pgrep -f "akademik-service" 2>/dev/null | head -1)
    fi
    if [ -z "$AKADEMIK_PID" ]; then
        AKADEMIK_PID=$(pgrep -f "backend-data-master" 2>/dev/null | head -1)
    fi
    if [ -n "$AKADEMIK_PID" ]; then
        echo "  akademik-service: ✅ RUNNING (PID: $AKADEMIK_PID)"
    else
        echo "  akademik-service: ✅ STARTED (PID file not found)"
    fi
else
    echo "  akademik-service: ❌ FAILED TO START"
fi

if [ $PROFILE_STARTED -eq 0 ]; then
    # Try to get PID from file first, then from pgrep
    PROFILE_PID=$(cat "$API_DIR/profile-service.pid" 2>/dev/null)
    if [ -z "$PROFILE_PID" ]; then
        PROFILE_PID=$(pgrep -f "profile-service" 2>/dev/null | head -1)
    fi
    if [ -n "$PROFILE_PID" ]; then
        echo "  profile-service:  ✅ RUNNING (PID: $PROFILE_PID)"
    else
        echo "  profile-service:  ✅ STARTED (PID file not found)"
    fi
else
    echo "  profile-service:  ❌ FAILED TO START"
fi

if [ $AMI_STARTED -eq 0 ]; then
    # Try to get PID from file first, then check port 8082, then pgrep
    AMI_PID=$(cat "$API_DIR/ami-service.pid" 2>/dev/null)
    if [ -z "$AMI_PID" ]; then
        # Check for process listening on port 8082
        if command -v lsof > /dev/null 2>&1; then
            AMI_PID=$(lsof -ti :8082 2>/dev/null | head -1)
        elif command -v netstat > /dev/null 2>&1; then
            AMI_PID=$(netstat -tlnp 2>/dev/null | grep ":8082 " | awk '{print $7}' | cut -d'/' -f1 | head -1)
        elif command -v ss > /dev/null 2>&1; then
            AMI_PID=$(ss -tlnp 2>/dev/null | grep ":8082 " | grep -oP 'pid=\K[0-9]+' | head -1)
        fi
    fi
    if [ -z "$AMI_PID" ]; then
        AMI_PID=$(pgrep -f "ami-service" 2>/dev/null | head -1)
    fi
    if [ -n "$AMI_PID" ]; then
        echo "  ami-service:      ✅ RUNNING (PID: $AMI_PID)"
    else
        echo "  ami-service:      ✅ STARTED (PID file not found)"
    fi
else
    echo "  ami-service:      ❌ FAILED TO START"
fi

echo ""
echo "Log files:"
echo "  akademik-service: $LOG_DIR/akademik-service.log"
echo "  profile-service:  $LOG_DIR/profile-service.log"
echo "  ami-service:  $LOG_DIR/ami-service.log"
echo ""
echo "To view logs:"
echo "  tail -f $LOG_DIR/akademik-service.log"
echo "  tail -f $LOG_DIR/profile-service.log"
echo "  tail -f $LOG_DIR/ami-service.log"
echo ""
echo "To check status:"
echo "  ./status-services.sh"
echo ""
echo "To stop services:"
echo "  ./stop-services.sh"

# Exit with error if any service failed to start
if [ $AKADEMIK_STARTED -ne 0 ] || [ $PROFILE_STARTED -ne 0 ] || [ $AMI_STARTED -ne 0 ]; then
    exit 1
fi
