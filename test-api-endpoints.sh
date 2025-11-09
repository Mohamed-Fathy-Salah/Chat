#!/bin/bash
# Comprehensive API endpoint testing script

# Don't exit on errors - we want to run all tests
set +e

BASE_URL="http://localhost:3000/api/v1"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0

# Function to test endpoint
test_endpoint() {
    local method=$1
    local endpoint=$2
    local data=$3
    local expected_status=$4
    local description=$5
    local token=$6
    
    echo -n "Testing: $description ... "
    
    if [ -n "$token" ]; then
        COOKIE="Cookie: auth_token=$token"
    else
        COOKIE=""
    fi
    
    if [ "$method" = "GET" ]; then
        response=$(curl -s -w "\n%{http_code}" -X GET "$BASE_URL$endpoint" -H "$COOKIE" 2>/dev/null || echo "000")
    elif [ "$method" = "POST" ]; then
        response=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL$endpoint" \
            -H "Content-Type: application/json" \
            -H "$COOKIE" \
            -d "$data" 2>/dev/null || echo "000")
    elif [ "$method" = "PUT" ]; then
        response=$(curl -s -w "\n%{http_code}" -X PUT "$BASE_URL$endpoint" \
            -H "Content-Type: application/json" \
            -H "$COOKIE" \
            -d "$data" 2>/dev/null || echo "000")
    elif [ "$method" = "DELETE" ]; then
        response=$(curl -s -w "\n%{http_code}" -X DELETE "$BASE_URL$endpoint" \
            -H "$COOKIE" 2>/dev/null || echo "000")
    fi
    
    status_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | head -n -1)
    
    if [ "$status_code" = "$expected_status" ]; then
        echo -e "${GREEN}✓ PASS${NC} (HTTP $status_code)"
        ((PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC} (Expected: $expected_status, Got: $status_code)"
        echo "  Response: $body"
        ((FAILED++))
        return 1
    fi
}

echo ""
echo "=========================================="
echo "  API Endpoint Testing"
echo "=========================================="
echo ""
echo "Base URL: $BASE_URL"
echo ""

# ==========================================
# 1. Authentication Endpoints
# ==========================================
echo -e "${BLUE}[1/6] Authentication Endpoints${NC}"
echo "=========================================="

# Generate unique email for this test run
TIMESTAMP=$(date +%s)
TEST_EMAIL="test${TIMESTAMP}@example.com"

# Register
REGISTER_DATA="{\"email\":\"$TEST_EMAIL\",\"password\":\"password123\",\"password_confirmation\":\"password123\",\"name\":\"Test User\"}"
test_endpoint "POST" "/auth/register" "$REGISTER_DATA" "201" "POST /auth/register - Register new user"

# Register duplicate (should fail)
test_endpoint "POST" "/auth/register" "$REGISTER_DATA" "422" "POST /auth/register - Duplicate email"

# Login
LOGIN_DATA="{\"email\":\"$TEST_EMAIL\",\"password\":\"password123\"}"
LOGIN_RESPONSE=$(curl -s -c /tmp/cookies.txt -X POST "$BASE_URL/auth/login" \
    -H "Content-Type: application/json" \
    -d "$LOGIN_DATA")
LOGIN_STATUS=$(curl -s -w "%{http_code}" -c /tmp/cookies.txt -o /dev/null -X POST "$BASE_URL/auth/login" \
    -H "Content-Type: application/json" \
    -d "$LOGIN_DATA")

if [ "$LOGIN_STATUS" = "200" ]; then
    echo -e "Testing: POST /auth/login - Login user ... ${GREEN}✓ PASS${NC} (HTTP 200)"
    ((PASSED++))
    AUTH_TOKEN=$(grep auth_token /tmp/cookies.txt | awk '{print $7}')
else
    echo -e "Testing: POST /auth/login - Login user ... ${RED}✗ FAIL${NC} (HTTP $LOGIN_STATUS)"
    ((FAILED++))
    AUTH_TOKEN=""
fi

# Login with wrong password
WRONG_LOGIN="{\"email\":\"$TEST_EMAIL\",\"password\":\"wrongpassword\"}"
test_endpoint "POST" "/auth/login" "$WRONG_LOGIN" "401" "POST /auth/login - Wrong password"

# Get current user
test_endpoint "GET" "/auth/me" "" "200" "GET /auth/me - Get current user" "$AUTH_TOKEN"

