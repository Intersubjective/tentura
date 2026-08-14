#!/usr/bin/env bash
# UNIT 17 — live API walkthrough for availability / request-receptiveness.
# Uses QA witness fixture (Alice/Bob/Carol) plus V2 GraphQL and Hasura reads.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

API="${API_BASE:-http://127.0.0.1:2080}"
HASURA="${HASURA_BASE:-http://127.0.0.1:8080}"
QA_TOKEN="$(grep -E '^QA_AUTH_TOKEN=' .env | cut -d= -f2-)"
RUN_ID="unit17-$(date +%s)"
TMPDIR="${TMPDIR:-/tmp}/unit17-$$"
mkdir -p "$TMPDIR"

log() { printf '\n=== %s ===\n' "$*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

qa_login() {
  local email=$1 jar=$2
  curl -sk -c "$jar" -b "$jar" -X POST "$API/api/v2/auth/email/test-login" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$email\"}" >/dev/null
  local body
  body=$(curl -sk -c "$jar" -b "$jar" -X POST "$API/api/v2/session/access-token")
  python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])' <<<"$body"
}

v2_gql() {
  local jwt=$1 payload=$2
  curl -sk "$API/api/v2/graphql" \
    -H "Authorization: Bearer $jwt" \
    -H 'Content-Type: application/json' \
    -d "$payload"
}

hasura_gql() {
  local jwt=$1 payload=$2
  curl -s "$HASURA/v1/graphql" \
    -H "Authorization: Bearer $jwt" \
    -H 'Content-Type: application/json' \
    -d "$payload"
}

sql_counts() {
  local user_filter=$1
  docker exec postgres psql -U postgres -d postgres -tAc "
SELECT json_build_object(
  'user_updates', (SELECT count(*)::int FROM public.user_updates WHERE user_id IN ($user_filter)),
  'inbox_item', (SELECT count(*)::int FROM public.inbox_item WHERE user_id IN ($user_filter)),
  'notification_outbox', (SELECT count(*)::int FROM public.notification_outbox WHERE actor_user_id IN ($user_filter)),
  'beacon', (SELECT count(*)::int FROM public.beacon WHERE user_id IN ($user_filter)),
  'beacon_forward_edge', (SELECT count(*)::int FROM public.beacon_forward_edge WHERE sender_id IN ($user_filter) OR recipient_id IN ($user_filter)),
  'beacon_help_offer', (SELECT count(*)::int FROM public.beacon_help_offer WHERE user_id IN ($user_filter)),
  'beacon_participant', (SELECT count(*)::int FROM public.beacon_participant WHERE user_id IN ($user_filter)),
  'beacon_room_message', (SELECT count(*)::int FROM public.beacon_room_message WHERE author_id IN ($user_filter)),
  'user_availability', (SELECT count(*)::int FROM public.user_availability WHERE user_id IN ($user_filter))
)::text;"
}

log "Witness fixture runId=$RUN_ID"
FIXTURE=$(curl -sk -X POST "$API/_qa/integration/witness-fixture?_qa_token=$QA_TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"runId\":\"$RUN_ID\"}")
echo "$FIXTURE" | python3 -m json.tool

ALICE_EMAIL=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["aliceEmail"])' <<<"$FIXTURE")
BOB_EMAIL=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["bobEmail"])' <<<"$FIXTURE")
CAROL_EMAIL=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["carolEmail"])' <<<"$FIXTURE")
ALICE_ID=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["aliceUserId"])' <<<"$FIXTURE")
BOB_ID=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["bobUserId"])' <<<"$FIXTURE")
CAROL_ID=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["carolUserId"])' <<<"$FIXTURE")
USER_FILTER="'$ALICE_ID','$BOB_ID','$CAROL_ID'"

ALICE_JAR="$TMPDIR/alice.jar"
BOB_JAR="$TMPDIR/bob.jar"
CAROL_JAR="$TMPDIR/carol.jar"
ALICE_JWT=$(qa_login "$ALICE_EMAIL" "$ALICE_JAR")
BOB_JWT=$(qa_login "$BOB_EMAIL" "$BOB_JAR")
CAROL_JWT=$(qa_login "$CAROL_EMAIL" "$CAROL_JAR")

log "Establish Alice↔Bob mutual visibility (fixture only has one-way Alice→Bob trust)"
v2_gql "$BOB_JWT" "{\"query\":\"mutation { userSubscribe(objectId: \\\"$ALICE_ID\\\") }\"}" | python3 -m json.tool
v2_gql "$ALICE_JWT" "{\"query\":\"mutation { userSubscribe(objectId: \\\"$BOB_ID\\\") }\"}" | python3 -m json.tool

TOMORROW=$(python3 -c 'from datetime import datetime,timedelta,timezone; d=datetime.now(timezone.utc).date()+timedelta(days=7); print(d.isoformat())')
PAUSE_DATE=$(python3 -c 'from datetime import datetime,timedelta,timezone; d=datetime.now(timezone.utc).date()+timedelta(days=14); print(d.isoformat())')

