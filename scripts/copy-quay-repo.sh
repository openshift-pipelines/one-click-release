#!/usr/bin/env bash

set -euo pipefail

ORG="openshift-pipeline"
API_URL="https://quay.io/api/v1"
EXECUTE_CREATION="${EXECUTE_CREATION:-false}"

if [[ -z "${QUAY_TOKEN:-}" ]]; then
    echo "Error: QUAY_TOKEN environment variable is not set." >&2
    echo "Export it using: export QUAY_TOKEN='your_oauth_token'" >&2
    exit 1
fi

echo "==> Fetching and processing repositories page by page under organization: ${ORG}..."
echo "------------------------------------------------------------------"

# Quay uses next_page tokens rather than numeric pages
NEXT_PAGE_TOKEN=""
HAS_MORE="true"
TOTAL_FETCHED=0
MATCHED_COUNT=0
FETCH_COUNT=1

while [[ "${HAS_MORE}" == "true" ]]; do
    echo "[INFO] Fetching batch ${FETCH_COUNT}..."

    # Construct URL with pagination token if present
    REQ_URL="${API_URL}/repository?namespace=${ORG}&limit=100"
    if [[ -n "${NEXT_PAGE_TOKEN}" ]]; then
        REQ_URL="${REQ_URL}&next_page=${NEXT_PAGE_TOKEN}"
    fi

    RESPONSE=$(curl -s -H "Authorization: Bearer ${QUAY_TOKEN}" "${REQ_URL}")

    # Use Python to extract repos and the opaque next_page token reliably via JSON
    PARSED=$(echo "${RESPONSE}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'error_message' in data:
        sys.stderr.write(f\"API Error: {data['error_message']}\n\")
        sys.exit(1)

    repos = [r['name'] for r in data.get('repositories', [])]
    next_page = data.get('next_page', '') or ''

    output = {
        'repos': repos,
        'next_page': next_page
    }
    print(json.dumps(output))
except Exception as e:
    sys.stderr.write(f'Error parsing JSON: {e}\n')
    sys.exit(1)
")

    REPOS=$(echo "${PARSED}" | python3 -c "import sys, json; print('\n'.join(json.load(sys.stdin)['repos']))")
    NEXT_PAGE_TOKEN=$(echo "${PARSED}" | python3 -c "import sys, json; print(json.load(sys.stdin)['next_page'])")

    if [[ -z "${NEXT_PAGE_TOKEN}" ]]; then
        HAS_MORE="false"
    fi

    while IFS= read -r repo; do
        [[ -z "${repo}" ]] && continue
        TOTAL_FETCHED=$((TOTAL_FETCHED + 1))

        if [[ "${repo}" == *rhel9* ]]; then
            MATCHED_COUNT=$((MATCHED_COUNT + 1))
            new_repo="${repo//rhel9/rhel10}"

            echo "  [MATCH FOUND] ${repo}"
            echo "             -> Target Repo: ${new_repo}"

            if [[ "${EXECUTE_CREATION}" == "true" ]]; then
                echo "             -> Creating empty repository via Quay API..."

                PAYLOAD=$(cat <<EOF
{
  "namespace": "${ORG}",
  "repository": "${new_repo}",
  "visibility": "public",
  "description": "Auto-created rhel10 equivalent of ${repo}",
  "repo_kind": "image"
}
EOF
)

                HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
                    -X POST \
                    -H "Authorization: Bearer ${QUAY_TOKEN}" \
                    -H "Content-Type: application/json" \
                    -d "${PAYLOAD}" \
                    "${API_URL}/repository")

                if [[ "${HTTP_STATUS}" -eq 201 ]] || [[ "${HTTP_STATUS}" -eq 200 ]]; then
                    echo "             -> Success: Empty repository created (${new_repo})"
                elif [[ "${HTTP_STATUS}" -eq 400 ]]; then
                    echo "             -> Notice: Repository ${new_repo} already exists or bad request."
                else
                    echo "             -> Error: Failed to create ${new_repo} (HTTP status: ${HTTP_STATUS})" >&2
                fi
            else
                echo "             -> [Dry-Run] Skipped API creation"
            fi
        fi
    done <<< "${REPOS}"

    FETCH_COUNT=$((FETCH_COUNT + 1))
    echo "TOTAL_FETCHED SO FAR: ${TOTAL_FETCHED}"
    echo "------------------------------------------------------------------"
done

echo "==> Summary: Fetched ${TOTAL_FETCHED} total repositories. Processed ${MATCHED_COUNT} matching 'rhel9' repositories."