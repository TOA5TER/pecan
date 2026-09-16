# pecan - sourced shell function to build/run the pi sandbox container; see README.md.

# Rejects scalar config values containing shell metacharacters; empty values pass.
_pecan_validate() {
  case "$1" in
    "")
      return 0
      ;;
    *[!A-Za-z0-9/_.:-]*)
      echo "Error: value '$1' contains disallowed characters." >&2
      return 1
      ;;
  esac
  return 0
}

_pecan_validate_user() {
  if [ "$(printf '%s' "$1" | wc -l | tr -d ' ')" -ne 0 ] \
    || ! printf '%s\n' "$1" | grep -Eq '^[A-Za-z_][A-Za-z0-9_-]*$'; then
    echo "Error: user '$1' is not a valid container username." >&2
    return 1
  fi
  return 0
}

_pecan_validate_name() {
  if [ "$(printf '%s' "$1" | wc -l | tr -d ' ')" -ne 0 ] \
    || ! printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9_.-]*$'; then
    echo "Error: name '$1' is not a valid container name." >&2
    return 1
  fi
  return 0
}

_pecan_validate_image() {
  if [ "$(printf '%s' "$1" | wc -l | tr -d ' ')" -ne 0 ] \
    || ! printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9/@_.:-]*$'; then
    echo "Error: image '$1' is not a valid image reference." >&2
    return 1
  fi
  return 0
}

_pecan_validate_home() {
  if [ "$(printf '%s' "$1" | wc -l | tr -d ' ')" -ne 0 ] \
    || ! printf '%s\n' "$1" | grep -Eq '^/[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$'; then
    echo "Error: home '$1' is not a valid absolute container path." >&2
    return 1
  fi
  return 0
}

# Accepts only space-separated Debian package names, never apt options or shell syntax.
_pecan_validate_packages() {
  [ -z "$1" ] && return 0
  if [ "$(printf '%s' "$1" | wc -l | tr -d ' ')" -ne 0 ] \
    || ! printf '%s\n' "$1" | grep -Eq '^([A-Za-z0-9][A-Za-z0-9+_.:-]*)( [A-Za-z0-9][A-Za-z0-9+_.:-]*)*$'; then
    echo "Error: package list '$1' must contain only space-separated Debian package names." >&2
    return 1
  fi
  return 0
}

