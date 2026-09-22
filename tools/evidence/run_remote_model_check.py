#!/usr/bin/env python3
"""Run the fixed private Q remote-model-check probe.

Credential paths come from the environment so credential bytes never enter the
command registry or argv retained by the evidence collector.  The collector's
private command context retains the paths and declared service identity.  This
wrapper never reads or prints certificate or key contents.
"""

from __future__ import annotations

import hashlib
import os
import re
import stat
import sys
from pathlib import Path


HOST = "192.168.150.219"
PORT = "8999"
SERVICE = "ModelMirrors"
MIRROR = Path(".lake/build/bin/mirror")
SPEC = Path("test/specs/HourClock.tla")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
SOURCE_REF = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")
APALACHE_VERSION = "0.61.0"
APALACHE_ARCHIVE_SHA256 = "68fb56dd9d053cf21d692fd7ec3fbaaeba1395661ec7434fa2b4c47e6fc432b8"
APALACHE_JAR_SHA256 = "33611081942d392646af60993c599907f1f41752fce4a62304dbf9e2cdad4346"
JAVA_SELECTED_VERSION = "25.0.4+7"
JAVA_OBSERVED_VERSION = "25.0.4+7-LTS"
JAVA_ARCHIVE_SHA256 = "54ba13f3ef80887fa74708b2a32daaae6262517ba68433d850bb4b426343172b"
JAVA_EXECUTABLE_SHA256 = "58df5c13e5d6e68f242ad9b724479122828523008ef0907d3f2a02f54afaff23"


def required(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise ValueError(f"required private environment name is absent: {name}")
    return value


def regular_file(name: str) -> str:
    value = required(name)
    info = os.stat(value, follow_symlinks=False)
    if not stat.S_ISREG(info.st_mode):
        raise ValueError(f"private environment path is not a regular file: {name}")
    return value


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    try:
        cert = regular_file("MIRRORS_REMOTE_CLIENT_CERT")
        key = regular_file("MIRRORS_REMOTE_CLIENT_KEY")
        ca = regular_file("MIRRORS_REMOTE_CA")
        pin = required("MIRRORS_REMOTE_SERVER_PIN").lower()
        service_binary = required("MIRRORS_REMOTE_SERVICE_BINARY_SHA256").lower()
        source_ref = required("MIRRORS_REMOTE_SERVICE_SOURCE_REF").lower()
        if not HEX64.fullmatch(pin):
            raise ValueError("MIRRORS_REMOTE_SERVER_PIN must be 64 lowercase hex digits")
        if not HEX64.fullmatch(service_binary):
            raise ValueError(
                "MIRRORS_REMOTE_SERVICE_BINARY_SHA256 must be 64 lowercase hex digits"
            )
        if not SOURCE_REF.fullmatch(source_ref):
            raise ValueError(
                "MIRRORS_REMOTE_SERVICE_SOURCE_REF must be a full 40 or 64 digit hex identity"
            )
        required_fixed = {
            "MIRRORS_REMOTE_APALACHE_VERSION": APALACHE_VERSION,
            "MIRRORS_REMOTE_APALACHE_ARCHIVE_SHA256": APALACHE_ARCHIVE_SHA256,
            "MIRRORS_REMOTE_APALACHE_JAR_SHA256": APALACHE_JAR_SHA256,
            "MIRRORS_REMOTE_JAVA_SELECTED_VERSION": JAVA_SELECTED_VERSION,
            "MIRRORS_REMOTE_JAVA_OBSERVED_VERSION": JAVA_OBSERVED_VERSION,
            "MIRRORS_REMOTE_JAVA_ARCHIVE_SHA256": JAVA_ARCHIVE_SHA256,
            "MIRRORS_REMOTE_JAVA_EXECUTABLE_SHA256": JAVA_EXECUTABLE_SHA256,
        }
        if any(required(name) != value for name, value in required_fixed.items()):
            raise ValueError("remote model-check tool identity differs from the selected pins")
        if not MIRROR.is_file() or not os.access(MIRROR, os.X_OK):
            raise ValueError("build the registered Mirrors client before remote qualification")
        if not SPEC.is_file():
            raise ValueError("registered HourClock qualification model is absent")
    except (OSError, ValueError) as error:
        print(f"remote model-check admission failed: {error}", file=sys.stderr)
        return 2

    print(
        "remote-model-check "
        f"endpoint={HOST}:{PORT} service={SERVICE} tls=1.3-mtls "
        f"server_pin_sha256={pin} service_binary_sha256={service_binary} "
        f"service_source_ref={source_ref} client_binary_sha256={sha256(MIRROR)} "
        f"model=HourClock.tla model_sha256={sha256(SPEC)} "
        f"apalache={APALACHE_VERSION} apalache_archive_sha256={APALACHE_ARCHIVE_SHA256} "
        f"apalache_jar_sha256={APALACHE_JAR_SHA256} java={JAVA_OBSERVED_VERSION} "
        f"java_archive_sha256={JAVA_ARCHIVE_SHA256} "
        f"java_executable_sha256={JAVA_EXECUTABLE_SHA256}",
        flush=True,
    )
    argv = [
        str(MIRROR),
        "validate",
        "--host", HOST,
        "--port", PORT,
        "--tls",
        "--cert", cert,
        "--key", key,
        "--ca", ca,
        "--pin", pin,
        "--spec", str(SPEC),
        "--inv", "Inv",
        "--init", "Init",
        "--next", "Next",
        "--bound", "3",
    ]
    child_environment = dict(os.environ)
    child_environment.pop("APALACHE_MC", None)
    os.execve(MIRROR, argv, child_environment)
    return 2  # pragma: no cover - execve replaces this process


if __name__ == "__main__":
    raise SystemExit(main())
