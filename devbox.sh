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

_devbox_firewall_custom_header() {
  cat <<'EOF'
# 99-custom.txt -- your own additions to the firewall allowlist.
# One domain per line. '#' starts a comment; blank lines are ignored.
# `devbox firewall list` combines this with every other *.txt file in
# firewall.d/ (sorted by filename) and dedupes -- a domain already
# covered by a preset doesn't need to be repeated here.
#
# Add domains with `devbox firewall add <domain>`, or edit this file
# directly and run `devbox firewall list` to confirm, then restart the
# container (or `devbox firewall add <domain>` again, which reloads a
# running container's firewall for you).
EOF
}

# Seed a project's firewall.d/ with the default presets if it has none.
#
# Deliberately not part of bootstrapping. init-firewall.sh builds the whole
# allowlist from firewall.d/, so a project bootstrapped before that
# directory existed has nothing to build from -- and since bootstrapping
# only runs when .devcontainer/ is absent, it would never get one. That is
# how an upgraded project ends up sandboxed to GitHub and DNS alone, with
# every other request hanging on a dropped packet.
#
# An existing firewall.d/ is left completely alone: the README encourages
# trimming it down to what a project actually needs, and re-adding presets
# underneath someone who deliberately removed them would be worse than the
# bug this fixes. Only its total absence is repaired.
_devbox_firewall_ensure() {
  local proj="$1" dir preset src
  dir="$proj/.devcontainer/firewall.d"
  [[ -d "$proj/.devcontainer" ]] || return 0
  [[ -d "$dir" ]] && return 0
  mkdir -p "$dir" || return 1
  for preset in base claude-code; do
    # A project bootstrapped before 0.2.0 has no vendored presets/ of its
    # own, so fall back to the template's copy -- that is exactly the
    # case being repaired here.
    for src in "$proj/.devcontainer/features/firewall/presets/$preset.txt" \
               "$HOME/.devbox-template/features/firewall/presets/$preset.txt"; do
      [[ -f "$src" ]] || continue
      cp "$src" "$dir/$preset.txt"
      break
    done
  done
  _devbox_firewall_custom_header > "$dir/99-custom.txt"
  echo "devbox: seeded default firewall presets (base, claude-code) into $dir"
  return 0
}

_devbox_firewall_container_id() {
  docker ps -q --filter "label=devcontainer.local_folder=$1"
}

_devbox_firewall_reload() {
  local proj="$1" cid
  cid="$(_devbox_firewall_container_id "$proj")"
  if [[ -n "$cid" ]]; then
    echo "devbox: reloading firewall in running container $cid"
    docker exec "$cid" sudo /usr/local/bin/init-firewall.sh
  else
    echo "devbox: no running container for $proj -- change takes effect next start"
  fi
}

