#!/usr/bin/env bash
# Explain recent Conan download blocks using Curation audit events and policy definitions.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${ROOT}/env.local.sh" ]]; then
    source "${ROOT}/env.local.sh"
fi

usage() {
    echo "Usage: $0 [--json] [package_name [package_version]]" >&2
    echo "Requires JFROG_SERVER_ID and CONAN_CURATED_REMOTE_REPO (the remote key, not the virtual key)." >&2
}

JSON=false
if [[ "${1:-}" == "--json" ]]; then
    JSON=true
    shift
fi
if (( $# > 2 )) || [[ "${1:-}" == --* ]] || [[ "${2:-}" == --* ]]; then
    usage
    exit 2
fi

: "${JFROG_SERVER_ID:?Set JFROG_SERVER_ID to a configured JFrog CLI server ID.}"
: "${CONAN_CURATED_REMOTE_REPO:?Set CONAN_CURATED_REMOTE_REPO to the Curation-connected Conan remote repository key.}"
for command in jf jq; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Required command not found: $command" >&2
        exit 1
    fi
done

PACKAGE="${1:-}"
VERSION="${2:-}"
urlencode() { jq -nr --arg value "$1" '$value | @uri'; }

QUERY='order_by=id&direction=desc&num_of_rows=20&offset=0&include_total=true&action=blocked&package_type=Conan'
QUERY+="&curated_repository_name=$(urlencode "$CONAN_CURATED_REMOTE_REPO")"
if [[ -n "$PACKAGE" ]]; then
    QUERY+="&package_name=$(urlencode "$PACKAGE")"
fi
if [[ -n "$VERSION" ]]; then
    QUERY+="&package_version=$(urlencode "$VERSION")"
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/conan-curation-audit.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
EVENTS="$WORK/events.json"
POLICIES="$WORK/policies.ndjson"
: > "$POLICIES"

if ! jf api --server-id "$JFROG_SERVER_ID" "/xray/api/v1/curation/audit/packages?$QUERY" > "$EVENTS"; then
    echo "Could not read Curation Downloads audit events from JFrog server '$JFROG_SERVER_ID'." >&2
    exit 1
fi
if ! jq -e 'has("data") and (.data == null or (.data | type == "array"))' "$EVENTS" >/dev/null; then
    echo "Unexpected Curation audit response: invalid data field." >&2
    exit 1
fi

while IFS= read -r policy_id; do
    [[ "$policy_id" =~ ^[0-9]+$ ]] || continue
    if jf api --server-id "$JFROG_SERVER_ID" "/xray/api/v1/curation/policies/$policy_id" > "$WORK/policy.json"; then
        if jq -e 'type == "object" and (.id != null)' "$WORK/policy.json" >/dev/null; then
            jq -c . "$WORK/policy.json" >> "$POLICIES"
        else
            jq -cn --arg id "$policy_id" '{id:$id, lookup_error:"Unexpected policy response"}' >> "$POLICIES"
        fi
    else
        echo "Could not read current definition of policy $policy_id; showing the recorded event only." >&2
        jq -cn --arg id "$policy_id" '{id:$id, lookup_error:"Policy definition unavailable"}' >> "$POLICIES"
    fi
done < <(jq -r '[(.data // [])[]?.policies[]?.policy_id | select(. != null) | tostring] | unique[]' "$EVENTS")

jq -n \
    --slurpfile audit "$EVENTS" \
    --slurpfile policies "$POLICIES" \
    --arg repo "$CONAN_CURATED_REMOTE_REPO" \
    --arg package "$PACKAGE" \
    --arg version "$VERSION" '
    ($policies | map({key:(.id | tostring), value:.}) | from_entries) as $definitions
    | {
        filter: {package_type:"Conan", curated_repository_name:$repo, action:"blocked", package_name:$package, package_version:$version},
        total_count: ($audit[0].meta.total_count // null),
        returned_count: (($audit[0].data // []) | length),
        events: [ ($audit[0].data // [])[] | {
            id, created_at, action, package_name, package_version,
            curated_repository_name, reason,
            policies: [ .policies[]? | . as $recorded
                | ($definitions[($recorded.policy_id | tostring)] // {}) as $current
                | {
                    policy_id: $recorded.policy_id,
                    policy_name: $recorded.policy_name,
                    result: $recorded.result,
                    condition_name: $recorded.condition_name,
                    condition_category: $recorded.condition_category,
                    current_policy: (if $current == {} then null else {
                        name: $current.name,
                        updated_at: $current.updated_at,
                        enabled: $current.enabled,
                        policy_action: $current.policy_action,
                        condition_template_id: $current.condition.condition_template_id,
                        condition_parameters: $current.condition.param_values,
                        lookup_error: $current.lookup_error
                    } end)
                }
            ]
        } ]
    }
' > "$WORK/report.json"

if [[ "$JSON" == true ]]; then
    cat "$WORK/report.json"
else
    jq -r '
        "Blocked Conan download events: \(.returned_count) shown / \(.total_count // "unknown") matching in the last 7 days (latest first)",
        "Curated remote: \(.filter.curated_repository_name)",
        (if .events == [] then
            "No matching block event. Check the remote key, audit time window, Curation connection, and policy scope; absence is not approval."
        else
            (.events[] |
                "\nEvent #\(.id) | \(.created_at) | \(.package_name)/\(.package_version)",
                "  Reason: \(.reason // "not supplied")",
                (.policies[]? |
                    "  Policy: \(.policy_name) (#\(.policy_id)) — \(.result // "result not supplied")",
                    "    Condition at event: \(.condition_name) [\(.condition_category // "category not supplied")]",
                    (if .current_policy == null then empty
                     elif .current_policy.lookup_error then "    Current definition: \(.current_policy.lookup_error)"
                     else
                        "    Current rule: \(.current_policy.condition_template_id // "not supplied")" +
                        (if (.current_policy.condition_parameters // []) == [] then ""
                         else " (" + ([.current_policy.condition_parameters[] | "\(.param_id)=\(.value)"] | join(", ")) + ")" end),
                        "    Policy last updated: \(.current_policy.updated_at // "not supplied")"
                     end)
                )
            )
        end)
    ' "$WORK/report.json"
fi
