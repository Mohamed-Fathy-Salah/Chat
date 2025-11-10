#!/bin/bash
# JWT Key Rotation Script

set -e

echo "=========================================="
echo "JWT Key Rotation"
echo "=========================================="
echo ""

# Check if services are running
if ! docker-compose ps | grep -q "requests.*Up"; then
    echo "⚠️  Warning: requests service is not running"
    echo ""
fi

echo "Generating new JWT key..."
NEW_KEY=$(openssl rand -hex 64)

echo "Backing up old key..."
BACKUP_FILE=".jwt_secret.backup.$(date +%Y%m%d_%H%M%S)"
docker-compose exec -T requests cat /jwt/.jwt_secret > "$BACKUP_FILE" 2>/dev/null || echo "(no existing key to backup)"

echo "Writing new key..."
echo "$NEW_KEY" | docker-compose exec -T requests sh -c 'cat > /jwt/.jwt_secret'

echo ""
echo "✓ JWT key rotated successfully"
echo "✓ Backup saved to: $BACKUP_FILE"
echo ""
echo "⚠️  IMPORTANT: Restart the services for the new key to take effect:"
echo "   docker-compose restart requests"
echo ""
echo "Note: This will invalidate all existing tokens"
echo "=========================================="
