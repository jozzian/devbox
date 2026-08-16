_devbox_doctor() {
  local verbose="${1:-0}"
  local -a lines=()
  local ok=1

  if command -v curl >/dev/null 2>&1; then
    lines+=("[ok]   curl")
  else
    lines+=("[FAIL] curl not found -- fix: sudo apt install curl -y")
    ok=0
  fi

  if ! command -v docker >/dev/null 2>&1; then
    lines+=("[FAIL] docker not found -- fix: install Docker Engine (https://docs.docker.com/engine/install/)")
    ok=0
  elif docker info >/dev/null 2>&1; then
    lines+=("[ok]   docker daemon reachable")
  else
    local docker_err
    docker_err="$(docker info 2>&1 >/dev/null)"
    if printf '%s' "$docker_err" | grep -qi "permission denied"; then
      lines+=('[FAIL] docker: permission denied on docker.sock -- fix: sudo usermod -aG docker $USER && newgrp docker   # or log out/in')
    else
      lines+=("[FAIL] docker daemon not reachable -- fix: start Docker (sudo systemctl start docker, or open Docker Desktop/OrbStack)")
    fi
    ok=0
  fi

  if command -v devcontainer >/dev/null 2>&1; then
    lines+=("[ok]   devcontainer CLI on PATH")
  else
    lines+=('[FAIL] devcontainer CLI not found on PATH -- fix: curl -fsSL https://raw.githubusercontent.com/devcontainers/cli/main/scripts/install.sh | sh && echo '"'"'export PATH="$HOME/.devcontainers/bin:$PATH"'"'"' >> ~/.bashrc && source ~/.bashrc')
    ok=0
  fi

  if [[ "$verbose" == "1" || "$ok" == "0" ]]; then
    echo "devbox doctor:"
    local l
    for l in "${lines[@]}"; do
      echo "  $l"
    done
    [[ "$ok" == "1" ]] && echo "  all checks passed"
  fi

  [[ "$ok" == "1" ]]
}

devbox() {
  local dir="$1"
  if [[ "$dir" == "doctor" ]]; then
    _devbox_doctor 1
    return $?
  fi
  if [[ -z "$dir" ]]; then
    echo "usage: devbox <dir>" >&2
    return 1
  fi
  _devbox_doctor 0 || return 1
  dir="$(cd "$dir" 2>/dev/null && pwd)"
  if [[ -z "$dir" || ! -d "$dir" ]]; then
    echo "devbox: no such directory: $1" >&2
    return 1
  fi
  builtin cd "$dir" || return 1
  local template_dir="$HOME/.devbox-template"
  if [[ ! -f .devcontainer/devcontainer.json && ! -f .devcontainer.json ]]; then
    if [[ ! -f "$template_dir/devcontainer.json" ]]; then
      echo "devbox: no devcontainer.json in $dir, and no template at $template_dir" >&2
      return 1
    fi
    echo "devbox: no .devcontainer/ found, bootstrapping from $template_dir"
    cp -r "$template_dir" .devcontainer
  fi
  if [[ -f .devcontainer/VERSION && -f "$template_dir/VERSION" ]]; then
    local project_version template_version
    project_version="$(cat .devcontainer/VERSION)"
    template_version="$(cat "$template_dir/VERSION")"
    if [[ "$project_version" != "$template_version" ]]; then
      echo "devbox: this project's .devcontainer is v$project_version, template is now v$template_version"
      echo "        see $template_dir/CHANGELOG.md for what changed; re-run bootstrap to update"
    fi
  fi
  devcontainer up --workspace-folder . || return 1
  local sessions_dir="$dir/.devbox-sessions"
  mkdir -p "$sessions_dir"
  local logfile="$sessions_dir/$(date +%Y-%m-%dT%H-%M-%S).log"
  echo "devbox: recording session to $logfile"
  if [[ "$(uname)" == "Darwin" ]]; then
    script -q "$logfile" devcontainer exec --workspace-folder . bash
  else
    script -q -c "devcontainer exec --workspace-folder . bash" "$logfile"
  fi
  echo "devbox: session ended, transcript saved to $logfile"
  local cid
  cid="$(docker ps -q --filter "label=devcontainer.local_folder=$dir")"
  if [[ -n "$cid" ]]; then
    echo "devbox: stopping container $cid"
    docker stop "$cid" >/dev/null
  fi
}
