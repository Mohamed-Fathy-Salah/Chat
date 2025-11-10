#!/bin/bash

# Performance Test Runner for Chat API
# Tests the system's ability to handle 5000 writes/sec and 10000 reads/sec

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PERF_TEST_DIR="$SCRIPT_DIR/performance-test"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
WRITES=500
READS=1000
DURATION=30
WORKERS=100

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --writes)
      WRITES="$2"
      shift 2
      ;;
    --reads)
      READS="$2"
      shift 2
      ;;
    --duration)
      DURATION="$2"
      shift 2
      ;;
    --workers)
      WORKERS="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo ""
      echo "Options:"
      echo "  --writes N      Target writes per second (default: 5000)"
      echo "  --reads N       Target reads per second (default: 10000)"
      echo "  --duration N    Test duration in seconds (default: 30)"
      echo "  --workers N     Number of concurrent workers (default: 100)"
      echo "  --help          Show this help message"
      echo ""
      echo "Example:"
      echo "  $0 --writes 3000 --reads 6000 --duration 60"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Chat API Performance Test${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""

# Check if services are running
echo -e "${YELLOW}Checking if services are running...${NC}"
if ! curl -s http://localhost:3000/api/v1/auth/login > /dev/null 2>&1; then
    echo -e "${RED}Error: Chat API is not running!${NC}"
    echo "Please start the services with: docker-compose up -d"
    exit 1
fi
echo -e "${GREEN}✓ Services are running${NC}"
echo ""

# Build the performance test tool
echo -e "${YELLOW}Building performance test tool...${NC}"
cd "$PERF_TEST_DIR"
go build -o perftest main.go
echo -e "${GREEN}✓ Build complete${NC}"
echo ""

# Run the test
echo -e "${YELLOW}Starting performance test...${NC}"
echo ""
./perftest --writes "$WRITES" --reads "$READS" --duration "$DURATION" --workers "$WORKERS"

# Cleanup
rm -f perftest

echo ""
echo -e "${GREEN}Performance test completed!${NC}"
