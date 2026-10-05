"""Clone the deployed backend config without printing or persisting its secrets.

Run on the VPS after building an image. --candidate disables background workers
and binds Uvicorn to loopback. Keep the source container for rollback.
"""

import argparse
import http.client
import json
import os
import re
import socket
import stat
import subprocess
from urllib.parse import quote


class DockerConnection(http.client.HTTPConnection):
    def __init__(self):
        super().__init__("localhost", timeout=20)

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect("/var/run/docker.sock")


def docker_request(method, path, payload=None):
    connection = DockerConnection()
    try:
        body = json.dumps(payload).encode() if payload is not None else None
        connection.request(method, path, body, {"Content-Type": "application/json"})
        response = connection.getresponse()
        data = response.read()
        if response.status not in {200, 201, 204}:
            raise RuntimeError("Docker operation failed: HTTP {}".format(response.status))
        return json.loads(data.decode("utf-8")) if data else {}
    finally:
        connection.close()


def read_private_deepseek_key(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, "r", encoding="utf-8") as handle:
        info = os.fstat(handle.fileno())
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid()
                or stat.S_IMODE(info.st_mode) != 0o600 or info.st_size > 256):
            raise ValueError("Requires an owned private credential file")
        key = handle.read(256).strip()
    if not re.fullmatch(r"sk-[A-Za-z0-9_-]{16,160}", key):
        raise ValueError("Invalid provider credential format")
    return key


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--image", required=True)
    parser.add_argument("--port", required=True, type=int)
    parser.add_argument("--candidate", action="store_true")
    parser.add_argument("--create-only", action="store_true")
    parser.add_argument("--deepseek-key-file", help="Owned regular file with mode 600; never printed")
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535:
        parser.error("port must be between 1024 and 65535")
    key = None
    if args.deepseek_key_file:
        try:
            key = read_private_deepseek_key(args.deepseek_key_file)
        except (OSError, ValueError, UnicodeError):
            parser.error("Cannot load the private provider credential")
    source = json.loads(subprocess.check_output(["docker", "inspect", args.source]).decode("utf-8"))[0]
    image = docker_request("GET", "/images/" + quote(args.image, safe="") + "/json")
    config = source["Config"]
    overrides = {"PORT": str(args.port), "MARKET_HISTORY_PROVIDER": "tradingview",
                 "PROTRADING_BACKGROUND_WORKERS": "0" if args.candidate else "1"}
    if key is not None:
        overrides["DEEPSEEK_API_KEY"] = key
    environment = [item for item in config.get("Env", []) if item.split("=", 1)[0] not in overrides]
    environment.extend("{}={}".format(key, value) for key, value in overrides.items())
    payload = {key: config[key] for key in ("Cmd", "Entrypoint", "User", "WorkingDir", "Labels", "StopSignal") if key in config}
    payload.update(Image=args.image, Env=environment, HostConfig=source["HostConfig"])
    # A new image may add a required runtime security bootstrap.
    payload["Entrypoint"] = image["Config"].get("Entrypoint")
    if args.candidate:
        payload["Cmd"] = ["uvicorn", "server:app", "--host", "127.0.0.1", "--port", str(args.port)]
        payload["HostConfig"]["RestartPolicy"] = {"Name": "no", "MaximumRetryCount": 0}
    created = docker_request("POST", "/containers/create?name=" + quote(args.name, safe=""), payload)
    if not args.create_only:
        docker_request("POST", "/containers/" + created["Id"] + "/start")
    print(json.dumps({"container": args.name, "image": args.image, "port": args.port,
                      "candidate": args.candidate, "market_history_provider": "tradingview",
                      "deepseek_key_updated": key is not None}))


if __name__ == "__main__":
    main()
