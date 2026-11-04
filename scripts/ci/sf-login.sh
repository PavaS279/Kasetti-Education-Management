#!/usr/bin/env bash
# Authorizes the Salesforce CLI against an org using the OAuth 2.0 client credentials flow.
# Needs no browser and no local machine, so it works in GitHub Actions and cloud sessions.
#
# Required environment variables:
#   SF_INSTANCE_URL   My Domain URL, e.g. https://kasetti.my.salesforce.com
#   SF_CLIENT_ID      Consumer key of the External Client App
#   SF_CLIENT_SECRET  Consumer secret of the External Client App
# Optional:
#   SF_ORG_ALIAS      Alias for the authorized org (default: edu-org)
set -euo pipefail

: "${SF_INSTANCE_URL:?SF_INSTANCE_URL is not set}"
: "${SF_CLIENT_ID:?SF_CLIENT_ID is not set}"
: "${SF_CLIENT_SECRET:?SF_CLIENT_SECRET is not set}"
instance_url="${SF_INSTANCE_URL%/}"
alias_name="${SF_ORG_ALIAS:-edu-org}"

if ! token_json=$(curl -sS --fail-with-body -X POST "${instance_url}/services/oauth2/token" \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "client_id=${SF_CLIENT_ID}" \
  --data-urlencode "client_secret=${SF_CLIENT_SECRET}"); then
  echo "Token request to ${instance_url} failed: ${token_json}" >&2
  exit 1
fi

access_token=$(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(0, "utf8")).access_token || "")' <<<"$token_json")
if [[ -z "$access_token" ]]; then
  echo "Token response did not include an access_token." >&2
  exit 1
fi
if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  echo "::add-mask::${access_token}"
fi

SF_ACCESS_TOKEN="$access_token" sf org login access-token \
  --instance-url "$instance_url" \
  --alias "$alias_name" \
  --set-default \
  --no-prompt
