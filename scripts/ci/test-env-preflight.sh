#!/usr/bin/env bash
# Regression test for scripts/env-preflight.sh (env-drift preflight, ansible-core).
# Hermetic: a temp repo dir + a MOCK `ansible` shim on PATH echoing a chosen version,
# and the audit log pointed at a temp path so tests never touch the real log.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFLIGHT="${SCRIPT_DIR}/../env-preflight.sh"
PASS=0; FAIL=0; FAILURES=()
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL=$((FAIL+1)); FAILURES+=("$1"); }

# Hermetic sandbox.
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

MOCKBIN="${TMPROOT}/mockbin"          # dir holding the ansible shim
AUDIT="${TMPROOT}/env-preflight.log"  # temp audit log
mkdir -p "$MOCKBIN"

# Hermetic "ansible absent" bin: a dedicated dir containing ONLY symlinks to the
# coreutils the script actually needs — and, deliberately, NO ansible. Pointing PATH
# at just this dir makes ansible's absence STRUCTURAL, not host-dependent (the old
# PATH=/usr/bin:/bin was fragile if the host had a system ansible there).
CLEANBIN="${TMPROOT}/cleanbin"
mkdir -p "$CLEANBIN"
for t in bash env grep sed sort date cat head dirname mkdir printf; do
    p="$(command -v "$t" 2>/dev/null)" && [ -n "$p" ] && ln -sf "$p" "${CLEANBIN}/${t}"
done

# Build (or remove) a mock `ansible` that reports a chosen core version.
set_mock_ansible() {
    local version="$1"
    cat > "${MOCKBIN}/ansible" << EOF
#!/usr/bin/env bash
echo "ansible [core ${version}]"
echo "  config file = None"
EOF
    chmod +x "${MOCKBIN}/ansible"
}
remove_mock_ansible() { rm -f "${MOCKBIN}/ansible"; }

# Make a fresh repo dir; echo its path.
make_repo() {
    local d; d="$(mktemp -d "${TMPROOT}/repo.XXXXXX")"
    echo "$d"
}

# Run preflight inside $1 with the mockbin on PATH; capture stdout+exit.
# Sets globals OUT and RC.
run_preflight() {
    local repo="$1"; shift
    OUT="$(cd "$repo" && PATH="${MOCKBIN}:${PATH}" ENV_PREFLIGHT_LOG="$AUDIT" bash "$PREFLIGHT" "$@" 2>&1)"
    RC=$?
}
# Same, but WITHOUT any ansible — PATH points at the coreutils-only CLEANBIN, so
# ansible is structurally absent regardless of what the host has installed.
run_preflight_no_ansible() {
    local repo="$1"; shift
    OUT="$(cd "$repo" && PATH="$CLEANBIN" ENV_PREFLIGHT_LOG="$AUDIT" bash "$PREFLIGHT" "$@" 2>&1)"
    RC=$?
}

# Source env-preflight.sh in a lib-only subshell and invoke a helper directly; return
# the helper's own exit status (subshell isolates its `set -e`).
lib_helper() { bash -c 'export ENV_PREFLIGHT_LIB_ONLY=1; source "$0"; "$@"' "$PREFLIGHT" "$@"; }

echo "--- env-preflight.sh ---"

# (a) PASS when mock live == declared pin.
set_mock_ansible "2.21.0"
r="$(make_repo)"; printf 'ansible-core==2.21.0\n' > "${r}/requirements.txt"
run_preflight "$r"
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '^env-preflight: PASS'; then
    ok "a_pass_match"
else fail "a_pass_match" "rc=$RC out='$OUT'"; fi

# (b) DRIFT + nonzero, direction=local-ahead (live newer than declared).
set_mock_ansible "2.21.0"
r="$(make_repo)"; printf 'ansible-core==2.15.3\n' > "${r}/requirements.txt"
run_preflight "$r"
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'DRIFT' && printf '%s' "$OUT" | grep -q 'local-ahead'; then
    ok "b_drift_local_ahead"
else fail "b_drift_local_ahead" "rc=$RC out='$OUT'"; fi

# (b') DRIFT + nonzero, direction=local-STALE (live older than declared — the
# inverse-trap: local behind, CI right, agent chased a phantom bug).
set_mock_ansible "2.15.3"
r="$(make_repo)"; printf 'ansible-core==2.21.0\n' > "${r}/requirements.txt"
run_preflight "$r"
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'DRIFT' && printf '%s' "$OUT" | grep -q 'local-STALE'; then
    ok "b_drift_local_stale"
else fail "b_drift_local_stale" "rc=$RC out='$OUT'"; fi

# (c) UNVERIFIED + exit 0 + audit-log line when ansible absent.
: > "$AUDIT"
remove_mock_ansible
r="$(make_repo)"; printf 'ansible-core==2.21.0\n' > "${r}/requirements.txt"
run_preflight_no_ansible "$r"
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'UNVERIFIED' && grep -q 'UNVERIFIED' "$AUDIT"; then
    ok "c_unverified_no_ansible_logged"
else fail "c_unverified_no_ansible_logged" "rc=$RC out='$OUT' log='$(cat "$AUDIT" 2>/dev/null)'"; fi

# (d) UNVERIFIED when ansible-repo but no parseable pin (ansible.cfg present, no pin).
set_mock_ansible "2.21.0"
r="$(make_repo)"; : > "${r}/ansible.cfg"; printf 'requests==2.31.0\n' > "${r}/requirements.txt"
run_preflight "$r"
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'UNVERIFIED'; then
    ok "d_unverified_no_pin"
