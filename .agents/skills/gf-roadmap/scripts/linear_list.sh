#!/usr/bin/env bash
# List Linear issues for the team/project.
#
# Usage:
#   linear_list.sh [state_filter]
#
#   state_filter (optional):
#     all        — all issues (default)
#     open       — Todo + In Progress
#     completed  — Done / Cancelled
#     done       — Done only
#
# Required env vars:
#   LINEAR_API_KEY
#   LINEAR_TEAM_ID
#
# Optional env vars:
#   LINEAR_PROJECT_ID — if set, filters to this project
#
# Output: tab-separated lines: ID  STATE  TITLE  URL

set -euo pipefail

STATE_FILTER="${1:-all}"

if [[ -z "${LINEAR_API_KEY:-}" ]]; then
  echo "ERROR: LINEAR_API_KEY env var not set" >&2
  exit 1
fi
if [[ -z "${LINEAR_TEAM_ID:-}" ]]; then
  echo "ERROR: LINEAR_TEAM_ID env var not set" >&2
  exit 1
fi

# Build optional project filter.
PROJECT_FILTER=""
if [[ -n "${LINEAR_PROJECT_ID:-}" ]]; then
  PROJECT_FILTER=", projectId: { eq: \"${LINEAR_PROJECT_ID}\" }"
fi

# Build state filter condition.
case "$STATE_FILTER" in
  completed|done)
    STATE_CONDITION=', state: { type: { in: ["completed", "cancelled"] } }'
    ;;
  open)
    STATE_CONDITION=', state: { type: { in: ["triage", "backlog", "unstarted", "started"] } }'
    ;;
  *)
    STATE_CONDITION=""
    ;;
esac

QUERY=$(cat <<GRAPHQL
query {
  issues(
    filter: {
      team: { id: { eq: "${LINEAR_TEAM_ID}" } }
      ${PROJECT_FILTER}
      ${STATE_CONDITION}
    }
    orderBy: updatedAt
    first: 100
  ) {
    nodes {
      identifier
      title
      url
      state {
        name
        type
      }
    }
  }
}
GRAPHQL
)

QUERY_COMPACT=$(printf '%s' "$QUERY" | tr '\n' ' ' | sed 's/"/\\"/g')

RESPONSE=$(curl -sS \
  -X POST \
  -H "Authorization: ${LINEAR_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"${QUERY_COMPACT}\"}" \
  "https://api.linear.app/graphql")

if echo "$RESPONSE" | grep -q '"errors"'; then
  echo "ERROR from Linear API:"
  echo "$RESPONSE" | grep -o '"message":"[^"]*"' | head -5
  exit 1
fi

# Parse and print tab-separated output.
# Uses basic string processing (no jq dependency).
echo "$RESPONSE" \
  | grep -o '"identifier":"[^"]*"\|"title":"[^"]*"\|"url":"[^"]*"\|"name":"[^"]*"\|"type":"[^"]*"' \
  | paste - - - - - \
  | awk -F'"' '{
      id=$4; title=$8; url=$12; state_name=$16; state_type=$20;
      printf "%s\t%s (%s)\t%s\t%s\n", id, state_name, state_type, title, url
    }'