pecan() {
  local repo="${PECAN_REPO:-$HOME/projects/pecan}"
  local env_file="${PECAN_ENV_FILE:-$repo/pecan.env}"

  case "${1:-}" in
    -b|--build)
      if [ ! -f "$env_file" ]; then
        echo "Error: pecan config '$env_file' not found. Copy pecan.env.example to pecan.env and edit it." >&2
        return 1
      fi
      . "$env_file"
      : "${PECAN_BASE_IMAGE:=node:24-bookworm-slim}"
      : "${PECAN_EXTRA_PACKAGES:=}"
      : "${PECAN_USER:=pecan}"
      : "${PECAN_HOME:=/home/pecan}"
      : "${PECAN_IMAGE:=pecan:latest}"
      if ! _pecan_validate_image "$PECAN_BASE_IMAGE" || ! _pecan_validate_packages "$PECAN_EXTRA_PACKAGES" \
        || ! _pecan_validate_user "$PECAN_USER" || ! _pecan_validate_home "$PECAN_HOME" \
        || ! _pecan_validate_image "$PECAN_IMAGE"; then
        return 1
      fi
      export PECAN_BASE_IMAGE PECAN_EXTRA_PACKAGES PECAN_USER PECAN_HOME PECAN_IMAGE
      (cd "$repo" && docker buildx bake -f docker-bake.hcl pecan)
      return
      ;;
    -l|--ls|--list)
      local running
      running="$(docker ps --format '{{.Names}}' | grep '^pecan-')"
      if [ -z "$running" ]; then
        echo "No pecan containers running."
        return
      fi
      echo "$running" | sed 's/^pecan-//'
      return
      ;;
    --rm)
      local target="${2:-}"
      if [ -z "$target" ]; then
        echo "Error: --rm requires a container name." >&2
        return 1
      fi
      case "$target" in
        pecan-*) : ;;
        *) target="pecan-$target" ;;
      esac
      if ! _pecan_validate_name "$target"; then
        return 1
      fi
      if ! docker ps --format '{{.Names}}' | grep -qxF "$target"; then
        echo "Error: no running container named '$target'." >&2
        return 1
      fi
      local sock eid attached
      attached=0
      sock="$(docker context inspect -f '{{.Endpoints.docker.Host}}' 2>/dev/null | sed 's|^unix://||')"
      if [ -n "$sock" ]; then
        for eid in $(docker inspect -f '{{range .ExecIDs}}{{println .}}{{end}}' "$target" 2>/dev/null); do
          [ -z "$eid" ] && continue
          case "$(curl -s --unix-socket "$sock" "http://localhost/exec/$eid/json" 2>/dev/null)" in
            *'"Running":true'*)
              attached=1
              break
              ;;
          esac
        done
      else
        docker top "$target" -o pid,comm 2>/dev/null | grep -qw bash && attached=1
      fi
      if [ "$attached" = "1" ]; then
        echo "Error: '$target' has a live exec session. Detach before removing." >&2
        return 1
      fi
      docker kill "$target"
      return
      ;;
    "")
      echo "Error: container name required." >&2
      echo "Usage: pecan <name> | -b/--build | -l/--ls/--list | --rm <name>" >&2
      return 1
      ;;
    -*)
      echo "Error: unknown flag '$1'." >&2
      echo "Usage: pecan <name> | -b/--build | -l/--ls/--list | --rm <name>" >&2
      return 1
      ;;
  esac

  local container_name="pecan-$1"
  if ! _pecan_validate_name "$container_name"; then
    return 1
  fi

  if docker ps --format '{{.Names}}' | grep -qxF "$container_name"; then
    echo "Container '$container_name' already exists - attaching."
    docker exec -it "$container_name" bash
    return
  fi

  if [ ! -f "$env_file" ]; then
    echo "Error: pecan config '$env_file' not found. Copy pecan.env.example to pecan.env and edit it." >&2
    return 1
  fi
  . "$env_file"
  : "${PECAN_HOSTNAME:=pecan}"
  : "${PECAN_HOME:=/home/pecan}"
  : "${PECAN_WORKSPACE:=$PECAN_HOME}"
  : "${PECAN_IMAGE:=pecan:latest}"
  : "${PECAN_MEMORY_LIMIT:=4g}"
  : "${PECAN_CPU_LIMIT:=2}"
  : "${PECAN_HOST_DIR:=}"
  : "${PECAN_VOLUME_NAME:=}"

  if ! _pecan_validate "$PECAN_HOSTNAME" || ! _pecan_validate "$PECAN_HOST_DIR" \
    || ! _pecan_validate_home "$PECAN_HOME" || ! _pecan_validate "$PECAN_WORKSPACE" \
    || ! _pecan_validate "$PECAN_VOLUME_NAME" || ! _pecan_validate "$PECAN_MEMORY_LIMIT" \
    || ! _pecan_validate "$PECAN_CPU_LIMIT" || ! _pecan_validate_image "$PECAN_IMAGE"; then
    return 1
  fi

  if [ -z "$PECAN_HOST_DIR" ] || [ -z "$PECAN_HOME" ] || [ -z "$PECAN_WORKSPACE" ] \
    || [ -z "$PECAN_VOLUME_NAME" ]; then
    echo "Error: pecan.env is missing a required value (PECAN_HOST_DIR, PECAN_HOME, PECAN_WORKSPACE, PECAN_VOLUME_NAME)." >&2
    return 1
  fi

  # Sourced run hooks append Docker arguments and may replace the keepalive command.
  local PECAN_EXTRA_RUN_ARGS=()
  local PECAN_START_COMMAND="sleep infinity"
  pecan_add_run_arg() { PECAN_EXTRA_RUN_ARGS+=("$@"); }
  pecan_set_start_command() { PECAN_START_COMMAND="$1"; }

  # Avoid zsh's empty-glob failure while keeping hook mutations in this shell.
  local hook
  while IFS= read -r hook; do
    if ! . "$hook"; then
      echo "Error: run hook '$hook' failed." >&2
      return 1
    fi
  done < <(find "$repo/hooks.d/run.d" -maxdepth 1 -type f -name '*.sh' 2>/dev/null | sort)

  echo "Container '$container_name' is new - creating."
  docker run --rm -d --name "$container_name" \
    --hostname "$PECAN_HOSTNAME" \
    --memory="${PECAN_MEMORY_LIMIT:-4g}" \
    --cpus="${PECAN_CPU_LIMIT:-2}" \
    --workdir "$PECAN_WORKSPACE" \
    -v "$PECAN_HOST_DIR:$PECAN_WORKSPACE" \
    -v "$PECAN_VOLUME_NAME:$PECAN_HOME/.pi/agent" \
    "${PECAN_EXTRA_RUN_ARGS[@]}" \
    --entrypoint sh \
    "$PECAN_IMAGE" \
    -c "$PECAN_START_COMMAND"

  docker exec -it "$container_name" bash
  return
}
