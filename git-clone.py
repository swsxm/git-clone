#!/usr/bin/env python3
# coding: utf-8

import argparse
import logging
import re
import socket
import sys
from typing import Any

from pydantic import BaseModel, StrictStr, model_validator

# Configure module-level logger
logger = logging.getLogger(__name__)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)


class GitUrl(BaseModel):
    """
    Data model for a parsed Git URL.
    """

    proto: StrictStr
    host: StrictStr
    repo: StrictStr

    @model_validator(mode="before")
    def validate_not_empty(cls, values: dict[str, Any]) -> dict[str, Any]:
        if not all(values.get(field) for field in ("proto", "host", "repo")):
            raise ValueError("`proto`, `host`, and `repo` must be non-empty strings")
        return values


def parse_git_url(url: str) -> GitUrl:
    """
    Parse a Git URL into its protocol, host, and repository components.
    Supports patterns like:
      - proto://host/repo
      - proto:host/repo
    """
    if not url:
        raise ValueError("URL must not be empty")

    # Split on `://`, `:`, or `/`, collapsing consecutive delimiters
    parts = [part for part in re.split(r"[/:]+", url) if part]
    if len(parts) < 3:
        raise ValueError(f"Invalid Git URL format: {url!r}")

    proto, host, *repo_parts = parts
    repo = "/".join(repo_parts)
    return GitUrl(proto=proto, host=host, repo=repo)


def build_pkt_line(data: str) -> bytes:
    """
    Build a Git pkt-line packet for the provided ASCII data.
    """
    payload = data.encode("utf-8")
    length = len(payload) + 4  # 4 bytes for the length header
    header = f"{length:04x}".encode("ascii")
    return header + payload


def send_git_service_request(
    host: str,
    port: int,
    repo: str,
    service: str = "git-upload-pack",
    timeout: float = 5.0,
) -> bytes:
    """
    Connect to the Git service on `<host>:<port>`, send a service request for `<repo>`,
    and return the raw response bytes.
    """
    payload = f"{service} /{repo}\0host={host}\0"
    pkt = build_pkt_line(payload)

    with socket.create_connection((host, port), timeout=timeout) as sock:
        sock.sendall(pkt)
        # Read up to 4KB; adjust as needed for larger responses
        return sock.recv(4096)


def main() -> None:
    parser = argparse.ArgumentParser(description="Send a Git service request over TCP.")
    parser.add_argument(
        "url",
        help="Git URL (e.g., 'git://host/repo' or 'ssh:host/repo')",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=9418,
        help="Git service port (default: 9418)",
    )
    parser.add_argument(
        "--service",
        default="git-upload-pack",
        help="Git service to request (default: git-upload-pack)",
    )
    args = parser.parse_args()

    try:
        git_url = parse_git_url(args.url)
    except ValueError as exc:
        logger.error("Failed to parse Git URL: %s", exc)
        sys.exit(1)

    try:
        response = send_git_service_request(
            host=git_url.host,
            port=args.port,
            repo=git_url.repo,
            service=args.service,
        )
        logger.info("Received %d bytes from %s", len(response), git_url.host)
        print(response)
    except socket.timeout:
        logger.error("Connection to %s:%d timed out", git_url.host, args.port)
        sys.exit(2)
    except socket.error as exc:
        logger.error(
            "Socket error communicating with %s:%d: %s", git_url.host, args.port, exc
        )
        sys.exit(3)

    logger.info("Done.")


if __name__ == "__main__":
    main()
