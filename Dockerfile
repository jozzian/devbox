FROM debian:bookworm-slim

# python3 is already in the image, but only as a transitive dependency of
# the credential proxy (mitmproxy) -- so it arrives without pip and without
# ensurepip, which makes both `pip install` and `python3 -m venv` fail out
# of the box. python3-pip/python3-venv are the baseline that lets a project
# build its own venv; no project libraries are baked in. Same split as the
# firewall's package-registry allowlist: make the tool reachable, let each
# project declare what it actually needs.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get -y install --no-install-recommends \
    ca-certificates curl git jq less locales sudo vim \
    python3-pip python3-venv \
    sqlite3 libsqlite3-dev \
    unzip \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen \
 && locale-gen en_US.UTF-8 \
 && update-locale LANG=en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# debian:bookworm-slim has no unprivileged user by default (unlike
# language-runtime base images). updateRemoteUserUID in devcontainer.json
# remaps this to your host UID/GID at container start, so the initial UID
# here doesn't need to match anything.
RUN useradd -m -s /bin/bash -u 1000 node \
 && usermod -aG sudo node

# Volume-init helper: chowns named-volume mountpoints at runtime (Docker
# creates volumes root-owned by default). The workspace always lives at the
# fixed /workspaces/app path (set via workspaceFolder/workspaceMount in
# devcontainer.json) regardless of the project's real directory name, so
# this script's paths are the same for every project and the sudoers entry
# can lock to no-args — a hostile process can't pass arbitrary chown
# targets.
COPY volume-init.sh /usr/local/bin/volume-init.sh
RUN chmod 0755 /usr/local/bin/volume-init.sh \
 && echo 'node ALL=(root) NOPASSWD: /usr/local/bin/volume-init.sh ""' > /etc/sudoers.d/devbox-volumes \
 && chmod 0440 /etc/sudoers.d/devbox-volumes \
 && printf '%s\n' 'Plugin sudoers_policy sudoers.so' 'Plugin sudoers_io sudoers.so' > /etc/sudo.conf

USER node
ENTRYPOINT ["/bin/bash"]
