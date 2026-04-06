#!/usr/bin/env bash
# Create a Linear issue via the GraphQL API.
#
# Usage:
#   linear_create.sh "<title>" "<description>" "<label1,label2>"
#
# Required env vars:
#   LINEAR_API_KEY   — API key (lin_api_xxxx)
#   LINEAR_TEAM_ID   — team UUID
#
# Optional env vars:
#   LINEAR_PROJECT_ID — project UUID (issue is added to project if set)
#
# Outputs the created issue ID and URL on success, or an error message.

set -euo pipefail

TITLE="${1:-}"
DESCRIPTION="${2:-}"
LABELS="${3:-}"  # comma-separated label names, optional

if [[ -z "$TITLE" ]]; then
  echo "ERROR: title is required" >&2
  exit 1
fi
if [[ -z "${LINEAR_API_KEY:-}" ]]; then
  echo "ERROR: LINEAR_API_KEY env var not set" >&2
  exit 1
fi
if [[ -z "${LINEAR_TEAM_ID:-}" ]]; then
  echo "ERROR: LINEAR_TEAM_ID env var not set" >&2
  exit 1
fi

# Escape double-quotes and backslashes for JSON embedding.
json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/g' | tr -d '\n' | sed 's/\\n$//'
}

TITLE_ESC=$(json_escape "$TITLE")
DESC_ESC=$(json_escape "$DESCRIPTION")

# Build the projectId fragment conditionally.
PROJECT_FRAGMENT=""
if [[ -n "${LINEAR_PROJECT_ID:-}" ]]; then
  PROJECT_FRAGMENT=", projectId: \"${LINEAR_PROJECT_ID}\""
fi

# Build the mutation. Label IDs would require a lookup step; we skip labels
# here and rely on linear_label_ids.sh for a full workflow. Labels can be
# applied after creation via linear_update.sh.
MUTATION=$(cat <<GRAPHQL
mutation {
  issueCreate(input: {
    title: "$TITLE_ESC",
    description: "$DESC_ESC",
    teamId: "${LINEAR_TEAM_ID}"${PROJECT_FRAGMENT}
  }) {
    success
    issue {
      id
      identifier
      url
    }
  }
}
GRAPHQL
)

# Compact to single line for JSON body.
MUTATION_COMPACT=$(printf '%s' "$MUTATION" | tr '\n' ' ' | sed 's/"/\\"/g')

RESPONSE=$(curl -sS \
  -X POST \
  -H "Authorization: ${LINEAR_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"${MUTATION_COMPACT}\"}" \
  "https://api.linear.app/graphql")

# Check for errors.
if echo "$RESPONSE" | grep -q '"errors"'; then
  echo "ERROR from Linear API:"
  echo "$RESPONSE" | grep -o '"message":"[^"]*"' | head -5
  exit 1
fi

SUCCESS=$(echo "$RESPONSE" | grep -o '"success":[a-z]*' | cut -d: -f2)
if [[ "$SUCCESS" != "true" ]]; then
  echo "ERROR: issueCreate returned success=false"
  echo "$RESPONSE"
  exit 1
fi

ISSUE_ID=$(echo "$RESPONSE" | grep -o '"identifier":"[^"]*"' | cut -d'"' -f4)
ISSUE_URL=$(echo "$RESPONSE" | grep -o '"url":"[^"]*"' | cut -d'"' -f4)

echo "CREATED $ISSUE_ID  $ISSUE_URL"
