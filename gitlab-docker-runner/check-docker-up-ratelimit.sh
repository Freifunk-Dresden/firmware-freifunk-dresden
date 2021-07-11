#!/bin/bash

# https://docs.docker.com/docker-hub/download-rate-limit/

if [ -z "$(which jq)" ]; then
	echo "Please install 'jq'"
	exit 1
fi

echo "get access token"
TOKEN=$(curl "https://auth.docker.io/token?service=registry.docker.io&scope=repository:ratelimitpreview/test:pull" | jq -r .token)

echo "request rate limit"
curl --head -H "Authorization: Bearer $TOKEN" https://registry-1.docker.io/v2/ratelimitpreview/test/manifests/latest
