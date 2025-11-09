#!/bin/bash
# Quick test runner for Request Service only

set -e

echo "Running Request Service Tests..."
echo ""

cd requests

export JWT_SECRET_KEY='test_secret_key_minimum_32_characters_required_for_testing_purposes'
export RAILS_ENV=test
export DATABASE_HOST=${DATABASE_HOST:-localhost}
export REDIS_URL=${REDIS_URL:-redis://localhost:6379/1}
export RABBITMQ_URL=${RABBITMQ_URL:-amqp://guest:guest@localhost:5672}
export ELASTICSEARCH_URL=${ELASTICSEARCH_URL:-http://localhost:9200}

# Setup database
bundle exec rails db:create RAILS_ENV=test 2>/dev/null || true
bundle exec rails db:migrate RAILS_ENV=test

# Run tests
bundle exec rspec "$@"
