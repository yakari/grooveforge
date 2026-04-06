#!/usr/bin/env bash
# Update a Linear issue — change state, title, or description.
#
# Usage:
#   linear_update.sh <issue-id> <field> <value>
#
#   <issue-id>  — Linear internal UUID (not the GF-123 identifier)
#   <field>     — one of: stateId | title | description | priority
#   <value>     — new value
#
#   To find state UUIDs for your team, run:
#     linear_states.sh
#
# Required env vars:
#   LINEAR_API_KEY
#   LINEAR_TEAM_ID

set -euo pipefail

ISSUE_UUID="${1:-}"
FIELD="${2:-}"
VALUE="${3:-}"

if [[ -z "$ISSUE_UUID" || -z "$FIELD" || -z "$VALUE" ]]; then
  echo "Usage: linear_update.sh <issue-uuid> <field> <value>" >&2
  exit 1
fi
if [[ -z "${LINEAR_API_KEY:-}" ]]; then
  echo "ERROR: LINEAR_API_KEY env var not set" >&2
  exit 1
fi

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

VALUE_ESC=$(json_escape "$VALUE")

# Build the input fragment based on field type.
case "$FIELD" in
  stateId|priorityId)
    INPUT_FRAGMENT="${FIELD}: \"${VALUE_ESC}\""
    ;;
  priority)
    # priority is an int (0=no priority, 1=urgent, 2=high, 3=medium, 4=low)
    INPUT_FRAGMENT="priority: ${VALUE}"
    ;;
  title|description)
    INPUT_FRAGMENT="${FIELD}: \"${VALUE_ESC}\""
    ;;
  *)
    echo "ERROR: unknown field '${FIELD}'. Use: stateId, title, description, priority" >&2
    exit 1
    ;;
esac

MUTATION=$(cat <<GRAPHQL
mutation {
  issueUpdate(
    id: "${ISSUE_UUID}",
    input: { ${INPUT_FRAGMENT} }
  ) {
    success
    issue {
      identifier
      title
      state { name }
      url
    }
  }
}
GRAPHQL
)

MUTATION_COMPACT=$(printf '%s' "$MUTATION" | tr '\n' ' ' | sed 's/"/\\"/g')

RESPONSE=$(curl -sS \
  -X POST \
  -H "Authorization: ${LINEAR_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"${MUTATION_COMPACT}\"}" \
  "https://api.linear.app/graphql")

if echo "$RESPONSE" | grep -q '"errors"'; then
  echo "ERROR from Linear API:"
  echo "$RESPONSE" | grep -o '"message":"[^"]*"' | head -5
  exit 1
fi

SUCCESS=$(echo "$RESPONSE" | grep -o '"success":[a-z]*' | cut -d: -f2)
if [[ "$SUCCESS" != "true" ]]; then
  echo "ERROR: issueUpdate returned success=false"
  echo "$RESPONSE"
  exit 1
fi

IDENTIFIER=$(echo "$RESPONSE" | grep -o '"identifier":"[^"]*"' | cut -d'"' -f4)
STATE=$(echo "$RESPONSE" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "UPDATED ${IDENTIFIER} → ${FIELD}=${VALUE} (state: ${STATE})"
