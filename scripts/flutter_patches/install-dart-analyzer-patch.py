#!/usr/bin/env python3
"""Build and install the patched AOT analyzer for a Dart 3.13.0 SDK."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from urllib.parse import unquote, urljoin, urlsplit


REVISION = "da6595cd6bb5d4c0a185d759a025e879ff06e631"
PATCH = Path(__file__).with_name("dart-3.13.0-telemetry-zone.patch")
SNAPSHOT = "analysis_server_aot.dart.snapshot"


def install(sdk, source, package_config):
    if (sdk / "revision").read_text().strip() != REVISION:
        raise SystemExit("This patch requires the Dart 3.13.0 SDK revision " + REVISION)
    snapshots = sdk / "bin" / "snapshots"
    installed = snapshots / SNAPSHOT
    config = json.loads(package_config.read_text())

    # Build outside the Flutter workspace, using a private copy of analytics.
    with tempfile.TemporaryDirectory(prefix="tentura-analyzer-") as tmp:
        stage = Path(tmp)
        for package in config["packages"]:
            uri = urljoin(package_config.as_uri(), package["rootUri"])
            if package["name"] == "unified_analytics":
                analytics = stage / "unified_analytics"
                shutil.copytree(Path(unquote(urlsplit(uri).path)), analytics)
                subprocess.run(
                    ["patch", "--batch", "--forward", "-p1", "-i", str(PATCH.resolve())],
                    cwd=analytics,
                    check=True,
                    timeout=10,
                )
                uri = analytics.as_uri() + "/"
            package["rootUri"] = uri
        local_config = stage / "package_config.json"
        local_config.write_text(json.dumps(config))

        entrypoint = stage / "server.dart"
        shutil.copyfile(source / "pkg" / "analysis_server" / "bin" / "server.dart", entrypoint)
        candidate = stage / SNAPSHOT
        subprocess.run(
            [
                str(sdk / "bin" / "dart"),
                "compile",
                "aot-snapshot",
                "-Dbuilt_as_aot=true",
                f"--packages={local_config}",
                "-o",
                str(candidate),
                str(entrypoint),
            ],
            cwd=stage,
            check=True,
            timeout=240,
        )

        backup = installed.with_suffix(".snapshot.stock")
        with tempfile.TemporaryDirectory(prefix=".tentura-analyzer-", dir=snapshots) as dest:
            staged_snapshot = Path(dest) / SNAPSHOT
            shutil.copy2(candidate, staged_snapshot)
            try:
                os.link(installed, backup)
            except FileExistsError:
                pass  # The first successful install preserves the stock snapshot.
            staged_snapshot.replace(installed)
        print(f"Installed {installed}. Stock snapshot saved at {backup}.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sdk", type=Path, help="installed Dart SDK root")
    parser.add_argument("source", type=Path, help="matching Dart SDK source checkout")
    parser.add_argument("--package-config", type=Path, help="override the source package config")
    args = parser.parse_args()
    config = args.package_config or args.source / ".dart_tool" / "package_config.json"
    install(args.sdk.resolve(), args.source.resolve(), config.resolve())
