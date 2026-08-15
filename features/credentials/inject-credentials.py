"""mitmproxy addon that injects credentials for approved hosts."""

import json
import logging
import os
from mitmproxy import http

_log_file = "/var/log/devbox/credential-injections.log"
if os.path.isdir(os.path.dirname(_log_file)):
    logging.basicConfig(
        filename=_log_file,
        format="%(asctime)s %(message)s",
        level=logging.INFO,
    )
else:
    logging.basicConfig(
        format="%(asctime)s %(message)s",
        level=logging.INFO,
    )


class InjectCredentials:
    def __init__(self):
        with open("/etc/devbox/credentials.json") as f:
            config = json.load(f)
        # Build host -> (header, value) lookup
        self.host_map = {}
        for cred in config.get("credentials", []):
            for host in cred["hosts"]:
                self.host_map[host] = (cred["header"], cred["value"])

    def request(self, flow: http.HTTPFlow):
        host = flow.request.pretty_host
        if host in self.host_map:
            header, value = self.host_map[host]
            flow.request.headers[header] = value
            # Log injection event (header name and target only, never the credential value)
            logging.info(
                "injected %s for %s %s%s",
                header,
                flow.request.method,
                host,
                flow.request.path,
            )


addons = [InjectCredentials()]
