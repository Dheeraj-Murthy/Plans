#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Quick Add to Plans
# @raycast.mode silent
# @raycast.packageName Plans

# Optional parameters:
# @raycast.icon 🗒️
# @raycast.argument1 { "type": "text", "placeholder": "Task" }

TOKEN=$(cat ~/.plans_app/quickadd_token 2>/dev/null)
if [ -z "$TOKEN" ]; then
  echo "Plans app hasn't been launched yet"
  exit 1
fi

RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://127.0.0.1:51793/quickadd \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"text\": \"$1\"}")

if [ "$RESPONSE" = "201" ]; then
  echo "Added"
else
  echo "Failed ($RESPONSE)"
fi
