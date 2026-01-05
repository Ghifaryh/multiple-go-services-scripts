# Service Management Scripts

A collection of bash scripts to manage multiple Go microservices in a unified way. These scripts handle starting, stopping, and monitoring services with proper PID tracking, logging, and process detection.

## Table of Contents

- [Quick Start](#quick-start)
- [Overview](#overview)
- [How It Works](#how-it-works)
  - [start-services.sh](#start-servicessh)
  - [status-services.sh](#status-servicessh)
  - [stop-services.sh](#stop-servicessh)
- [Adding a New Service](#adding-a-new-service)
- [Architecture & Design Decisions](#architecture--design-decisions)
- [Troubleshooting](#troubleshooting)
- [Manual Management](#manual-management)

## Quick Start

### Start all services:
```bash
cd /home/gip/apps/api
./start-services.sh
```

### Stop all services:
```bash
cd /home/gip/apps/api
./stop-services.sh
```

### Check status:
```bash
cd /home/gip/apps/api
./status-services.sh
```

## Overview

These scripts provide a unified way to manage multiple Go microservices:

- **start-services.sh**: Starts all services in the background, tracks PIDs, and logs output
- **status-services.sh**: Checks the running status of all services
- **stop-services.sh**: Gracefully stops all services with fallback to force kill

### Current Services

- `akademik-service` - Port 8080 (runs as `backend-data-master` binary)
- `profile-service` - Standard Go service
- `ami-service` - Port 8082 (runs from `cmd/server/main.go`)

## How It Works

### start-services.sh

This script orchestrates the startup of all services with the following workflow:

#### 1. **Service Detection** (`check_service_running()`)
   - Checks if a PID file exists and if the process is still running
   - Uses `pgrep` to find processes matching the service name
   - **Special handling**: Some services have unique binary names or require port checking:
     - `akademik-service`: Checks for `backend-data-master` process and port 8080
     - `ami-service`: Checks port 8082 (binary runs as `server`)
   - Prevents duplicate service instances

#### 2. **Service Startup** (`start_service()`)
   - Validates service directory exists
   - Changes to service directory
   - Removes stale PID files
   - Starts service with `nohup go run <path> > logs/<service>.log 2>&1 &`
   - **Special handling**: Services with `cmd/server/main.go` use `go run ./cmd/server`
   - Waits for compilation and startup (3-5 seconds)
   - Finds the actual binary process PID (not the `go run` PID)
   - Saves PID to `<service-name>.pid` file
   - Verifies the process is actually running

#### 3. **Process Detection**
   The script uses multiple methods to find the actual service process:
   - **Standard services**: `pgrep -f "<service-name>"`
   - **akademik-service**: `pgrep -f "backend-data-master"`
   - **ami-service**: Checks port 8082 using `lsof`, `netstat`, or `ss`

#### 4. **Status Summary**
   After starting all services, displays a summary with:
   - Service status (RUNNING/FAILED)
   - Process IDs
   - Log file locations
   - Helpful commands

### status-services.sh

This script checks the status of all services:

#### Process Detection Strategy
1. **PID File Check**: If a PID file exists, verify the process is running
2. **Fallback Detection**: If no PID file or stale PID:
   - Use `pgrep` to find processes by name
   - For special services, check alternative patterns:
     - `akademik-service`: Check `backend-data-master` process
     - `ami-service`: Check port 8082
3. **Port Checking**: For services with known ports, verify the port is in use

#### Output States
- ✅ **RUNNING**: Service is active (with PID)
- ⚠️ **RUNNING (no PID file)**: Service is running but PID file is missing
- ❌ **NOT RUNNING**: Service is not active

### stop-services.sh

This script stops all services gracefully:

#### Stopping Strategy
1. **PID File Method**: If PID file exists, kill the process using the saved PID
2. **Process Search**: Find all processes matching the service name
3. **Special Handling**:
   - `akademik-service`: Also searches for `backend-data-master`
   - `ami-service`: Finds process by port 8082
4. **Graceful Shutdown**: Send SIGTERM first, wait 1 second
5. **Force Kill**: If still running, send SIGKILL
6. **Cleanup**: Remove PID files
7. **Verification**: Final check to confirm all processes are stopped

## Adding a New Service

Follow these steps to add a new service to the management scripts:

### Step 1: Determine Service Characteristics

Before adding, identify:
- **Service name**: e.g., `my-new-service`
- **Port**: What port does it run on? (if applicable)
- **Binary name**: Does it run with a different binary name? (check with `ps aux | grep <service>`)
- **Directory structure**: Is `main.go` in root or `cmd/server/main.go`?

### Step 2: Update start-services.sh

#### 2.1 Add port checking (if applicable)
In the `check_service_running()` function, add port checking:

```bash
# Check if port <PORT> is in use (<service-name> default port)
if [ "$service_name" = "<service-name>" ]; then
    if command -v lsof > /dev/null 2>&1; then
        if lsof -i :<PORT> > /dev/null 2>&1; then
            return 0  # Port in use, likely the service
        fi
    elif command -v netstat > /dev/null 2>&1; then
        if netstat -tln 2>/dev/null | grep -q ":<PORT> "; then
            return 0  # Port in use
        fi
    elif command -v ss > /dev/null 2>&1; then
        if ss -tln 2>/dev/null | grep -q ":<PORT> "; then
            return 0  # Port in use
        fi
    fi
fi
```

#### 2.2 Add process detection logic
In the `start_service()` function, add detection for the actual binary:

```bash
elif [ "$service_name" = "<service-name>" ]; then
    # Wait a bit more for the binary to start
    sleep 1
    # Check for process listening on port <PORT>
    if command -v lsof > /dev/null 2>&1; then
        actual_pid=$(lsof -ti :<PORT> 2>/dev/null | head -1)
    elif command -v netstat > /dev/null 2>&1; then
        actual_pid=$(netstat -tlnp 2>/dev/null | grep ":<PORT> " | awk '{print $7}' | cut -d'/' -f1 | head -1)
    elif command -v ss > /dev/null 2>&1; then
        actual_pid=$(ss -tlnp 2>/dev/null | grep ":<PORT> " | grep -oP 'pid=\K[0-9]+' | head -1)
    fi
    # Fallback to pgrep if port check didn't work
    if [ -z "$actual_pid" ]; then
        actual_pid=$(pgrep -f "<service-name>" 2>/dev/null | grep -v "^$$$" | head -1)
    fi
```

Also update the retry logic in the same function.

#### 2.3 Add service startup call
After the existing service calls, add:

```bash
# Wait a moment before starting the next service
sleep 2

# Start <service-name>
start_service "<service-name>"
<UPPERCASE_SERVICE>_STARTED=$?
```

#### 2.4 Add status display
In the status summary section, add:

```bash
if [ $<UPPERCASE_SERVICE>_STARTED -eq 0 ]; then
    # Try to get PID from file first, then check port <PORT>, then pgrep
    <SERVICE>_PID=$(cat "$API_DIR/<service-name>.pid" 2>/dev/null)
    if [ -z "$<SERVICE>_PID" ]; then
        # Check for process listening on port <PORT>
        if command -v lsof > /dev/null 2>&1; then
            <SERVICE>_PID=$(lsof -ti :<PORT> 2>/dev/null | head -1)
        elif command -v netstat > /dev/null 2>&1; then
            <SERVICE>_PID=$(netstat -tlnp 2>/dev/null | grep ":<PORT> " | awk '{print $7}' | cut -d'/' -f1 | head -1)
        elif command -v ss > /dev/null 2>&1; then
            <SERVICE>_PID=$(ss -tlnp 2>/dev/null | grep ":<PORT> " | grep -oP 'pid=\K[0-9]+' | head -1)
        fi
    fi
    if [ -z "$<SERVICE>_PID" ]; then
        <SERVICE>_PID=$(pgrep -f "<service-name>" 2>/dev/null | head -1)
    fi
    if [ -n "$<SERVICE>_PID" ]; then
        echo "  <service-name>:      ✅ RUNNING (PID: $<SERVICE>_PID)"
    else
        echo "  <service-name>:      ✅ STARTED (PID file not found)"
    fi
else
    echo "  <service-name>:      ❌ FAILED TO START"
fi
```

#### 2.5 Update exit condition
Add the new service to the exit check:

```bash
if [ $AKADEMIK_STARTED -ne 0 ] || [ $PROFILE_STARTED -ne 0 ] || [ $AMI_STARTED -ne 0 ] || [ $<UPPERCASE_SERVICE>_STARTED -ne 0 ]; then
    exit 1
fi
```

#### 2.6 Update log file references
Add log file path to the help text at the end.

### Step 3: Update status-services.sh

Add a status check section (similar to existing services):

```bash
# Check <service-name>
if [ -f "$API_DIR/<service-name>.pid" ]; then
    <SERVICE>_PID=$(cat "$API_DIR/<service-name>.pid")
    if ps -p $<SERVICE>_PID > /dev/null 2>&1; then
        echo "✅ <service-name>:      RUNNING (PID: $<SERVICE>_PID)"
    else
        echo "❌ <service-name>:      NOT RUNNING (stale PID file)"
        # Check if it's actually running without PID file
        RUNNING_PID=$(pgrep -f "<service-name>" 2>/dev/null | grep -v "^$$$" | head -1)
        # Add port check if applicable
        if [ -z "$RUNNING_PID" ] && [ -n "<PORT>" ]; then
            if command -v lsof > /dev/null 2>&1; then
                RUNNING_PID=$(lsof -ti :<PORT> 2>/dev/null | head -1)
            elif command -v netstat > /dev/null 2>&1; then
                RUNNING_PID=$(netstat -tlnp 2>/dev/null | grep ":<PORT> " | awk '{print $7}' | cut -d'/' -f1 | head -1)
            elif command -v ss > /dev/null 2>&1; then
                RUNNING_PID=$(ss -tlnp 2>/dev/null | grep ":<PORT> " | grep -oP 'pid=\K[0-9]+' | head -1)
            fi
        fi
        if [ -n "$RUNNING_PID" ] && ps -p $RUNNING_PID > /dev/null 2>&1; then
            echo "⚠️  <service-name>:      RUNNING (PID: $RUNNING_PID, no PID file)"
        fi
    fi
else
    # Similar logic for when PID file doesn't exist
    RUNNING_PID=$(pgrep -f "<service-name>" 2>/dev/null | grep -v "^$$$" | head -1)
    if [ -z "$RUNNING_PID" ] && [ -n "<PORT>" ]; then
        # Port check logic here
    fi
    if [ -n "$RUNNING_PID" ] && ps -p $RUNNING_PID > /dev/null 2>&1; then
        echo "⚠️  <service-name>:      RUNNING (PID: $RUNNING_PID, no PID file)"
    else
        echo "❌ <service-name>:      NOT RUNNING"
    fi
fi
```

Add log file reference at the end.

### Step 4: Update stop-services.sh

Add a stop section:

```bash
# Stop <service-name>
# Always check for running processes, regardless of PID file
RUNNING_PIDS=""
if [ -n "<PORT>" ]; then
    # Check for process listening on port <PORT>
    if command -v lsof > /dev/null 2>&1; then
        RUNNING_PIDS=$(lsof -ti :<PORT> 2>/dev/null | grep -v "^$$$")
    elif command -v netstat > /dev/null 2>&1; then
        RUNNING_PIDS=$(netstat -tlnp 2>/dev/null | grep ":<PORT> " | awk '{print $7}' | cut -d'/' -f1 | grep -v "^$$$")
    elif command -v ss > /dev/null 2>&1; then
        RUNNING_PIDS=$(ss -tlnp 2>/dev/null | grep ":<PORT> " | grep -oP 'pid=\K[0-9]+' | grep -v "^$$$")
    fi
fi
# Also check for go run processes
GO_RUN_PIDS=$(pgrep -f "<service-name>" 2>/dev/null | grep -v "^$$$")
if [ -n "$GO_RUN_PIDS" ]; then
    if [ -n "$RUNNING_PIDS" ]; then
        RUNNING_PIDS="$RUNNING_PIDS $GO_RUN_PIDS"
    else
        RUNNING_PIDS="$GO_RUN_PIDS"
    fi
fi

if [ -f "$API_DIR/<service-name>.pid" ]; then
    <SERVICE>_PID=$(cat "$API_DIR/<service-name>.pid")
    if ps -p $<SERVICE>_PID > /dev/null 2>&1; then
        echo "Stopping <service-name> (PID: $<SERVICE>_PID)..."
        kill $<SERVICE>_PID 2>/dev/null
        sleep 1
        # Force kill if still running
        if ps -p $<SERVICE>_PID > /dev/null 2>&1; then
            echo "Force killing <service-name>..."
            kill -9 $<SERVICE>_PID 2>/dev/null
            sleep 1
        fi
    fi
    rm -f "$API_DIR/<service-name>.pid"
fi

# Always check for any remaining processes and kill them
if [ -n "$RUNNING_PIDS" ]; then
    echo "Found <service-name> processes: $RUNNING_PIDS"
    echo $RUNNING_PIDS | xargs kill 2>/dev/null
    sleep 1
    # Force kill if still running
    REMAINING=""
    if [ -n "<PORT>" ]; then
        # Port check logic here
    fi
    GO_RUN_REMAINING=$(pgrep -f "<service-name>" 2>/dev/null | grep -v "^$$$")
    if [ -n "$GO_RUN_REMAINING" ]; then
        if [ -n "$REMAINING" ]; then
            REMAINING="$REMAINING $GO_RUN_REMAINING"
        else
            REMAINING="$GO_RUN_REMAINING"
        fi
    fi
    if [ -n "$REMAINING" ]; then
        echo "Force killing remaining <service-name> processes..."
        echo $REMAINING | xargs kill -9 2>/dev/null
        sleep 1
    fi
fi

# Final check
FINAL_CHECK=""
if [ -n "<PORT>" ]; then
    # Port check logic here
fi
GO_RUN_FINAL=$(pgrep -f "<service-name>" 2>/dev/null | grep -v "^$$$")
if [ -n "$GO_RUN_FINAL" ]; then
    if [ -n "$FINAL_CHECK" ]; then
        FINAL_CHECK="$FINAL_CHECK $GO_RUN_FINAL"
    else
        FINAL_CHECK="$GO_RUN_FINAL"
    fi
fi
if [ -z "$FINAL_CHECK" ]; then
    echo "✅ <service-name> stopped"
else
    echo "❌ Failed to stop <service-name> (PIDs still running: $FINAL_CHECK)"
fi
```

### Step 5: Handle Special Directory Structures

If your service has `main.go` in `cmd/server/main.go` (like `ami-service`), update the `start_service()` function:

```bash
# Determine the correct go run command based on service structure
local go_run_cmd="."
if [ "$service_name" = "<service-name>" ] && [ -f "cmd/server/main.go" ]; then
    go_run_cmd="./cmd/server"
fi
```

### Step 6: Test

1. Test starting: `./start-services.sh`
2. Test status: `./status-services.sh`
3. Test stopping: `./stop-services.sh`
4. Verify logs: `tail -f logs/<service-name>.log`

## Architecture & Design Decisions

### Why Multiple Detection Methods?

Services can be detected in different ways:
- **PID files**: Most reliable when scripts manage the service
- **Process name**: Works for standard Go services
- **Port checking**: Essential for services with unique binary names or when PID files are missing
- **Combination**: Provides redundancy and reliability

### Why Port Checking?

Some services compile to binaries with different names than their directory:
- `akademik-service` → `backend-data-master`
- `ami-service` → `server` (from `cmd/server/main.go`)

Port checking ensures we can always find the running service.

### Why Wait Times?

- **3 seconds**: Initial wait for `go run` to compile
- **1-2 seconds**: Additional wait for binary to start listening
- **1 second**: Between service starts (prevents resource contention)

### PID File Management

- **Location**: `<API_DIR>/<service-name>.pid`
- **Content**: Actual binary process PID (not `go run` PID)
- **Cleanup**: Removed on stop, checked on start
- **Stale handling**: Scripts detect and handle stale PID files

## Troubleshooting

### Service Shows as "NOT RUNNING" but Actually Running

**Problem**: Process detection isn't finding the service.

**Solutions**:
1. Check what the actual process name is: `ps aux | grep <service>`
2. Verify the port: `lsof -i :<PORT>` or `netstat -tln | grep <PORT>`
3. Update the detection logic in all three scripts to match your service's actual process name/port

### Service Fails to Start

**Check logs**:
```bash
tail -f logs/<service-name>.log
```

**Common issues**:
- Port already in use: Another process is using the port
- Compilation errors: Check Go build errors in logs
- Missing dependencies: Run `go mod download` in service directory
- Configuration errors: Check `.env` files and config

### PID File Not Created

**Causes**:
- Service dies immediately after start
- Process detection logic can't find the binary
- Timing issue (service takes longer to start)

**Solutions**:
- Check logs for errors
- Increase wait times in `start_service()`
- Verify process detection logic matches your service

### Can't Stop Service

**Solutions**:
1. Check if process exists: `ps aux | grep <service>`
2. Manual kill: `kill -9 <PID>`
3. Check for zombie processes: `ps aux | grep defunct`
4. Verify stop script logic matches your service's process name

## Manual Management

### Start a Service Manually

```bash
cd /home/gip/apps/api/<service-name>
nohup go run . > ../logs/<service-name>.log 2>&1 &
echo $! > ../<service-name>.pid
```

For services with `cmd/server/main.go`:
```bash
cd /home/gip/apps/api/<service-name>
nohup go run ./cmd/server > ../logs/<service-name>.log 2>&1 &
# Find actual PID after it starts
sleep 3
PID=$(lsof -ti :<PORT> 2>/dev/null || pgrep -f "<service-name>" | head -1)
echo $PID > ../<service-name>.pid
```

### Stop a Service Manually

```bash
# Using PID file
kill $(cat /home/gip/apps/api/<service-name>.pid)

# Using process name
pkill -f "<service-name>"

# Using port (if known)
kill $(lsof -ti :<PORT>)
```

### View Logs

```bash
# Real-time
tail -f logs/<service-name>.log

# Last 100 lines
tail -n 100 logs/<service-name>.log

# Search logs
grep "ERROR" logs/<service-name>.log
```

## Logs

Logs are saved to: `logs/<service-name>.log`

Current services:
- `logs/akademik-service.log`
- `logs/profile-service.log`
- `logs/ami-service.log`

## Requirements

- Bash 4.0+
- Go 1.16+
- One of: `lsof`, `netstat`, or `ss` (for port checking)
- `pgrep` (usually pre-installed on Linux)

## License

[Add your license here]

## Contributing

When adding a new service, please:
1. Follow the existing patterns in the scripts
2. Test all three scripts (start, status, stop)
3. Update this documentation
4. Ensure port checking works correctly
5. Handle edge cases (stale PIDs, missing processes, etc.)
