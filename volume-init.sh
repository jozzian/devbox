#!/bin/sh
# Fixed path, no args accepted — sudoers locks this to no-args so a
# hostile process can't pass arbitrary chown targets. Safe to be identical
# across every project: the only named volume the base template mounts is
# the isolated Claude Code home.
set -eu
target_uid="$(id -u node)"
for d in '/home/node/.claude'; do
    [ -e "$d" ] || continue
    # Only chown freshly-mounted (root-owned) volumes. Docker creates named
    # volumes root-owned 0755, which root can read, so the first chown -R
    # succeeds. Re-running it later would force root to recurse into a now
    # dev-owned 0700 dir and fail with "Permission denied" —
    # --cap-drop=ALL strips CAP_DAC_READ_SEARCH, so root can't traverse a
    # directory it lacks the permission bits for. Skipping already-dev-owned
    # dirs keeps the chown idempotent.
    [ "$(stat -c %u "$d")" = "$target_uid" ] && continue
    chown -R node:node "$d"
done
exit 0
