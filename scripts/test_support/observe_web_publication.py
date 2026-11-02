#!/usr/bin/env python3
"""Test-only observer of the live web directory during a real deployment.

Linux inotify queues events in filesystem order, even if deployment finishes
before Python reads them. New version paths must be absent before deployment.
Their creation or atomic rename must be observed before any entry-file update.
"""

import ctypes
import os
from pathlib import Path
import select
import struct
import subprocess
import sys


CLOSE_WRITE = 0x00000008
MOVED_TO = 0x00000080
CREATE = 0x00000100
IS_DIRECTORY = 0x40000000
QUEUE_OVERFLOW = 0x00004000
CONTROL_FILES = {
    "index.html", "flutter_bootstrap.js", "tentura-app-cache-sw.js",
    "version.json", "manifest.json",
}
ORDER_FAILURE = 86


def observe(web, payload, log, command):
    expected = {
        path.relative_to(payload): path.read_bytes()
        for path in (payload / "app-assets").rglob("*")
        if path.is_file()
    }
    controls = {
        Path(name): (payload / name).read_bytes()
        for name in CONTROL_FILES
        if (payload / name).is_file()
    }
    assert expected and controls, "Publication needs real assets and entry files"
    versions = {Path(*relative.parts[:2]) for relative in expected}
    for version in versions:
        assert not (web / version).exists(), f"New version must start absent: {version}"

    def matches(relative, contents):
        try:
            return (web / relative).read_bytes() == contents
        except FileNotFoundError:
            return False

    ready = set()
    published_versions = set()
    failures = []
    seen_entries = set()
    libc = ctypes.CDLL(None, use_errno=True)
    libc.inotify_init1.argtypes = [ctypes.c_int]
    libc.inotify_init1.restype = ctypes.c_int
    libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    libc.inotify_add_watch.restype = ctypes.c_int
    descriptor = libc.inotify_init1(os.O_CLOEXEC | os.O_NONBLOCK)
    if descriptor < 0:
        raise OSError(ctypes.get_errno(), "inotify_init1 failed")
    watches = {}

    def watch(directory):
        wd = libc.inotify_add_watch(
            descriptor, os.fsencode(directory), CLOSE_WRITE | MOVED_TO | CREATE,
        )
        if wd < 0:
            raise OSError(ctypes.get_errno(), f"Cannot watch {directory}")
        watches[wd] = directory

    def consume():
        while True:
            try:
                data = os.read(descriptor, 65536)
            except BlockingIOError:
                return
            offset = 0
            while offset < len(data):
                wd, mask, _, size = struct.unpack_from("iIII", data, offset)
                offset += 16
                name = os.fsdecode(data[offset:offset + size].split(b"\0", 1)[0])
                offset += size
                if mask & QUEUE_OVERFLOW:
                    raise AssertionError("Filesystem event queue overflowed")
                if wd not in watches:
                    continue
                path = watches[wd] / name
                relative = path.relative_to(web)
                if mask & IS_DIRECTORY:
                    if mask & (CREATE | MOVED_TO):
                        if relative in versions:
                            published_versions.add(relative)
                        # Register newly created directories, including any
                        # descendants populated before this event was read.
                        # Unlike pre-seeding readiness, this verification is
                        # tied to a newly observed directory publication.
                        for asset, contents in expected.items():
                            if relative in asset.parents and matches(asset, contents):
                                ready.add(asset)
                    if path.is_dir():
                        watch(path)
                        for directory in path.rglob("*"):
                            if directory.is_dir():
                                watch(directory)
                    continue
                if not mask & (CLOSE_WRITE | MOVED_TO):
                    continue
                if relative in expected and matches(relative, expected[relative]):
                    ready.add(relative)
                if relative in controls:
                    seen_entries.add(relative)
                    unpublished = versions - published_versions
                    if unpublished:
                        failures.append(
                            f"{relative} became visible before new version directories were published: "
                            + ", ".join(str(version) for version in sorted(unpublished))
                        )
                    missing = expected.keys() - ready
                    if missing:
                        failures.append(
                            f"{relative} became visible before versioned assets: "
                            + ", ".join(str(asset) for asset in sorted(missing))
                        )

    try:
        watch(web)
        for directory in web.rglob("*"):
            if directory.is_dir():
                watch(directory)
        with log.open("w") as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
            while True:
                select.select([descriptor], [], [], 0.05)
                consume()
                if process.poll() is not None:
                    consume()
                    break
        if process.returncode:
            print(log.read_text(), file=sys.stderr)
            return process.returncode
        for relative, contents in {**expected, **controls}.items():
            if not matches(relative, contents):
                failures.append(f"Deployment did not publish expected bytes for {relative}")
        if versions - published_versions:
            failures.append("Deployment never published the new version directories")
        if controls.keys() - seen_entries:
            failures.append("Deployment did not publish every new entry file")
        if failures:
            for failure in failures:
                print(f"FAIL: {failure}", file=sys.stderr)
            return ORDER_FAILURE
        print("OK: all versioned assets were published before entry files")
        return 0
    finally:
        os.close(descriptor)


if __name__ == "__main__":
    web, payload, log, separator, *command = sys.argv[1:]
    assert separator == "--" and command
    sys.exit(observe(Path(web).resolve(), Path(payload).resolve(), Path(log), command))