read_profile() {
  local jwt=$1 target=$2 label=$3
  local resp
  resp=$(hasura_gql "$jwt" "{\"query\":\"query { user_by_pk(id: \\\"$target\\\") { id display_name user_availability { is_limited resume_on } } }\"}")
  echo "$label: $resp"
  python3 -c 'import json,sys; d=json.load(sys.stdin); assert "errors" not in d, d; ua=d["data"]["user_by_pk"]["user_availability"]; print("  availability=", ua)' <<<"$resp"
}

read_candidates() {
  local jwt=$1 label=$2
  local resp
  resp=$(hasura_gql "$jwt" '{"query":"query { mutually_visible_users(args: {context: \"\"}) { id display_name user_availability { is_limited resume_on } } }"}')
  echo "$label candidates (subset):"
  RESP="$resp" ALICE_ID="$ALICE_ID" BOB_ID="$BOB_ID" CAROL_ID="$CAROL_ID" python3 <<'PY'
import json, os
data=json.loads(os.environ["RESP"])
ids={
    os.environ["ALICE_ID"]: "alice",
    os.environ["BOB_ID"]: "bob",
    os.environ["CAROL_ID"]: "carol",
}
for row in data.get("data", {}).get("mutually_visible_users", []):
    if row["id"] in ids:
        print(f"  {ids[row['id']]}: {row.get('user_availability')}")
PY
}

capture_counts() {
  sql_counts "$USER_FILTER"
}

snapshot_side_effects() {
  local label=$1
  echo "$label side-effect snapshot:"
  capture_counts
}

MONITORED_KEYS="user_updates inbox_item notification_outbox beacon beacon_forward_edge beacon_help_offer beacon_participant beacon_room_message"

assert_no_side_effects() {
  local before=$1 after=$2 op=$3
  python3 <<PY
import json
b=json.loads('''$before''')
a=json.loads('''$after''')
for k in """$MONITORED_KEYS""".split():
    if b.get(k)!=a.get(k):
        raise SystemExit(f"side effect on {k} during $op: {b.get(k)} -> {a.get(k)}")
print(f"  OK: no side effects on monitored tables for $op")
PY
}

log "Alice creates beacons for forward walkthrough"
CREATE_LIMITED=$(v2_gql "$ALICE_JWT" '{"query":"mutation { beaconCreate(title: \"UNIT17 limited probe\", description: \"limited forward probe\") { id } }"}')
BEACON_LIMITED=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["beaconCreate"]["id"])' <<<"$CREATE_LIMITED")
CREATE_MIXED=$(v2_gql "$ALICE_JWT" '{"query":"mutation { beaconCreate(title: \"UNIT17 mixed batch\", description: \"mixed forward probe\") { id } }"}')
BEACON_MIXED=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["beaconCreate"]["id"])' <<<"$CREATE_MIXED")
echo "beacons: limited=$BEACON_LIMITED mixed=$BEACON_MIXED"

log "1) Carol sets limited; Alice sees label"
BEFORE=$(capture_counts)
echo "before setLimited: $BEFORE"
SET_LIM=$(v2_gql "$CAROL_JWT" '{"query":"mutation { userAvailabilitySetLimited(isLimited: true) }"}')
echo "$SET_LIM" | python3 -m json.tool
AFTER=$(capture_counts)
echo "after setLimited: $AFTER"
assert_no_side_effects "$BEFORE" "$AFTER" "userAvailabilitySetLimited"
read_profile "$ALICE_JWT" "$CAROL_ID" "Alice reads Carol profile (limited)"
python3 -c 'import json,sys; d=json.load(sys.stdin); ua=d["data"]["user_by_pk"]["user_availability"]; assert ua and ua["is_limited"] is True and ua["resume_on"] is None' \
  <<<"$(hasura_gql "$ALICE_JWT" "{\"query\":\"query { user_by_pk(id: \\\"$CAROL_ID\\\") { user_availability { is_limited resume_on } } }\"}")" \
  || fail "Alice should see Carol limited"

log "Alice can still forward to limited Carol (probe forward while limited)"
FWD_LIM=$(v2_gql "$ALICE_JWT" "{\"query\":\"mutation { beaconForward(id: \\\"$BEACON_LIMITED\\\", recipientIds: [\\\"$CAROL_ID\\\"]) { batchId deliveredRecipientIds availabilitySkippedRecipientIds } }\"}")
echo "$FWD_LIM" | python3 -m json.tool
python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]["beaconForward"]; assert d["deliveredRecipientIds"]==["'"$CAROL_ID"'"] and d["availabilitySkippedRecipientIds"]==[]' <<<"$FWD_LIM" \
  || fail "limited Carol should be delivered not skipped"

PRE_EDGE=$(docker exec postgres psql -U postgres -d postgres -tAc "SELECT count(*)::int FROM public.beacon_forward_edge WHERE beacon_id='$BEACON_LIMITED' AND recipient_id='$CAROL_ID' AND cancelled_at IS NULL;")
echo "Carol forward edge count on limited beacon before pause: $PRE_EDGE"