else fail "d_unverified_no_pin" "rc=$RC out='$OUT'"; fi

# (e) non-ansible-repo → no-op exit 0, no drift, no output of substance.
set_mock_ansible "2.21.0"
r="$(make_repo)"; printf 'requests==2.31.0\n' > "${r}/requirements.txt"
run_preflight "$r"
if [ "$RC" -eq 0 ] && ! printf '%s' "$OUT" | grep -q 'DRIFT'; then
    ok "e_non_ansible_noop"
else fail "e_non_ansible_noop" "rc=$RC out='$OUT'"; fi

# (f) the DRIFT-vs-UNVERIFIED boundary: installed + pin present + differ → DRIFT
# (nonzero), NEVER unverified.
set_mock_ansible "2.16.0"
r="$(make_repo)"; printf 'ansible-core==2.21.0\n' > "${r}/requirements.txt"
run_preflight "$r"
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'DRIFT' && ! printf '%s' "$OUT" | grep -q 'UNVERIFIED'; then
    ok "f_boundary_differ_is_drift"
else fail "f_boundary_differ_is_drift" "rc=$RC out='$OUT'"; fi

# (g) >= floor, live ABOVE floor → PASS (THE key regression: local-ahead of a floor is
# COMPLIANT, not drift).
set_mock_ansible "2.21.0"
r="$(make_repo)"; printf 'ansible-core>=2.15\n' > "${r}/requirements.txt"
run_preflight "$r"
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '^env-preflight: PASS'; then
    ok "g_floor_above_is_pass"
else fail "g_floor_above_is_pass" "rc=$RC out='$OUT'"; fi

# (h) >= floor, live BELOW floor → DRIFT (local-STALE), exit 3.
set_mock_ansible "2.14.0"
r="$(make_repo)"; printf 'ansible-core>=2.15\n' > "${r}/requirements.txt"
run_preflight "$r"
if [ "$RC" -eq 3 ] && printf '%s' "$OUT" | grep -q 'DRIFT' && printf '%s' "$OUT" | grep -q 'local-STALE'; then
    ok "h_floor_below_is_drift"
else fail "h_floor_below_is_drift" "rc=$RC out='$OUT'"; fi

# (i) ~= compatible-release, live AT/above floor → PASS.
set_mock_ansible "2.16.4"
r="$(make_repo)"; printf 'ansible-core~=2.16\n' > "${r}/requirements.txt"
run_preflight "$r"
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '^env-preflight: PASS'; then
    ok "i_compat_above_is_pass"
else fail "i_compat_above_is_pass" "rc=$RC out='$OUT'"; fi

# (j) ~= compatible-release, live BELOW floor → DRIFT (local-STALE).
set_mock_ansible "2.15.0"
r="$(make_repo)"; printf 'ansible-core~=2.16\n' > "${r}/requirements.txt"
run_preflight "$r"
if [ "$RC" -eq 3 ] && printf '%s' "$OUT" | grep -q 'DRIFT'; then
    ok "j_compat_below_is_drift"
else fail "j_compat_below_is_drift" "rc=$RC out='$OUT'"; fi

# (k) shape: ==2.21 + live 2.21.0 → PASS (semantic equality, not string equality).
set_mock_ansible "2.21.0"
r="$(make_repo)"; printf 'ansible-core==2.21\n' > "${r}/requirements.txt"
run_preflight "$r"
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '^env-preflight: PASS'; then
    ok "k_semantic_equal_is_pass"
else fail "k_semantic_equal_is_pass" "rc=$RC out='$OUT'"; fi

# (l) wildcard 2.21.* + live 2.21.3 → PASS (within the 2.21. prefix series).
set_mock_ansible "2.21.3"
r="$(make_repo)"; printf 'ansible-core==2.21.*\n' > "${r}/requirements.txt"
run_preflight "$r"
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '^env-preflight: PASS'; then
    ok "l_wildcard_in_series_is_pass"
else fail "l_wildcard_in_series_is_pass" "rc=$RC out='$OUT'"; fi

# (m) wildcard 2.21.* + live 2.22.0 → DRIFT (outside the series).
set_mock_ansible "2.22.0"
r="$(make_repo)"; printf 'ansible-core==2.21.*\n' > "${r}/requirements.txt"
run_preflight "$r"
if [ "$RC" -eq 3 ] && printf '%s' "$OUT" | grep -q 'DRIFT'; then
    ok "m_wildcard_out_of_series_is_drift"
else fail "m_wildcard_out_of_series_is_drift" "rc=$RC out='$OUT'"; fi

# (n) direct asserts on the ver_ge / ver_eq helpers.
if lib_helper ver_ge 2.21.0 2.15; then ok "n_ver_ge_above_true"
else fail "n_ver_ge_above_true" "ver_ge 2.21.0 2.15 returned false"; fi

if lib_helper ver_eq 2.21 2.21.0; then ok "n_ver_eq_shape_true"
else fail "n_ver_eq_shape_true" "ver_eq 2.21 2.21.0 returned false"; fi

if ! lib_helper ver_ge 2.15 2.21; then ok "n_ver_ge_below_false"
else fail "n_ver_ge_below_false" "ver_ge 2.15 2.21 returned true"; fi

echo ""
TOTAL=$((PASS+FAIL))
if [ "$FAIL" -eq 0 ]; then
    echo "PASS — ${TOTAL} tests run, ${PASS} passed, 0 failed"; exit 0
else
    echo "FAIL — ${TOTAL} tests run, ${PASS} passed, ${FAIL} failed"
    printf '  - %s\n' "${FAILURES[@]}"; exit 1
fi