_devbox_firewall_list() {
  local proj="$1" dir f base domain clean seen total=0 printed_any
  dir="$proj/.devcontainer/firewall.d"
  if [[ ! -d "$dir" ]]; then
    echo "devbox: no $dir -- this project hasn't bootstrapped the firewall.d allowlist yet" >&2
    return 1
  fi
  seen=""
  for f in "$dir"/*.txt; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    printed_any=0
    while IFS= read -r domain; do
      clean="${domain%%#*}"
      clean="$(echo "$clean" | xargs || true)"
      [[ -n "$clean" ]] || continue
      if printf '%s\n' "$seen" | grep -qxF "$clean"; then
        continue
      fi
      seen="$seen
$clean"
      if [[ "$printed_any" == "0" ]]; then
        echo "$base:"
        printed_any=1
      fi
      echo "  $clean"
      total=$((total + 1))
    done < "$f"
  done
  echo "---"
  echo "$total unique domain(s) allowlisted from $dir"
}

_devbox_firewall_test() {
  local proj="$1" domain="$2" cid
  cid="$(_devbox_firewall_container_id "$proj")"
  if [[ -z "$cid" ]]; then
    echo "devbox: no running container for $proj -- start one with 'devbox $proj' first" >&2
    return 1
  fi
  if docker exec "$cid" curl -sf --max-time 5 "https://$domain" >/dev/null 2>&1; then
    echo "  [PASS] $domain reachable"
  else
    echo "  [WARN] $domain not reachable -- check rules"
  fi
}

_devbox_firewall() {
  local sub="$1"
  shift || true
  case "$sub" in
    add)
      local domain="$1" proj="${2:-.}" custom
      if [[ -z "$domain" ]]; then
        echo "usage: devbox firewall add <domain> [project-dir]" >&2
        return 1
      fi
      proj="$(cd "$proj" 2>/dev/null && pwd)" || { echo "devbox: no such directory: ${2:-.}" >&2; return 1; }
      custom="$proj/.devcontainer/firewall.d/99-custom.txt"
      mkdir -p "$(dirname "$custom")"
      [[ -f "$custom" ]] || _devbox_firewall_custom_header > "$custom"
      if grep -qxF "$domain" "$custom" 2>/dev/null; then
        echo "devbox: $domain already in $custom"
      else
        echo "$domain" >> "$custom"
        echo "devbox: added $domain to $custom"
      fi
      _devbox_firewall_reload "$proj"
      ;;
    enable)
      local preset="$1" proj="${2:-.}" src
      if [[ -z "$preset" ]]; then
        echo "usage: devbox firewall enable <preset> [project-dir]" >&2
        return 1
      fi
      proj="$(cd "$proj" 2>/dev/null && pwd)" || { echo "devbox: no such directory: ${2:-.}" >&2; return 1; }
      src="$HOME/.devbox-template/features/firewall/presets/$preset.txt"
      if [[ ! -f "$src" ]]; then
        echo "devbox: unknown preset '$preset' (no $src)" >&2
        echo "        available presets:" >&2
        ls "$HOME/.devbox-template/features/firewall/presets" 2>/dev/null | sed 's/\.txt$//' | sed 's/^/          /' >&2
        return 1
      fi
      mkdir -p "$proj/.devcontainer/firewall.d"
      cp "$src" "$proj/.devcontainer/firewall.d/$preset.txt"
      echo "devbox: enabled preset '$preset' in $proj/.devcontainer/firewall.d/$preset.txt"
      _devbox_firewall_reload "$proj"
      ;;
    list)
      local proj="${1:-.}"
      proj="$(cd "$proj" 2>/dev/null && pwd)" || { echo "devbox: no such directory: ${1:-.}" >&2; return 1; }
      _devbox_firewall_list "$proj"
      ;;
    test)
      local domain="$1" proj="${2:-.}"
      if [[ -z "$domain" ]]; then
        echo "usage: devbox firewall test <domain> [project-dir]" >&2
        return 1
      fi
      proj="$(cd "$proj" 2>/dev/null && pwd)" || { echo "devbox: no such directory: ${2:-.}" >&2; return 1; }
      _devbox_firewall_test "$proj" "$domain"
      ;;
    *)
      echo "usage: devbox firewall <add|enable|list|test> ..." >&2
      return 1
      ;;
  esac
}

devbox() {
  local dir="$1"
  if [[ "$dir" == "doctor" ]]; then
    _devbox_doctor 1
    return $?
  fi
  if [[ "$dir" == "firewall" ]]; then
    shift
    _devbox_firewall "$@"
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
  # Docker volume names must match [a-zA-Z0-9][a-zA-Z0-9_.-]*, but project
  # folder names can contain spaces or other characters Docker rejects.
  # devcontainer.json can't sanitize ${localWorkspaceFolderBasename} itself,
  # so we do it here and pass it through as an env var it can reference.
  # Feed `tr` via printf rather than piping basename straight in: `tr -c`
  # counts the trailing newline as an out-of-set character too and rewrites
  # it to '-', so every project name picked up a phantom trailing dash --
  # renaming its ~/.claude volume and silently orphaning the stored login.
  local project_basename
  project_basename="$(basename "$dir")"
  export DEVBOX_PROJECT_NAME="$(printf '%s' "$project_basename" | tr -c 'A-Za-z0-9_.-' '-')"
  builtin cd "$dir" || return 1
  local template_dir="$HOME/.devbox-template"
  if [[ ! -f .devcontainer/devcontainer.json && ! -f .devcontainer.json ]]; then
    if [[ ! -f "$template_dir/devcontainer.json" ]]; then
      echo "devbox: no devcontainer.json in $dir, and no template at $template_dir" >&2
      return 1
    fi
    echo "devbox: no .devcontainer/ found, bootstrapping from $template_dir"
    cp -r "$template_dir" .devcontainer
    # Never carry the template's own .git into a project: it would give
    # every bootstrapped project a live clone of the template repo (full
    # history, origin remote) nested inside .devcontainer/, and a stray
    # git command run from there would target the template's remote
    # instead of the project's.
    rm -rf .devcontainer/.git
    # Nor the template's own bootstrapped .devcontainer/: the template is
    # itself a devbox project, so a plain copy nests a second, older config
    # one level down where it does nothing but confuse.
    rm -rf .devcontainer/.devcontainer
  fi
  # Seed the firewall allowlist with a default preset set (base +
  # claude-code, the primary supported tool today) and an empty, documented
  # spot for the project's own additions. Outside the bootstrap branch on
  # purpose -- see _devbox_firewall_ensure.
  _devbox_firewall_ensure "$dir" || return 1
  if [[ -f .devcontainer/VERSION && -f "$template_dir/VERSION" ]]; then
    local project_version template_version
    project_version="$(cat .devcontainer/VERSION)"
    template_version="$(cat "$template_dir/VERSION")"
    if [[ "$project_version" != "$template_version" ]]; then
      echo "devbox: this project's .devcontainer is v$project_version, template is now v$template_version"
      echo "        see $template_dir/CHANGELOG.md for what changed; to update, re-bootstrap:"
      echo "          rm -rf '$dir/.devcontainer' && devbox '$dir'"
      echo "        that also discards .devcontainer/firewall.d/ -- copy it aside first if you've customised the allowlist"
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
