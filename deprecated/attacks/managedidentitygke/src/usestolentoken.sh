
#!/bin/bash

# Fetch the OAuth2 token from the metadata server 
# Option 1 - Shell into your GKE node and run the following command:
TOKEN=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" | jq -r '.access_token')
# Option 2 : port forward the minimi-service to 8080 and run the following command


# Bearer token (this one is expired!)
TOKEN="ya29.c.c0ASRK0GaahWvICyZo4JgXU3cfLgX9tV65mAFBSN-KZE5le1Yb0A9_mnHJR8bMhanpXFa9zW5OiBpbNSYFeR6lH8OAvftOZK8wOIKu67kR3sGyu0bnBCUHPZ3Sm6RePorgDtaqrCLklTfJjrS8YEeR-7UpW4nmi_5ByQf_oiAQF4nUA-cyvw6JgCcdHNqhLGVPvvRHOey_7tubE0VkKarDnHoIh6HnffCDxgIszYfjGfF80QqLZ4h6dIFA2BZizQmNHkFyfkxAzuqmOyyNvDJPF0qCQcMw8nXLOib6x3x1udQj0_-LMT8nPPlQNCtsjgjyRPfljW9x3NssmD7SMLbK0C0fyAGJVMt9N3smmABaqCSVs30y93jVtdWQEv0i7Aim64N1PhJZiSpMpTJ0qRxzazLBVuG99KNkB4Dhw-eKZVnpRtr10Pp3CK32JgclswZyQIl8FluBziVNz_rUiDDnHn3s4tj2JpkN1h1X4xtEIk17evRBXKBrhZ25lPKQmMT-QNImsyvIHS4Tz9w9EtvifA8CVGI5Cbj-iAP1cVBz8-SnduIN38j3qtyGEfMO157DlhVDeozy0n8gGOfInYbmPFlbSRdKbbYNgs5QC2tnuOnKTmqgWGM_MwN639CuS4mUX0QFafeMFoel57X5ugkYSk-w80fl6esIlhzmuSFg4FVe94zr6M0Q8MRWqgIUZogp3oB9joRqcSxMuv0RIaXZ0xh__Xq8X6XQ1qn2YzI_MIYZF7uSwIhQg1IWtWRjV0huh-XfwJRoVs0eWSM7oWjhM0ba3Fikf9Ye6so4YR7e0O4IR7BSBRcRR7fnzY5WvaRYVSJfnOz6eolMXkBhQyjIS3hjQV0kjxzrIzzxUsXp5fiF0eMZF3Sm1IpediQ2fMWBnRxSacRnFjbpgn9q5Q0YzmOlbW2m-BiZIy9RuBaRmS5cZY02954d1c1Yo1MVcuOO7uI9W4rumlv08OmgIsd4BUrw3pFBg0StruV8R9R5VeUVw_sQFphairq"

# KMS Decrypt API endpoint
PROJECT_ID="my-gcp-projectid"
LOCATION="my-gcp-project-location"
KEY_RING="my-gcp-key-ring"
KEY_NAME="my-kms-key"
API_ENDPOINTE="https://cloudkms.googleapis.com/v1/projects/$PROJECT_ID/locations/$LOCATION/keyRings/$KEY_RING/cryptoKeys/$KEY_NAME:encrypt"
API_ENDPOINTD="https://cloudkms.googleapis.com/v1/projects/$PROJECT_ID/locations/$LOCATION/keyRings/$KEY_RING/cryptoKeys/$KEY_NAME:decrypt"

# Encrypted data (base64-encoded)
CIPHERTEXT="CiUAcbrqDGs8UAomoDqUwaLNRibC2xZvIbaZgKtqzbaexKMuOIoCEjgAwJ+FDfCbch6hqFxgQxsxmi2Q2N0wpetzPL7GS3AimxWm/Tiy2Selzl5m0xQ5I5k+SCppH7yx6Q=="
PLAINTEXT="dGhpcyBpcyBzZWNyZXQK"


# Prepare the request payload
PAYLOAD=$(jq -n --arg plaintext "$PLAINTEXT" '{plaintext: $plaintext}')

# Make the HTTP request
curl -X POST "$API_ENDPOINTE" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD"


# Prepare the request payload
PAYLOAD=$(jq -n --arg ciphertext "$CIPHERTEXT" '{ciphertext: $ciphertext}')
curl -X POST "$API_ENDPOINTD" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD"

# # when your token is not expired you ll get
# {
#   "name": "projects/xxxx/locations/xxx/keyRings/xxxx/cryptoKeys/xxx/cryptoKeyVersions/10",
#   "ciphertext": "CiUAcbrqDACmkEscnDN9iv9wL3vx2h1XO+cA712Jg4bSeB6Cn1S3EjgAwJ+FDWv1GaeLUDtpSf29AE6kMEeVfWzD5PxZcR7NWnIHzAL5KJW48g+g7MLagOj+cYHbGT4JXg==",
#   "ciphertextCrc32c": "2172507472",
#   "protectionLevel": "SOFTWARE"
# }
# {
#   "plaintext": "dGhpcyBpcyBzZWNyZXQK",
#   "plaintextCrc32c": "652025612",
#   "usedPrimary": true,
#   "protectionLevel": "SOFTWARE"
# }


# # when your token is expired you ll get 
# {
#   "error": {
#     "code": 401,
#     "message": "Request had invalid authentication credentials. Expected OAuth 2 access token, login cookie or other valid authentication credential. See https://developers.google.com/identity/sign-in/web/devconsole-project.",
#     "status": "UNAUTHENTICATED",
#     "details": [
#       {
#         "@type": "type.googleapis.com/google.rpc.ErrorInfo",
#         "reason": "ACCESS_TOKEN_EXPIRED",
#         "domain": "googleapis.com",
#         "metadata": {
#           "method": "google.cloud.kms.v1.KeyManagementService.Decrypt",
#           "service": "cloudkms.googleapis.com"
#         }
#       }
#     ]
#   }
# }

