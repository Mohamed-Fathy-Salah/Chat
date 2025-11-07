#!/bin/bash

# Test script for Auth API
# This script tests all authentication endpoints

API_URL="http://localhost:3000"

echo "==================================="
echo "Testing Authentication API"
echo "==================================="
echo ""

# Test 1: Register a new user
echo "1. Testing user registration..."
REGISTER_RESPONSE=$(curl -s -c cookies.txt -w "\n%{http_code}" \
  -X POST "$API_URL/api/v1/auth/register" \
  -H "Content-Type: application/json" \
  -d '{
    "user": {
      "email": "test@example.com",
      "password": "password123",
      "password_confirmation": "password123",
      "name": "Test User"
    }
  }')

HTTP_CODE=$(echo "$REGISTER_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$REGISTER_RESPONSE" | head -n-1)

echo "Status Code: $HTTP_CODE"
echo "Response: $RESPONSE_BODY"
echo ""

# Test 2: Login with correct credentials
echo "2. Testing login with correct credentials..."
LOGIN_RESPONSE=$(curl -s -c cookies.txt -w "\n%{http_code}" \
  -X POST "$API_URL/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "password123"
  }')

HTTP_CODE=$(echo "$LOGIN_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$LOGIN_RESPONSE" | head -n-1)

echo "Status Code: $HTTP_CODE"
echo "Response: $RESPONSE_BODY"
echo ""

# Test 3: Get current user
echo "3. Testing authenticated endpoint (GET /me)..."
ME_RESPONSE=$(curl -s -b cookies.txt -w "\n%{http_code}" \
  -X GET "$API_URL/api/v1/auth/me")

HTTP_CODE=$(echo "$ME_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$ME_RESPONSE" | head -n-1)

echo "Status Code: $HTTP_CODE"
echo "Response: $RESPONSE_BODY"
echo ""

# Test 4: Refresh token
echo "4. Testing token refresh..."
REFRESH_RESPONSE=$(curl -s -b cookies.txt -c cookies.txt -w "\n%{http_code}" \
  -X POST "$API_URL/api/v1/auth/refresh")

HTTP_CODE=$(echo "$REFRESH_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$REFRESH_RESPONSE" | head -n-1)

echo "Status Code: $HTTP_CODE"
echo "Response: $RESPONSE_BODY"
echo ""

# Test 5: Logout
echo "5. Testing logout..."
LOGOUT_RESPONSE=$(curl -s -b cookies.txt -w "\n%{http_code}" \
  -X DELETE "$API_URL/api/v1/auth/logout")

HTTP_CODE=$(echo "$LOGOUT_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$LOGOUT_RESPONSE" | head -n-1)

echo "Status Code: $HTTP_CODE"
echo "Response: $RESPONSE_BODY"
echo ""

# Test 6: Try to access protected endpoint after logout
echo "6. Testing access after logout (should fail)..."
AFTER_LOGOUT=$(curl -s -b cookies.txt -w "\n%{http_code}" \
  -X GET "$API_URL/api/v1/auth/me")

HTTP_CODE=$(echo "$AFTER_LOGOUT" | tail -n1)
RESPONSE_BODY=$(echo "$AFTER_LOGOUT" | head -n-1)

echo "Status Code: $HTTP_CODE"
echo "Response: $RESPONSE_BODY"
echo ""

# Test 7: Login with wrong password
echo "7. Testing login with wrong password..."
WRONG_PASSWORD=$(curl -s -w "\n%{http_code}" \
  -X POST "$API_URL/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "wrongpassword"
  }')

HTTP_CODE=$(echo "$WRONG_PASSWORD" | tail -n1)
RESPONSE_BODY=$(echo "$WRONG_PASSWORD" | head -n-1)

echo "Status Code: $HTTP_CODE"
echo "Response: $RESPONSE_BODY"
echo ""

# Cleanup
rm -f cookies.txt

echo "==================================="
echo "All tests completed!"
echo "==================================="
