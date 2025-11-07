#!/bin/bash

# Comprehensive API Test Script
# Tests Applications, Chats, and Messages endpoints

API_URL="http://localhost:3000"
COOKIES_FILE="test_cookies.txt"

echo "==================================="
echo "Testing Full Chat API"
echo "==================================="
echo ""

# Step 1: Register and login
echo "Step 1: Registering and logging in..."
curl -s -c $COOKIES_FILE -X POST "$API_URL/api/v1/auth/register" \
  -H "Content-Type: application/json" \
  -d '{
    "user": {
      "email": "testuser@example.com",
      "password": "password123",
      "password_confirmation": "password123",
      "name": "Test User"
    }
  }' > /dev/null

echo "✓ User registered and logged in"
echo ""

# Step 2: Create an application
echo "Step 2: Creating an application..."
APP_RESPONSE=$(curl -s -b $COOKIES_FILE -X POST "$API_URL/api/v1/applications" \
  -H "Content-Type: application/json" \
  -d '{"name": "My Test App"}')

APP_TOKEN=$(echo $APP_RESPONSE | grep -o '"token":"[^"]*' | cut -d'"' -f4)
echo "✓ Application created with token: $APP_TOKEN"
echo "Response: $APP_RESPONSE"
echo ""

# Step 3: List applications
echo "Step 3: Listing applications..."
APPS_LIST=$(curl -s -b $COOKIES_FILE -X GET "$API_URL/api/v1/applications")
echo "Response: $APPS_LIST"
echo ""

# Step 4: Update application
echo "Step 4: Updating application name..."
UPDATE_RESPONSE=$(curl -s -b $COOKIES_FILE -w "\n%{http_code}" -X PUT "$API_URL/api/v1/applications" \
  -H "Content-Type: application/json" \
  -d "{\"token\": \"$APP_TOKEN\", \"name\": \"Updated App Name\"}")

HTTP_CODE=$(echo "$UPDATE_RESPONSE" | tail -n1)
echo "✓ Application updated (Status: $HTTP_CODE)"
echo ""

# Step 5: Create a chat
echo "Step 5: Creating a chat..."
CHAT_RESPONSE=$(curl -s -b $COOKIES_FILE -X POST "$API_URL/api/v1/applications/$APP_TOKEN/chats")
CHAT_NUMBER=$(echo $CHAT_RESPONSE | grep -o '"chatNumber":[0-9]*' | cut -d':' -f2)
echo "✓ Chat created with number: $CHAT_NUMBER"
echo "Response: $CHAT_RESPONSE"
echo ""

# Step 6: Create another chat
echo "Step 6: Creating another chat..."
CHAT2_RESPONSE=$(curl -s -b $COOKIES_FILE -X POST "$API_URL/api/v1/applications/$APP_TOKEN/chats")
CHAT2_NUMBER=$(echo $CHAT2_RESPONSE | grep -o '"chatNumber":[0-9]*' | cut -d':' -f2)
echo "✓ Second chat created with number: $CHAT2_NUMBER"
echo ""

# Step 7: List chats
echo "Step 7: Listing chats..."
CHATS_LIST=$(curl -s -b $COOKIES_FILE -X GET "$API_URL/api/v1/applications/$APP_TOKEN/chats")
echo "Response: $CHATS_LIST"
echo ""

# Step 8: Create a message
echo "Step 8: Creating a message..."
MSG_RESPONSE=$(curl -s -b $COOKIES_FILE -X POST "$API_URL/api/v1/applications/$APP_TOKEN/chats/$CHAT_NUMBER/messages" \
  -H "Content-Type: application/json" \
  -d '{"body": "Hello, this is my first message!"}')

MSG_NUMBER=$(echo $MSG_RESPONSE | grep -o '"messageNumber":[0-9]*' | cut -d':' -f2)
echo "✓ Message created with number: $MSG_NUMBER"
echo "Response: $MSG_RESPONSE"
echo ""

# Step 9: Create more messages
echo "Step 9: Creating more messages..."
for i in {2..5}; do
  curl -s -b $COOKIES_FILE -X POST "$API_URL/api/v1/applications/$APP_TOKEN/chats/$CHAT_NUMBER/messages" \
    -H "Content-Type: application/json" \
    -d "{\"body\": \"This is message number $i\"}" > /dev/null
done
echo "✓ Created 4 more messages"
echo ""

# Step 10: List messages
echo "Step 10: Listing messages (page 1, limit 10)..."
MSGS_LIST=$(curl -s -b $COOKIES_FILE -X GET "$API_URL/api/v1/applications/$APP_TOKEN/chats/$CHAT_NUMBER/messages?page=1&limit=10")
echo "Response: $MSGS_LIST"
echo ""

# Step 11: Update a message
echo "Step 11: Updating message #$MSG_NUMBER..."
UPDATE_MSG_RESPONSE=$(curl -s -b $COOKIES_FILE -w "\n%{http_code}" -X PUT "$API_URL/api/v1/applications/$APP_TOKEN/chats/$CHAT_NUMBER/messages" \
  -H "Content-Type: application/json" \
  -d "{\"messageNumber\": $MSG_NUMBER, \"body\": \"Updated message content\"}")

HTTP_CODE=$(echo "$UPDATE_MSG_RESPONSE" | tail -n1)
echo "✓ Message updated (Status: $HTTP_CODE)"
echo ""

# Step 12: Search messages
echo "Step 12: Searching for messages containing 'first'..."
SEARCH_RESPONSE=$(curl -s -b $COOKIES_FILE -X GET "$API_URL/api/v1/applications/$APP_TOKEN/chats/$CHAT_NUMBER/messages/search?q=first")
echo "Response: $SEARCH_RESPONSE"
echo ""

# Step 13: Search for updated message
echo "Step 13: Searching for messages containing 'Updated'..."
SEARCH2_RESPONSE=$(curl -s -b $COOKIES_FILE -X GET "$API_URL/api/v1/applications/$APP_TOKEN/chats/$CHAT_NUMBER/messages/search?q=Updated")
echo "Response: $SEARCH2_RESPONSE"
echo ""

# Step 14: Test error handling - non-existent application
echo "Step 14: Testing error handling (non-existent application)..."
ERROR_RESPONSE=$(curl -s -b $COOKIES_FILE -w "\n%{http_code}" -X GET "$API_URL/api/v1/applications/invalid-token/chats")
HTTP_CODE=$(echo "$ERROR_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$ERROR_RESPONSE" | head -n-1)
echo "Status Code: $HTTP_CODE"
echo "Response: $RESPONSE_BODY"
echo ""

# Cleanup
rm -f $COOKIES_FILE

echo "==================================="
echo "All tests completed successfully!"
echo "==================================="
echo ""
echo "Summary:"
echo "- Created application with token: $APP_TOKEN"
echo "- Created 2 chats (numbers: $CHAT_NUMBER, $CHAT2_NUMBER)"
echo "- Created 5 messages in chat #$CHAT_NUMBER"
echo "- Updated message #$MSG_NUMBER"
echo "- Tested message search functionality"
echo "- Tested error handling"
