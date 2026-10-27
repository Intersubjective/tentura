#!/usr/bin/env python3
"""Internal output monitor for run_with_test_cleanup.sh's timed command."""

from contextlib import suppress
import os
import selectors
import signal
import subprocess
import sys
import time


def main():
    seconds, label, kill_after = sys.argv[1:4]
    seconds, kill_after = float(seconds), float(kill_after)
    # Same session boundary as the wrapper's setsid launcher. GNU timeout
    # still owns the overall deadline; the wrapper/reaper still own cleanup.
    process = subprocess.Popen(
        sys.argv[4:], start_new_session=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    last_output = time.monotonic()
    last_line = b""
    pending = {}
    with selectors.DefaultSelector() as selector:
        for pipe, output in ((process.stdout, sys.stdout.buffer),
                             (process.stderr, sys.stderr.buffer)):
            selector.register(pipe, selectors.EVENT_READ, output)
            pending[pipe] = b""
        while True:
            ready = selector.select(min(0.1, max(0, seconds - (
                time.monotonic() - last_output))))
            for key, _ in ready:
                chunk = os.read(key.fd, 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                    key.fileobj.close()
                    continue
                key.data.write(chunk)
                key.data.flush()
                last_output = time.monotonic()
                lines = (pending[key.fileobj] + chunk).splitlines()
                if lines:
                    last_line = lines[-1][-4096:]
                pending[key.fileobj] = (
                    b"" if chunk.endswith((b"\n", b"\r")) else last_line
                )
            # Drain output already in the pipes before returning the real code.
            if process.poll() is not None and not ready:
                break
            if process.poll() is None and time.monotonic() - last_output >= seconds:
                print(
                    f"test-cleanup: no test output for {label} -- treating as a hang; "
                    f"last line: {last_line.decode('utf-8', 'replace')}",
                    file=sys.stderr, flush=True,
                )
                with suppress(ProcessLookupError):
                    os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=kill_after)
                except subprocess.TimeoutExpired:
                    with suppress(ProcessLookupError):
                        os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                return 125
    rc = process.wait()
    return rc if rc >= 0 else 128 - rc


if __name__ == "__main__":
    sys.exit(main())
