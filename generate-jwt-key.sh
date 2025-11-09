#!/bin/bash
# Script to generate a secure JWT secret key

set -e

echo "=========================================="
echo "JWT Secret Key Generator"
echo "=========================================="
echo ""

# Check if openssl is available
if command -v openssl &> /dev/null; then
    echo "Generating secure JWT secret key..."
    JWT_KEY=$(openssl rand -hex 64)
    echo ""
    echo "✓ Generated 128-character secure key"
elif command -v ruby &> /dev/null; then
    echo "Using Ruby to generate secure key..."
    JWT_KEY=$(ruby -e "require 'securerandom'; puts SecureRandom.hex(64)")
    echo ""
    echo "✓ Generated 128-character secure key"
else
    echo "❌ Error: Neither openssl nor ruby is available"
    echo "Please install openssl or ruby to generate a secure key"
    exit 1
fi

echo ""
echo "=========================================="
echo "Your JWT Secret Key:"
echo "=========================================="
echo "$JWT_KEY"
echo ""
echo "=========================================="
echo "Next Steps:"
echo "=========================================="
echo ""
echo "1. For docker-compose:"
echo "   export JWT_SECRET_KEY='$JWT_KEY'"
echo "   docker-compose up -d"
echo ""
echo "2. For .env file:"
echo "   echo \"JWT_SECRET_KEY=$JWT_KEY\" >> .env"
echo ""
echo "3. For production deployment:"
echo "   - Set as environment variable in your deployment system"
echo "   - DO NOT commit this key to version control"
echo "   - Use different keys for different environments"
echo ""
echo "=========================================="
echo "Security Notes:"
echo "=========================================="
echo "✓ Key length: 128 characters (very secure)"
echo "✓ Generated using cryptographically secure random"
echo "✓ Unique to this generation"
echo ""
echo "⚠️  IMPORTANT:"
echo "   - Never commit this key to Git"
echo "   - Store securely in secret management system"
echo "   - Use different keys for dev/staging/production"
echo "   - Rotate keys every 3-6 months"
echo ""
