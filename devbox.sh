devbox() {
  local dir="$1"
  if [[ -z "$dir" ]]; then
    echo "usage: devbox <dir>" >&2
    return 1
  fi
  dir="$(cd "$dir" 2>/dev/null && pwd)"
  if [[ -z "$dir" || ! -d "$dir" ]]; then
    echo "devbox: no such directory: $1" >&2
    return 1
  fi
  builtin cd "$dir" || return 1
  if ! command -v devcontainer >/dev/null 2>&1; then
    echo "devbox: devcontainer CLI not found on PATH" >&2
    return 1
  fi
  local template_dir="$HOME/.devbox-template"
  if [[ ! -f .devcontainer/devcontainer.json && ! -f .devcontainer.json ]]; then
    if [[ ! -f "$template_dir/devcontainer.json" ]]; then
      echo "devbox: no devcontainer.json in $dir, and no template at $template_dir" >&2
      return 1
    fi
    echo "devbox: no .devcontainer/ found, bootstrapping from $template_dir"
    cp -r "$template_dir" .devcontainer
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
