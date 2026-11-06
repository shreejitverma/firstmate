#!/usr/bin/env bash
# Live contract: every quota provider id firstmate maps a harness to is one the
# installed quota-axi accepts.
#
# Typed dispatch (bin/fm-dispatch-resolve.sh) and the legacy chooser
# (bin/fm-quota-choose.sh) look a harness's quota up by the provider id from
# bin/fm-quota-axi-lib.sh. An id quota-axi never emits matches no row, which
# reads as unknown runway and keeps the harness eligible even when its quota is
# exhausted or its credential is unusable, so the drift is silent everywhere
# except here. muse was mapped to `meta` (its provider family and Keychain
# account) while quota-axi names the provider `muse`.
#
# quota-axi validates --provider before it loads QUOTA_AXI_SNAPSHOT, so pointing
# the snapshot at a missing file answers "is this id supported" with no vendor
# read, no credential access, and no model tokens. The guard is therefore
# default-on wherever quota-axi is installed. Both sides of the discriminator
# are proven first - a sentinel id must be rejected as unsupported and every
# mapped id must not be - so a reworded quota-axi message fails the guard
# instead of passing it vacuously.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fm_live_gate default-on FM_QUOTA_PROVIDER_IDS_LIVE quota-axi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=bin/fm-quota-axi-lib.sh
. "$ROOT/bin/fm-quota-axi-lib.sh"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

ok() {
  printf 'ok - %s\n' "$1"
}

LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-quota-provider-ids.XXXXXX")
trap 'rm -rf "$LAB"' EXIT
MISSING_SNAPSHOT="$LAB/absent-snapshot.json"
QA_VERSION=$(quota-axi --version 2>/dev/null | head -n 1)

# provider_verdict <id>: print unsupported or supported for one provider id.
provider_verdict() {
  local out
  out=$(QUOTA_AXI_SNAPSHOT="$MISSING_SNAPSHOT" quota-axi --provider "$1" --json 2>&1 || true)
  if printf '%s\n' "$out" | grep -F "unsupported provider: $1" >/dev/null; then
    printf 'unsupported\n'
  else
    printf 'supported\n'
  fi
}

[ "$(provider_verdict fm-no-such-provider)" = unsupported ] \
  || fail "quota-axi $QA_VERSION no longer reports a sentinel provider id as unsupported; this guard cannot tell supported ids apart"
ok "quota-axi $QA_VERSION rejects an unknown provider id"

checked=0
while read -r harness provider; do
  [ -n "$harness" ] || continue
  [ "$(provider_verdict "$provider")" = supported ] \
    || fail "single-provider table maps harness $harness to '$provider', which quota-axi $QA_VERSION does not support"
  # A harness the legacy chooser does not cover (agy is resolver-only) has no
  # second mapping to drift; one it does cover must agree with this table.
  if legacy=$(fm_quota_provider_for_harness "$harness"); then
    [ "$legacy" = "$provider" ] \
      || fail "legacy chooser maps harness $harness to '$legacy' but the single-provider table maps it to '$provider'"
  fi
  checked=$((checked + 1))
done < <(fm_quota_single_provider_table)

[ "$checked" -gt 0 ] || fail "single-provider table produced no rows; nothing was checked"
ok "all $checked single-provider harnesses map to quota-axi $QA_VERSION provider ids, and the legacy chooser agrees wherever it covers one"

[ "$(fm_quota_single_provider_for_harness muse)" = muse ] \
  || fail "muse quota is not read from quota-axi's muse provider"
ok "muse quota is read from quota-axi's muse provider"
