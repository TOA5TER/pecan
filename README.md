# pecan

A reusable Docker sandbox and shell CLI for running the [pi coding agent](https://pi.dev)
(`@earendil-works/pi-coding-agent`) with limited access to the host machine.

pi does not sandbox its own tool execution — its bash tool runs with the invoking
user's full permissions, and pi's own docs recommend containerizing it. pecan is that
container, plus a `pecan` shell function to build and run it.

Every host-specific and org-specific value — hostname, host mount path, volume name,
extra OS packages, resource limits — lives in an external, gitignored config file. No
tracked file in this repo needs editing to adapt pecan to your machine or org.

## Prerequisites

- Docker Engine or Docker Desktop with the Buildx plugin (bundled by default in
  current releases — check with `docker buildx version`).
- `bash` or `zsh`.

## Setup

1. **Source the CLI.** Add this line to `~/.bashrc` or `~/.zshrc`, pointing at wherever
   you cloned this repo:

   ```sh
   source /path/to/pecan/scripts/pecan.sh
   ```

   Open a new shell (or `source` it directly) so the `pecan` function exists.

2. **Create your config.** Copy the tracked template to the gitignored real file and
   edit it:

   ```sh
   cp pecan.env.example pecan.env
   ```

   Set at minimum `PECAN_HOST_DIR` (the host directory to bind-mount as pi's
   workspace) and review the rest — see the comments in `pecan.env.example` for what
   each value controls. `pecan` looks for this file at `<repo>/pecan.env` by default;
   override the repo path with `PECAN_REPO` or the file path directly with
   `PECAN_ENV_FILE` if you keep it elsewhere.

3. **Build the image:**

   ```sh
   pecan --build
   ```

4. **Run it:**

   ```sh
   pecan mywork
   ```

   This creates (or attaches to) a container named `pecan-mywork`, mounts your
   configured host directory, and drops you into a shell where `pi` is on `PATH`.

## Config reference

`pecan.env` (copied from `pecan.env.example`) is sourced directly as trusted shell
code by `scripts/pecan.sh`; do not use a config file from an untrusted source. Its
exported values feed `docker-bake.hcl`, making it the single source of truth for every
externalized value:

| Variable | Used by | Meaning |
|---|---|---|
| `PECAN_HOSTNAME` | `pecan.sh` | Container hostname (`docker run --hostname`). |
| `PECAN_HOST_DIR` | `pecan.sh` | Host directory bind-mounted as pi's workspace. |
| `PECAN_WORKSPACE` | `pecan.sh` | In-container workspace mount target and initial shell working directory. Defaults to `PECAN_HOME` for compatibility. |
| `PECAN_VOLUME_NAME` | `pecan.sh` | Docker named volume persisting pi's agent state, mounted at `PECAN_HOME/.pi/agent`. |
| `PECAN_BASE_IMAGE` | `docker-bake.hcl` | Base image tag for the build. |
| `PECAN_IMAGE` | both | Resulting image tag from Bake and the image used by `docker run`. |
| `PECAN_EXTRA_PACKAGES` | `docker-bake.hcl` | Space-separated extra `apt-get` packages. Quote multi-word values (e.g. `"jq curl"`) — this file is sourced as shell, so an unquoted space starts a new command. |
| `PECAN_USER`, `PECAN_HOME` | both | Non-root username and home directory baked into the image; `PECAN_HOME` is the image's default `WORKDIR`. |
| `PECAN_MEMORY_LIMIT`, `PECAN_CPU_LIMIT` | `pecan.sh` | `docker run --memory` / `--cpus` limits. |

After sourcing, path-like, hostname, image, user, package-list, resource-limit, and
container-name values are restricted to the syntax pecan accepts before reaching Docker.

## CLI reference

| Command | Effect |
|---|---|
| `pecan <name>` | Create (or attach to) container `pecan-<name>`. |
| `pecan -b`, `--build` | Build the image from `docker-bake.hcl` + `pecan.env`. No container. |
| `pecan -l`, `--ls`, `--list` | List running `pecan-*` containers. |
| `pecan --rm <name>` | Kill and remove a container. Refuses if a live exec session is attached. |

## Writing a custom hook

pecan ships two hook directories, each with a tracked, inert example ending in
`.stub`:

- `hooks.d/build.d/00-example.sh.stub` — runs as root during `docker build`, after pi
  and the configured non-root user exist. `PECAN_USER` and `PECAN_HOME` are available
  to the hook. Use it for toolchains, plugins, or user configuration; never bake
  secrets into an image.
- `hooks.d/run.d/00-example.sh.stub` — sourced on the host by `scripts/pecan.sh`
  before `docker run`. Call `pecan_add_run_arg <arg>...` to append any number of
  complete `docker run` arguments. Call `pecan_set_start_command "<shell command>"`
  when runtime initialization must happen before the default keepalive process.
  Environment variables can be forwarded without embedding their values with
  `pecan_add_run_arg -e VARIABLE_NAME`.

To add a real hook, copy the relevant `.stub` file, drop the `.stub` suffix, make it
executable, and edit it. Both directories are gitignored except for the tracked
`.stub` examples, so real hooks never get committed. These ignored files are the
right place for machine- or org-specific toolchains, paths, and identity configuration;
keep secret values in a separate ignored env file and only forward variable names at
runtime. Hooks run in sorted filename order - prefix with a number (`00-`, `10-`, ...)
to control ordering.

## Extending pecan for your org

Today, the path above — real, executable, gitignored files under `hooks.d/build.d/`
and `hooks.d/run.d/` — is the only supported extension mechanism, and it is
local-only: those hooks live on your machine and are never committed to this repo.

The intended future path is a separate, git-tracked overlay repo per org (e.g.
`{yourorg}-pecan`) holding that org's real hooks and a config template, checked out
independently and copied or synchronized into a pecan checkout. That keeps pecan generic
while giving org-specific toolchains and mounts a reviewable home. Keep actual secret
values in a separate ignored env file even in that overlay. Automated overlay wiring
is not yet implemented; for now, use the local `hooks.d/` path above.

## Tests

Run the lightweight shell-script tests from the repo root:

```sh
./test_pecan_env_validation.sh
./test_bake_config.sh
./test_build_hooks_discovery.sh
./test_run_hooks.sh
```

These exercise the real config-validation logic and the real `docker-bake.hcl` /
`scripts/run-hooks.sh` artifacts without requiring a full image build.
