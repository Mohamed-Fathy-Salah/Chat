#!/bin/bash
# Run all tests for both Request and Writer services

# Clear any conflicting Ruby environment variables
unset BUNDLE_IGNORE_CONFIGURE_RUBY_VERSION
unset RUBYLIB
unset GEM_HOME
unset GEM_PATH

# Disable system Ruby gem preloading
export RUBYOPT="--disable-gems"

# Force use of Ruby 3.2.0 via rbenv
export RBENV_VERSION=3.2.0
export PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH"
if command -v rbenv >/dev/null 2>&1; then
  eval "$(rbenv init - bash)" 2>/dev/null || true
fi

# Re-enable gems after rbenv is initialized
export RUBYOPT=""

# Tell bundler to ignore Ruby version mismatches (since we're managing it with rbenv)
export BUNDLE_IGNORE_RUBY_VERSION=1

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo "=========================================="
echo "  Running All Tests"
echo "=========================================="
echo ""

# Track success/failure
REQUESTS_TESTS_PASSED=0
WRITER_TESTS_PASSED=0

# Set JWT secret key for tests
export JWT_SECRET_KEY='test_secret_key_minimum_32_characters_required_for_testing_purposes'

# ==========================================
# Request Service Tests (Ruby/Rails)
# ==========================================

echo -e "${BLUE}[1/2] Running Request Service Tests (Ruby)${NC}"
echo "=========================================="
echo ""

cd requests

# Check if dependencies are installed
if [ ! -d "vendor/bundle" ] && [ ! -d "$HOME/.bundle" ]; then
    echo -e "${YELLOW}Installing Ruby dependencies...${NC}"
    $HOME/.rbenv/versions/3.2.0/bin/ruby $HOME/.rbenv/versions/3.2.0/bin/bundle install --quiet
fi

# Export test environment variables
export RAILS_ENV=test
export DATABASE_HOST=${DATABASE_HOST:-127.0.0.1}
export REDIS_URL=${REDIS_URL:-redis://127.0.0.1:6379/1}
export RABBITMQ_URL=${RABBITMQ_URL:-amqp://guest:guest@127.0.0.1:5672}
export ELASTICSEARCH_URL=${ELASTICSEARCH_URL:-http://127.0.0.1:9200}

# Setup test database
echo "Setting up test database..."
$HOME/.rbenv/versions/3.2.0/bin/ruby $HOME/.rbenv/versions/3.2.0/bin/bundle exec rails db:drop RAILS_ENV=test 2>/dev/null || true
$HOME/.rbenv/versions/3.2.0/bin/ruby $HOME/.rbenv/versions/3.2.0/bin/bundle exec rails db:create RAILS_ENV=test
$HOME/.rbenv/versions/3.2.0/bin/ruby $HOME/.rbenv/versions/3.2.0/bin/bundle exec rails db:migrate RAILS_ENV=test

echo ""
echo "Running RSpec tests..."
echo ""

# Run tests with better output
if $HOME/.rbenv/versions/3.2.0/bin/ruby $HOME/.rbenv/versions/3.2.0/bin/bundle exec rspec --format documentation --color; then
    REQUESTS_TESTS_PASSED=1
    echo ""
    echo -e "${GREEN}✓ Request Service Tests: PASSED${NC}"
else
    echo ""
    echo -e "${RED}✗ Request Service Tests: FAILED${NC}"
fi

cd ..

echo ""
echo "=========================================="
echo ""

# ==========================================
# Writer Service Tests (Go)
# ==========================================

echo -e "${BLUE}[2/2] Running Writer Service Tests (Go)${NC}"
echo "=========================================="
echo ""

cd writer

# Check if dependencies are downloaded
if [ ! -d "vendor" ] && [ ! -f "go.sum" ]; then
    echo -e "${YELLOW}Downloading Go dependencies...${NC}"
    go mod download
fi

echo "Running Go tests..."
echo ""

# Run tests with verbose output
if go test -v ./...; then
    WRITER_TESTS_PASSED=1
    echo ""
    echo -e "${GREEN}✓ Writer Service Tests: PASSED${NC}"
else
    echo ""
    echo -e "${RED}✗ Writer Service Tests: FAILED${NC}"
fi

cd ..

# ==========================================
# Summary
# ==========================================

echo ""
echo "=========================================="
echo "  Test Results Summary"
echo "=========================================="
echo ""

if [ $REQUESTS_TESTS_PASSED -eq 1 ]; then
    echo -e "${GREEN}✓ Request Service (Ruby/Rails): PASSED${NC}"
else
    echo -e "${RED}✗ Request Service (Ruby/Rails): FAILED${NC}"
fi

if [ $WRITER_TESTS_PASSED -eq 1 ]; then
    echo -e "${GREEN}✓ Writer Service (Go):          PASSED${NC}"
else
    echo -e "${RED}✗ Writer Service (Go):          FAILED${NC}"
fi

echo ""
echo "=========================================="
echo ""

# Exit with error if any tests failed
if [ $REQUESTS_TESTS_PASSED -eq 1 ] && [ $WRITER_TESTS_PASSED -eq 1 ]; then
    echo -e "${GREEN}All tests passed! ✓${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}Some tests failed! ✗${NC}"
    echo ""
    echo "Tips:"
    echo "  - Check that all services are running (docker-compose up -d)"
    echo "  - Verify environment variables are set correctly"
    echo "  - Check logs for specific error messages"
    echo "  - Run individual test suites for more details"
    echo ""
    exit 1
fi
