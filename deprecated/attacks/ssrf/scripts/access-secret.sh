response=$(
    curl -s "https://secretmanager.googleapis.com/v1/projects/$PROJECT_ID/secrets/session-secret/versions/latest:access" \
        --header "authorization: Bearer $1" \
        --header "content-type: application/json" \
        --fail-with-body
) ||
    (echo $response && exit 1) &&
    echo Successfully retrieved secret value: $(
        echo $response |
            jq -r '.payload.data' |
            base64 -d
    )