# Logout
test_endpoint "DELETE" "/auth/logout" "" "200" "DELETE /auth/logout - Logout user" "$AUTH_TOKEN"

echo ""

# ==========================================
# 2. Application Endpoints
# ==========================================
echo -e "${BLUE}[2/6] Application Endpoints${NC}"
echo "=========================================="

# Create application
APP_DATA='{"name":"Test App"}'
APP_RESPONSE=$(curl -s -X POST "$BASE_URL/applications" \
    -H "Content-Type: application/json" \
    -H "Cookie: auth_token=$AUTH_TOKEN" \
    -d "$APP_DATA")
APP_STATUS=$(curl -s -w "%{http_code}" -o /dev/null -X POST "$BASE_URL/applications" \
    -H "Content-Type: application/json" \
    -H "Cookie: auth_token=$AUTH_TOKEN" \
    -d "$APP_DATA")

if [ "$APP_STATUS" = "201" ]; then
    echo -e "Testing: POST /applications - Create application ... ${GREEN}✓ PASS${NC} (HTTP 201)"
    ((PASSED++))
    APP_TOKEN=$(echo "$APP_RESPONSE" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
else
    echo -e "Testing: POST /applications - Create application ... ${RED}✗ FAIL${NC} (HTTP $APP_STATUS)"
    ((FAILED++))
    APP_TOKEN=""
fi

# List applications
test_endpoint "GET" "/applications" "" "200" "GET /applications - List applications" "$AUTH_TOKEN"

# List applications with pagination
test_endpoint "GET" "/applications?page=1&limit=10" "" "200" "GET /applications?page=1&limit=10 - Paginated list" "$AUTH_TOKEN"

# Update application
if [ -n "$APP_TOKEN" ]; then
    UPDATE_DATA="{\"token\":\"$APP_TOKEN\",\"name\":\"Updated App Name\"}"
    test_endpoint "PUT" "/applications" "$UPDATE_DATA" "200" "PUT /applications - Update application" "$AUTH_TOKEN"
fi

echo ""

# ==========================================
# 3. Chat Endpoints
# ==========================================
echo -e "${BLUE}[3/6] Chat Endpoints${NC}"
echo "=========================================="

if [ -n "$APP_TOKEN" ]; then
    # Create chat
    CHAT_RESPONSE=$(curl -s -X POST "$BASE_URL/applications/$APP_TOKEN/chats" \
        -H "Cookie: auth_token=$AUTH_TOKEN")
    CHAT_STATUS=$(curl -s -w "%{http_code}" -o /dev/null -X POST "$BASE_URL/applications/$APP_TOKEN/chats" \
        -H "Cookie: auth_token=$AUTH_TOKEN")
    
    if [ "$CHAT_STATUS" = "201" ]; then
        echo -e "Testing: POST /applications/:token/chats - Create chat ... ${GREEN}✓ PASS${NC} (HTTP 201)"
        ((PASSED++))
        CHAT_NUMBER=$(echo "$CHAT_RESPONSE" | grep -o '"number":[0-9]*' | cut -d':' -f2)
    else
        echo -e "Testing: POST /applications/:token/chats - Create chat ... ${RED}✗ FAIL${NC} (HTTP $CHAT_STATUS)"
        ((FAILED++))
        CHAT_NUMBER=""
    fi
    
    # List chats
    test_endpoint "GET" "/applications/$APP_TOKEN/chats" "" "200" "GET /applications/:token/chats - List chats" "$AUTH_TOKEN"
    
    # List chats with pagination
    test_endpoint "GET" "/applications/$APP_TOKEN/chats?page=1&limit=10" "" "200" "GET /applications/:token/chats?page=1&limit=10 - Paginated chats" "$AUTH_TOKEN"
fi

echo ""

# ==========================================
# 4. Message Endpoints
# ==========================================
echo -e "${BLUE}[4/6] Message Endpoints${NC}"
echo "=========================================="

if [ -n "$APP_TOKEN" ] && [ -n "$CHAT_NUMBER" ]; then
    # Create message
    MSG_DATA='{"body":"Hello, this is a test message!"}'
    MSG_RESPONSE=$(curl -s -X POST "$BASE_URL/applications/$APP_TOKEN/chats/$CHAT_NUMBER/messages" \
        -H "Content-Type: application/json" \
        -H "Cookie: auth_token=$AUTH_TOKEN" \
        -d "$MSG_DATA")
    MSG_STATUS=$(curl -s -w "%{http_code}" -o /dev/null -X POST "$BASE_URL/applications/$APP_TOKEN/chats/$CHAT_NUMBER/messages" \
        -H "Content-Type: application/json" \
        -H "Cookie: auth_token=$AUTH_TOKEN" \
        -d "$MSG_DATA")
    
    if [ "$MSG_STATUS" = "201" ]; then
        echo -e "Testing: POST /applications/:token/chats/:number/messages - Create message ... ${GREEN}✓ PASS${NC} (HTTP 201)"
        ((PASSED++))
        MSG_NUMBER=$(echo "$MSG_RESPONSE" | grep -o '"number":[0-9]*' | cut -d':' -f2)
    else
        echo -e "Testing: POST /applications/:token/chats/:number/messages - Create message ... ${RED}✗ FAIL${NC} (HTTP $MSG_STATUS)"
        ((FAILED++))
        MSG_NUMBER=""
    fi
    
    # Wait for async processing
    echo "Waiting 3 seconds for async processing..."
    sleep 3
    
    # List messages
    test_endpoint "GET" "/applications/$APP_TOKEN/chats/$CHAT_NUMBER/messages" "" "200" "GET /applications/:token/chats/:number/messages - List messages" "$AUTH_TOKEN"
    
    # List messages with pagination
    test_endpoint "GET" "/applications/$APP_TOKEN/chats/$CHAT_NUMBER/messages?page=1&limit=10" "" "200" "GET /applications/:token/chats/:number/messages?page=1&limit=10 - Paginated" "$AUTH_TOKEN"
    
    # Update message
    if [ -n "$MSG_NUMBER" ]; then
        UPDATE_MSG='{"body":"Updated message content"}'
        test_endpoint "PUT" "/applications/$APP_TOKEN/chats/$CHAT_NUMBER/messages" "$UPDATE_MSG" "200" "PUT /applications/:token/chats/:number/messages - Update" "$AUTH_TOKEN"
    fi
    
    # Search messages
    test_endpoint "GET" "/applications/$APP_TOKEN/chats/$CHAT_NUMBER/messages/search?query=test" "" "200" "GET /applications/:token/chats/:number/messages/search - Search" "$AUTH_TOKEN"
fi

echo ""

# ==========================================
# 5. Error Handling & Validation
# ==========================================
echo -e "${BLUE}[5/6] Error Handling & Validation${NC}"
echo "=========================================="

# Invalid email format
INVALID_EMAIL='{"email":"invalid-email","password":"password123","password_confirmation":"password123","name":"Test"}'
test_endpoint "POST" "/auth/register" "$INVALID_EMAIL" "422" "POST /auth/register - Invalid email format"

# Short password
SHORT_PASSWORD='{"email":"test2@example.com","password":"123","password_confirmation":"123","name":"Test"}'
test_endpoint "POST" "/auth/register" "$SHORT_PASSWORD" "422" "POST /auth/register - Short password"

# Missing required fields
MISSING_FIELDS='{"email":"test3@example.com"}'
test_endpoint "POST" "/auth/register" "$MISSING_FIELDS" "422" "POST /auth/register - Missing fields"

# Unauthorized access (no token)
test_endpoint "GET" "/applications" "" "401" "GET /applications - Unauthorized access"

# Invalid pagination (should fail validation)
test_endpoint "GET" "/applications?page=-1&limit=200" "" "422" "GET /applications?page=-1 - Invalid pagination" "$AUTH_TOKEN"

echo ""

# ==========================================
# 6. Summary
# ==========================================
echo -e "${BLUE}[6/6] Test Cleanup${NC}"
echo "=========================================="
echo "Note: No DELETE operations available in current API"
echo ""

# ==========================================
# Summary
# ==========================================
echo "=========================================="
echo "  Test Results Summary"
echo "=========================================="
echo ""
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
TOTAL=$((PASSED + FAILED))
echo "Total:  $TOTAL"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed! ✓${NC}"
    echo ""
    exit 0
else
    PASS_RATE=$((PASSED * 100 / TOTAL))
    echo -e "${YELLOW}Pass rate: $PASS_RATE%${NC}"
    echo ""
    exit 1
fi
