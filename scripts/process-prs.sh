        #!/usr/bin/env bash

        # Cleanup temporary files on exit
        trap 'rm -f pr_list.json extracted_prs.txt' EXIT

        STATUS_CODE_FAILED=101
        STATUS_CODE_PENDING=102
        STATUS_CODE_SUCCESS=200

        function list_prs(){
          ORG="openshift-pipelines"
          SEARCH_LABEL="hack,upstream"
          BASE_BRANCH=$1

          # Search for PRs and save to JSON
          gh search prs --owner "$ORG" \
          --base "$BASE_BRANCH" \
          --state open \
          --json repository,url \
          "label:$SEARCH_LABEL" > pr_list.json
        }


        function process_pr() {
          URL=$1
          echo "Processing PR $URL"
          PR_DATA=$(gh pr view "$URL" --json mergeable,mergeStateStatus)
          MERGEABLE=$(echo "$PR_DATA" | jq -r '.mergeable')
          MERGE_STATE=$(echo "$PR_DATA" | jq -r '.mergeStateStatus')

          echo "$PR_DATA" | jq

            # --- SCENARIO 1: MERGE CONFLICTS ---
            if [[ "$MERGEABLE" == "CONFLICTING" || "$MERGE_STATE" == "DIRTY" ]]; then
              echo "⚠️ SKIP: PR has merge conflicts."
              return $STATUS_CODE_FAILED
            fi

            # --- SCENARIO 2: REBASE / OUT-OF-DATE ISSUE ---
            if [[ "$MERGE_STATE" == "BEHIND" ]]; then
              echo "⚠️ PR is behind the base branch."
              echo "Attempting to update branch..."
              if ! gh pr update-branch "$URL" --rebase ; then
                echo "❌ SKIP: Failed to REBASE branch automatically."
                return $STATUS_CODE_FAILED
              fi
              return $STATUS_CODE_PENDING
            fi
            # --- SCENARIO 3: CHECK AND CREATE MISSING LABELS ---
            IFS=',' read -ra LABEL_ARRAY <<< "$LABELS_TO_ADD"
            for LABEL in "${LABEL_ARRAY[@]}"; do
              LABEL=$(echo "$LABEL" | xargs)
              LABEL_EXISTS=$(gh label list --repo "$REPO_NAME" --search "$LABEL" --json name -q ".[] | select(.name == \"$LABEL\") | .name")

              if [[ -z "$LABEL_EXISTS" ]]; then
                gh label create "$LABEL" --repo "$REPO_NAME" --color "0E8A16" --description "Auto-created by pipeline"
              fi
            done
            gh pr edit "$URL" --add-label "$LABELS_TO_ADD"

            # --- SCENARIO 4: WORKFLOWS FAILING/PENDING ---
            echo "⏳ Checking PR workflows..."
            CHECKS_JSON=$(gh pr checks "$URL" --json name,bucket,link  | jq -r '.[]
              | select(.name | test("pull"))
              | select (.bucket=="pending" or .bucket =="fail")' 2>&1 \
              | grep -v "no checks reported" || true)
            if [[ -n "$CHECKS_JSON" ]]; then
              FAILING_COUNT=$(echo "$CHECKS_JSON" | jq '[.[] | select(.bucket == "fail")] | length')
              if [[ "$FAILING_COUNT" -gt 0 ]]; then
                echo "❌ SKIP: PR already has $FAILING_COUNT failing workflow(s)."
                gh pr comment $URL --body "/retest"
                return $STATUS_CODE_FAILED
              fi
            fi

            PENDING_COUNT=$(echo "$CHECKS_JSON" | jq '[.[] | select(.bucket == "pending")] | length')
            if [[ "$PENDING_COUNT" -gt 0 ]]; then
              echo "⏳ SKIP: PR has $PENDING_COUNT pending workflow(s)."
              return $STATUS_CODE_PENDING
            fi

            # --- SCENARIO 5: Merge PRs ---
            echo "🚢 Merging PR..."
            gh pr review --approve "$URL"
            gh pr merge "$URL" -d -r --auto || true  #FIXME  Handle the scneario when merging fails
            return $STATUS_CODE_SUCCESS
        }

        function main () {
          RELEASE=$1
          LABELS_TO_ADD="lgtm,approved,release-pipeline"
          BASE_BRANCH="release-v$RELEASE.x"
          list_prs $BASE_BRANCH

          PR_JSON=$(cat pr_list.json)
          echo "Extracting PRs from JSON..."

          # 2. Extract REPO_NAME (needed for checking labels) and URL (used for all PR actions)
          echo "$PR_JSON" | jq -r '.[] | "\(.url)"' > extracted_prs.txt

          declare -a FAILING_PRS=()
          declare -a SUCCESS_PRS=()
          declare -a PENDING_PRS=()

          while read -r URL; do
            echo "------------------------------------------------"
            echo "🚀 Processing PR: $URL"
            process_pr $URL
            local STATUS=$?
            echo "STATUS : $STATUS"
            case $STATUS in
              $STATUS_CODE_FAILED) FAILING_PRS+=("$URL") ;;
              $STATUS_CODE_PENDING) PENDING_PRS+=("$URL") ;;
              $STATUS_CODE_SUCCESS) SUCCESS_PRS+=("$URL") ;;
            esac
          done < extracted_prs.txt

          # ==============================================================================
            # --- RETRY PENDING PRS (1 Hour Limit, 1 Min Interval) ---
            # ==============================================================================

            local MAX_RETRIES=60
            local RETRY_COUNT=0
            local SLEEP_INTERVAL=60

            while [[ ${#PENDING_PRS[@]} -gt 0 && $RETRY_COUNT -lt $MAX_RETRIES ]]; do
              ((RETRY_COUNT++))
              echo ""
              echo "================================================"
              echo "⏳ Retry loop $RETRY_COUNT/$MAX_RETRIES. Sleeping for ${SLEEP_INTERVAL}s..."
              echo "================================================"
              sleep "$SLEEP_INTERVAL"

              # Temporary array to hold PRs that remain pending during this iteration
              local STILL_PENDING_PRS=()

              for URL in "${PENDING_PRS[@]}"; do
                echo "------------------------------------------------"
                echo "🔄 Retrying PR: $URL"

                set +e
                process_pr "$URL"
                local STATUS=$?
                set -e

                case $STATUS in
                  $STATUS_CODE_FAILED) FAILING_PRS+=("$URL") ;;
                  $STATUS_CODE_PENDING) STILL_PENDING_PRS+=("$URL") ;;
                  $STATUS_CODE_SUCCESS) SUCCESS_PRS+=("$URL") ;;
                esac
              done

              # Overwrite the pending array with the ones that are STILL pending
              PENDING_PRS=("${STILL_PENDING_PRS[@]}")
            done

          # ==============================================================================
          # --- FINAL SUMMARY ---
          # ==============================================================================

          echo ""
          echo "================================================"
          echo "✅ Pipeline Complete!"
          echo "================================================"
          echo "✅ Successful PRs: ${SUCCESS_PRS[*]}"
          echo "❌ Failed PRs:     ${FAILING_PRS[*]}"
          if [[ ${#PENDING_PRS[@]} -gt 0 ]]; then
            echo "⏳ Pending PRs:    ${PENDING_PRS[*]}"
          fi

        }

        main "$@"