log "2) Carol pauses; Alice sees paused availability on profile and candidates"
BEFORE=$(capture_counts)
echo "before pause: $BEFORE"
PAUSE_RESP=$(v2_gql "$CAROL_JWT" "{\"query\":\"mutation { userAvailabilityPause(resumeOn: \\\"$PAUSE_DATE\\\") }\"}")
echo "$PAUSE_RESP" | python3 -m json.tool
AFTER=$(capture_counts)
echo "after pause: $AFTER"
assert_no_side_effects "$BEFORE" "$AFTER" "userAvailabilityPause"
read_profile "$ALICE_JWT" "$CAROL_ID" "Alice reads Carol profile (paused)"
python3 -c 'import json,sys; d=json.load(sys.stdin); ua=d["data"]["user_by_pk"]["user_availability"]; assert ua and ua["resume_on"]=="'"$PAUSE_DATE"'"' \
  <<<"$(hasura_gql "$ALICE_JWT" "{\"query\":\"query { user_by_pk(id: \\\"$CAROL_ID\\\") { user_availability { is_limited resume_on } } }\"}")" \
  || fail "Alice should see Carol paused with resume_on"
read_candidates "$ALICE_JWT" "Alice"

log "3) Alice forwards Bob+Carol on fresh beacon — delivered Bob, skipped Carol"
MIXED=$(v2_gql "$ALICE_JWT" "{\"query\":\"mutation { beaconForward(id: \\\"$BEACON_MIXED\\\", recipientIds: [\\\"$BOB_ID\\\", \\\"$CAROL_ID\\\"]) { batchId deliveredRecipientIds availabilitySkippedRecipientIds } }\"}")
echo "$MIXED" | python3 -m json.tool
python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]["beaconForward"]; assert d["deliveredRecipientIds"]==["'"$BOB_ID"'"] and d["availabilitySkippedRecipientIds"]==["'"$CAROL_ID"'"]' <<<"$MIXED" \
  || fail "mixed forward delivery mismatch"

POST_EDGE=$(docker exec postgres psql -U postgres -d postgres -tAc "SELECT count(*)::int FROM public.beacon_forward_edge WHERE beacon_id='$BEACON_LIMITED' AND recipient_id='$CAROL_ID' AND cancelled_at IS NULL;")
echo "Carol forward edge count on limited beacon after pause/mixed batch: $POST_EDGE"
[[ "$PRE_EDGE" == "$POST_EDGE" ]] || fail "existing Carol interactions changed by pause"

log "4) Carol resumes — forward-selectable again; limited+paused resumes to limited"
echo "before resume side-effect snapshot:"
BEFORE=$(capture_counts)
RESUME_RESP=$(v2_gql "$CAROL_JWT" '{"query":"mutation { userAvailabilityResume }"}')
echo "$RESUME_RESP" | python3 -m json.tool
AFTER=$(capture_counts)
echo "after resume: $AFTER"
assert_no_side_effects "$BEFORE" "$AFTER" "userAvailabilityResume"
read_profile "$ALICE_JWT" "$CAROL_ID" "Alice reads Carol profile (resumed to limited)"
python3 -c 'import json,sys; d=json.load(sys.stdin); ua=d["data"]["user_by_pk"]["user_availability"]; assert ua and ua["is_limited"] is True and ua["resume_on"] is None' \
  <<<"$(hasura_gql "$ALICE_JWT" "{\"query\":\"query { user_by_pk(id: \\\"$CAROL_ID\\\") { user_availability { is_limited resume_on } } }\"}")" \
  || fail "resume should leave Carol limited not open"

FWD_AFTER_RESUME=$(v2_gql "$ALICE_JWT" "{\"query\":\"mutation { beaconForward(id: \\\"$BEACON_MIXED\\\", recipientIds: [\\\"$CAROL_ID\\\"]) { deliveredRecipientIds availabilitySkippedRecipientIds } }\"}")
python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]["beaconForward"]; assert d["deliveredRecipientIds"]==["'"$CAROL_ID"'"] and d["availabilitySkippedRecipientIds"]==[]' <<<"$FWD_AFTER_RESUME" \
  || fail "Carol should be deliverable after resume"

log "5) Blocked viewer cannot read availability (Alice blocks Carol)"
v2_gql "$ALICE_JWT" "{\"query\":\"mutation { userBlock(objectId: \\\"$CAROL_ID\\\") }\"}" | python3 -m json.tool
BLOCKED_READ=$(hasura_gql "$ALICE_JWT" "{\"query\":\"query { user_by_pk(id: \\\"$CAROL_ID\\\") { user_availability { is_limited resume_on } } }\"}")
echo "Alice blocked read: $BLOCKED_READ"
python3 -c 'import json,sys; d=json.load(sys.stdin); pk=d["data"]["user_by_pk"]; assert pk is None or pk.get("user_availability") is None' <<<"$BLOCKED_READ" \
  || fail "blocked viewer must not read availability"

log "Walkthrough complete — runId=$RUN_ID beacons=$BEACON_LIMITED,$BEACON_MIXED"
echo "TMPDIR=$TMPDIR"
