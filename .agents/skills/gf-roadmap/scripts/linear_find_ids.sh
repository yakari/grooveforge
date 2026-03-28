#!/usr/bin/env bash
# Discover Linear team IDs, project IDs, and workflow state IDs.
# Run this once to find the values to put in your env vars.
#
# Usage:
#   bash .agents/skills/gf-roadmap/scripts/linear_find_ids.sh
#
# Required env vars:
#   LINEAR_API_KEY  — your Linear API key (lin_api_xxxx)
#
# Get your API key at: https://linear.app/settings/api

set -euo pipefail

if [[ -z "${LINEAR_API_KEY:-}" ]]; then
  echo "ERROR: LINEAR_API_KEY env var not set." >&2
  echo "Set it in .claude/settings.local.json under 'env', or export it in your shell." >&2
  exit 1
fi

echo "=== Teams ==="
TEAMS_QUERY='query { teams { nodes { id name key } } }'
TEAMS_COMPACT=$(printf '%s' "$TEAMS_QUERY" | sed 's/"/\\"/g')

curl -sS \
  -X POST \
  -H "Authorization: ${LINEAR_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"${TEAMS_COMPACT}\"}" \
  "https://api.linear.app/graphql" \
  | grep -o '"id":"[^"]*"\|"name":"[^"]*"\|"key":"[^"]*"' \
  | paste - - - \
  | awk -F'"' '{ printf "  Team %-20s  key=%-8s  id=%s\n", $8, $12, $4 }'

echo ""
echo "=== Projects ==="
PROJECTS_QUERY='query { projects(first: 50) { nodes { id name } } }'
PROJECTS_COMPACT=$(printf '%s' "$PROJECTS_QUERY" | sed 's/"/\\"/g')

curl -sS \
  -X POST \
  -H "Authorization: ${LINEAR_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"${PROJECTS_COMPACT}\"}" \
  "https://api.linear.app/graphql" \
  | grep -o '"id":"[^"]*"\|"name":"[^"]*"' \
  | paste - - \
  | awk -F'"' '{ printf "  Project %-30s  id=%s\n", $8, $4 }'

echo ""
echo "=== Workflow States (first team) ==="
STATES_QUERY='query { workflowStates(first: 50) { nodes { id name type team { name } } } }'
STATES_COMPACT=$(printf '%s' "$STATES_QUERY" | sed 's/"/\\"/g')

curl -sS \
  -X POST \
  -H "Authorization: ${LINEAR_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"${STATES_COMPACT}\"}" \
  "https://api.linear.app/graphql" \
  | grep -o '"id":"[^"]*"\|"name":"[^"]*"\|"type":"[^"]*"' \
  | paste - - - \
  | awk -F'"' '{ printf "  State %-20s  type=%-12s  id=%s\n", $8, $12, $4 }'

echo ""
echo "Put these in .claude/settings.local.json:"
echo '{'
echo '  "env": {'
echo '    "LINEAR_API_KEY": "lin_api_xxxx",'
echo '    "LINEAR_TEAM_ID": "<team id from above>",'
echo '    "LINEAR_PROJECT_ID": "<project id from above>"'
echo '  }'
echo '}'
