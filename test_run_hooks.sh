#!/bin/bash
# Why: proves run hooks can add arbitrary Docker arguments and replace the startup command.

set -uo pipefail
cd "$(dirname "$0")"

mkdir -p .scratch/tmp
WORKDIR="$(mktemp -d .scratch/tmp/run-hooks-test.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT
mkdir -p "$WORKDIR/repo/hooks.d/run.d" "$WORKDIR/bin" "$WORKDIR/workspace"

cat > "$WORKDIR/repo/pecan.env" <<EOF
PECAN_HOSTNAME=hook-test
PECAN_HOST_DIR=$WORKDIR/workspace
PECAN_WORKSPACE=/workspace
PECAN_VOLUME_NAME=hook-test-state
PECAN_HOME=/home/pecan
PECAN_MEMORY_LIMIT=3g
PECAN_CPU_LIMIT=1.5
PECAN_IMAGE=example/pecan:test
EOF

cat > "$WORKDIR/repo/hooks.d/run.d/10-first.sh" <<'EOF'
pecan_add_run_arg --read-only
pecan_add_run_arg --tmpfs /run:rw,noexec,nosuid,size=16m
pecan_add_run_arg -e FIRST_HOOK=1
EOF
cat > "$WORKDIR/repo/hooks.d/run.d/20-second.sh" <<'EOF'
pecan_add_run_arg -e SECOND_HOOK=1
pecan_set_start_command "/usr/local/bin/custom-start && exec sleep infinity"
EOF
cat > "$WORKDIR/repo/hooks.d/run.d/99-never.sh.stub" <<'EOF'
pecan_add_run_arg -e STUB_RAN=1
EOF

cat > "$WORKDIR/bin/docker" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >> "$DOCKER_ARGS_LOG"
case "$1" in
  ps) exit 0 ;;
  run) printf 'container-id\n'; exit 0 ;;
  exec) exit 0 ;;
esac
EOF
chmod +x "$WORKDIR/bin/docker"

export PECAN_REPO="$WORKDIR/repo"
export PECAN_ENV_FILE="$WORKDIR/repo/pecan.env"
export DOCKER_ARGS_LOG="$WORKDIR/docker-args"
export PATH="$WORKDIR/bin:$PATH"
# shellcheck source=scripts/pecan.sh
. ./scripts/pecan.sh

pecan hooks >/dev/null

fail=0
if pecan >/dev/null 2>&1 || pecan --rm >/dev/null 2>&1; then
  echo "FAIL: missing container names were accepted"
  fail=1
else
  echo "PASS: missing container names return errors under nounset"
fi

assert_arg() {
  if grep -qxF -- "$1" "$DOCKER_ARGS_LOG"; then
    echo "PASS: docker received $1"
  else
    echo "FAIL: docker did not receive $1"
    fail=1
  fi
}
assert_no_arg() {
  if grep -qxF -- "$1" "$DOCKER_ARGS_LOG"; then
    echo "FAIL: docker unexpectedly received $1"
    fail=1
  else
    echo "PASS: docker did not receive $1"
  fi
}

assert_arg --workdir
assert_arg /workspace
assert_arg "$WORKDIR/workspace:/workspace"
assert_arg example/pecan:test
assert_arg --read-only
assert_arg /run:rw,noexec,nosuid,size=16m
assert_arg FIRST_HOOK=1
assert_arg SECOND_HOOK=1
assert_arg "/usr/local/bin/custom-start && exec sleep infinity"
assert_no_arg STUB_RAN=1

: > "$DOCKER_ARGS_LOG"
cat > "$WORKDIR/repo/hooks.d/run.d/15-failing.sh" <<'EOF'
return 23
EOF
if pecan hook-failure >/dev/null 2>&1; then
  echo "FAIL: failed run hook did not abort pecan"
  fail=1
else
  echo "PASS: failed run hook aborted pecan"
fi
if grep -qxF run "$DOCKER_ARGS_LOG"; then
  echo "FAIL: docker run executed after a failed hook"
  fail=1
else
  echo "PASS: docker run was skipped after a failed hook"
fi

if [ "$fail" -ne 0 ]; then
  echo "FAIL: run-hook behavior test failed"
  exit 1
fi

echo "PASS: run hooks preserve arguments, order, workspace, and startup command"
