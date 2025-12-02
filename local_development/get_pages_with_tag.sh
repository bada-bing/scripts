curl -s --request POST \
  --url http://127.0.0.1:12315/api \
  --header "authorization: Bearer $LOGSEQ_SERVER_API_TOKEN" \
  --header 'content-type: application/json' \
  --data '{"method": "logseq.db.q", "args": ["(page-tags [[Task]])"]}' | jq 'map(.name) | .[]'