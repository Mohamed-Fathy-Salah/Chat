#!/bin/bash

# Elasticsearch Viewer Helper Script
# Usage: ./es-viewer.sh [command]

ES_URL="http://localhost:9200"

case "${1:-help}" in
  "health")
    echo "=== Elasticsearch Health ==="
    curl -s "$ES_URL/_cluster/health?pretty"
    ;;
    
  "indices"|"index")
    echo "=== All Indices ==="
    curl -s "$ES_URL/_cat/indices?v"
    ;;
    
  "messages"|"all")
    echo "=== All Messages ==="
    curl -s "$ES_URL/messages/_search?pretty&size=100" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f\"Total: {data['hits']['total']['value']} messages\n\")
for hit in data['hits']['hits']:
    src = hit['_source']
    print(f\"[{src['number']}] Chat {src['chat_number']} - Sender {src['sender_id']}\")
    print(f\"    {src['body']}\")
    print(f\"    {src['created_at']}\n\")
"
    ;;
    
  "count")
    echo "=== Message Count ==="
    curl -s "$ES_URL/messages/_count?pretty"
    ;;
    
  "mapping")
    echo "=== Index Mapping ==="
    curl -s "$ES_URL/messages/_mapping?pretty"
    ;;
    
  "search")
    if [ -z "$2" ]; then
      echo "Usage: $0 search <query>"
      exit 1
    fi
    echo "=== Searching for: '$2' ==="
    curl -s -X GET "$ES_URL/messages/_search?pretty" -H 'Content-Type: application/json' -d"{
      \"query\": {
        \"match\": {
          \"body\": \"$2\"
        }
      }
    }" | python3 -c "
import sys, json
data = json.load(sys.stdin)
hits = data['hits']['hits']
print(f\"Found {len(hits)} results\n\")
for hit in hits:
    src = hit['_source']
    print(f\"Message {src['number']}: {src['body']}\")
    print(f\"  Score: {hit['_score']}, Created: {src['created_at']}\n\")
"
    ;;
    
  "delete-index")
    echo "=== Deleting messages index ==="
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
      curl -X DELETE "$ES_URL/messages?pretty"
      echo "Index deleted. It will be recreated automatically on next message."
    else
      echo "Cancelled."
    fi
    ;;
    
  "stats")
    echo "=== Index Statistics ==="
    curl -s "$ES_URL/messages/_stats?pretty" | grep -A 3 '"docs"' | head -5
    ;;
    
  "help"|*)
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════╗
║          Elasticsearch Viewer - Quick Commands            ║
╚═══════════════════════════════════════════════════════════╝

Usage: ./es-viewer.sh [command]

Commands:
  health          - Show cluster health status
  indices         - List all indices
  messages        - Show all messages (formatted)
  count           - Count total messages
  mapping         - Show index field mapping
  search <text>   - Search messages by text
  stats           - Show index statistics
  delete-index    - Delete messages index (careful!)
  help            - Show this help

Examples:
  ./es-viewer.sh messages
  ./es-viewer.sh search "hello"
  ./es-viewer.sh health

Web Access:
  Browser: http://localhost:9200/messages/_search?pretty
  Health:  http://localhost:9200/_cluster/health?pretty

EOF
    ;;
esac
