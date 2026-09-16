#!/bin/bash
# Why: guards against command injection into docker run/bake via a malicious or mistyped pecan.env value.

set -uo pipefail
cd "$(dirname "$0")"

echo "Testing scripts/pecan.sh config-value validation..."

# shellcheck source=scripts/pecan.sh
. ./scripts/pecan.sh

fail=0

assert_valid() {
  if _pecan_validate "$1"; then
    echo "PASS: '$1' accepted"
  else
    echo "FAIL: '$1' should have been accepted"
    fail=1
  fi
}

assert_invalid() {
  if _pecan_validate "$1"; then
    echo "FAIL: '$1' should have been rejected"
    fail=1
  else
    echo "PASS: '$1' rejected"
  fi
}

assert_valid "/Users/example/projects"
assert_valid "pecan-host"
assert_valid "pecan.local"
assert_valid ""

assert_invalid "/Users/example; rm -rf /"
assert_invalid '$(whoami)'
assert_invalid "host\`id\`"
assert_invalid "path with spaces"
assert_invalid "pipe|here"
assert_invalid "amp&here"
assert_invalid "redirect>here"

assert_packages_valid() {
  if _pecan_validate_packages "$1"; then
    echo "PASS: package list '$1' accepted"
  else
    echo "FAIL: package list '$1' should have been accepted"
    fail=1
  fi
}

assert_packages_invalid() {
  if _pecan_validate_packages "$1"; then
    echo "FAIL: package list '$1' should have been rejected"
    fail=1
  else
    echo "PASS: package list '$1' rejected"
  fi
}

assert_packages_valid ""
assert_packages_valid "jq curl"
assert_packages_valid "libssl-dev python3.11 adb:amd64 g++"
assert_packages_invalid "jq  curl"
assert_packages_invalid "--allow-unauthenticated jq"
assert_packages_invalid "jq;id"
assert_packages_invalid 'jq $(id)'
assert_packages_invalid "jq/curl"
assert_packages_invalid "jq
curl"

if _pecan_validate_user "pecan-user_1" && ! _pecan_validate_user "1pecan" \
  && ! _pecan_validate_user "pecan/user" && ! _pecan_validate_user "pecan
root"; then
  echo "PASS: container usernames use Dockerfile-compatible syntax"
else
  echo "FAIL: container username validation mismatch"
  fail=1
fi

if _pecan_validate_name "pecan-work_1.2" && ! _pecan_validate_name "pecan-.*" \
  && ! _pecan_validate_name "pecan-work
pecan-other"; then
  echo "PASS: container names use literal Docker-compatible syntax"
else
  echo "FAIL: container name validation mismatch"
  fail=1
fi

if _pecan_validate_image "registry.example/pecan:test" \
  && _pecan_validate_image "registry.example/pecan@sha256:abc123" \
  && ! _pecan_validate_image "--privileged" && ! _pecan_validate_image "pecan:test
--privileged"; then
  echo "PASS: image references cannot inject docker run options"
else
  echo "FAIL: image reference validation mismatch"
  fail=1
fi

if _pecan_validate_home "/home/pecan" && ! _pecan_validate_home "/home/pecan
/root" \
  && ! _pecan_validate_home "relative/home"; then
  echo "PASS: container homes use Dockerfile-compatible absolute paths"
else
  echo "FAIL: container home validation mismatch"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "❌ pecan.env validation test failed"
  exit 1
fi

echo "✅ pecan.env validation rejects shell metacharacters correctly"
