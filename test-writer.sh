#!/bin/bash
# Quick test runner for Writer Service only

set -e

echo "Running Writer Service Tests..."
echo ""

cd writer

# Run tests with any additional arguments passed
go test -v ./... "$@"
