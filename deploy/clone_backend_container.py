"""Clone the deployed backend config without printing or persisting its secrets.

Run on the VPS after building an image. --candidate disables background workers
and binds Uvicorn to loopback. Keep the source container for rollback.
"""

import argparse
import http.client
import json
import socket
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--image", required=True)
    parser.add_argument("--port", required=True, type=int)
    parser.add_argument("--candidate", action="store_true")
    parser.add_argument("--create-only", action="store_true")
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535:
        parser.error("port must be between 1024 and 65535")
    source = json.loads(subprocess.check_output(["docker", "inspect", args.source]).decode("utf-8"))[0]
    config = source["Config"]
    overrides = {"PORT": str(args.port), "MARKET_HISTORY_PROVIDER": "tradingview",
                 "PROTRADING_BACKGROUND_WORKERS": "0" if args.candidate else "1"}
    environment = [item for item in config.get("Env", []) if item.split("=", 1)[0] not in overrides]
    environment.extend("{}={}".format(key, value) for key, value in overrides.items())
    payload = {key: config[key] for key in ("Cmd", "Entrypoint", "User", "WorkingDir", "Labels", "StopSignal") if key in config}
    payload.update(Image=args.image, Env=environment, HostConfig=source["HostConfig"])
    if args.candidate:
        payload["Cmd"] = ["uvicorn", "server:app", "--host", "127.0.0.1", "--port", str(args.port)]
        payload["Entrypoint"] = None
        payload["HostConfig"]["RestartPolicy"] = {"Name": "no", "MaximumRetryCount": 0}
    created = docker_request("POST", "/containers/create?name=" + quote(args.name, safe=""), payload)
    if not args.create_only:
        docker_request("POST", "/containers/" + created["Id"] + "/start")
    print(json.dumps({"container": args.name, "image": args.image, "port": args.port,
                      "candidate": args.candidate, "market_history_provider": "tradingview"}))


if __name__ == "__main__":
    main()
