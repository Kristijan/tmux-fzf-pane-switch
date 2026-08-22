#!/usr/bin/env python3
"""Drive the real tmux/fzf switcher through a pseudo-terminal."""

import glob
import os
import pty
import select
import signal
import subprocess
import sys
import time


OWNER_MAGIC = "fzf-pane-switch-v1"


def read_available(fd, transcript):
    while True:
        readable, _, _ = select.select([fd], [], [], 0)
        if not readable:
            return
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            return
        if not chunk:
            return
        transcript.extend(chunk)


def invocation_directories(temporary_root):
    directories = []
    for directory in glob.glob(os.path.join(temporary_root, "fzf-pane-switch.*")):
        owner_file = os.path.join(directory, "owner")
        try:
            with open(owner_file, encoding="utf-8") as owner:
                if owner.readline().strip() == OWNER_MAGIC:
                    directories.append(directory)
        except (OSError, UnicodeError):
            pass
    return directories


def read_generation_state(directory):
    try:
        with open(os.path.join(directory, "generation"), encoding="ascii") as source:
            generation = int(source.read().strip())
        with open(os.path.join(directory, f"state.{generation}"), encoding="ascii") as source:
            state = source.read().strip()
        return generation, state
    except (OSError, ValueError):
        return 0, ""


def wait_for(predicate, fd, transcript, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        read_available(fd, transcript)
        result = predicate()
        if result:
            return result
        time.sleep(0.05)
    return None


def main():
    if len(sys.argv) != 4:
        print("usage: drive_switcher.py TMUX SOCKET TMPDIR", file=sys.stderr)
        return 2

    tmux_binary, socket_name, temporary_root = sys.argv[1:]
    transcript = bytearray()
    child_pid, fd = pty.fork()
    if child_pid == 0:
        environment = os.environ.copy()
        environment["TERM"] = "xterm-256color"
        os.execve(
            tmux_binary,
            [tmux_binary, "-L", socket_name, "attach-session", "-t", "integration"],
            environment,
        )

    try:
        time.sleep(0.4)
        read_available(fd, transcript)
        os.write(fd, b"\x02")
        time.sleep(0.1)
        os.write(fd, b"s")

        directories = wait_for(
            lambda: invocation_directories(temporary_root), fd, transcript
        )
        if not directories:
            raise RuntimeError("switcher did not create a private snapshot directory")
        directory = max(directories, key=os.path.getmtime)

        first_ready = wait_for(
            lambda: read_generation_state(directory) == (1, "ready"),
            fd,
            transcript,
        )
        if not first_ready:
            raise RuntimeError(
                f"initial snapshot did not become ready: {read_generation_state(directory)!r}"
            )

        read_available(fd, transcript)
        transcript.clear()
        os.write(fd, b"\x12")
        refreshed = wait_for(
            lambda: (
                read_generation_state(directory)[0] >= 2
                and read_generation_state(directory)[1] == "ready"
            ),
            fd,
            transcript,
        )
        if not refreshed:
            raise RuntimeError(
                f"Ctrl-R snapshot did not become ready: {read_generation_state(directory)!r}"
            )

        final_label = wait_for(lambda: b"Panes" in transcript, fd, transcript, timeout=3)
        if not final_label:
            raise RuntimeError("fzf did not render the ready list label after Ctrl-R")

        os.write(fd, b"\x1b")
        cleaned = wait_for(lambda: not os.path.exists(directory), fd, transcript)
        if not cleaned:
            raise RuntimeError("switcher did not clean its private snapshot directory")
        return 0
    except Exception as error:  # Integration diagnostics must include terminal state.
        read_available(fd, transcript)
        print(str(error), file=sys.stderr)
        print(transcript.decode("utf-8", errors="replace")[-4000:], file=sys.stderr)
        messages = subprocess.run(
            [tmux_binary, "-L", socket_name, "show-messages", "-J"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        ).stdout
        print(messages.decode("utf-8", errors="replace")[-4000:], file=sys.stderr)
        return 1
    finally:
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.kill(child_pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            os.waitpid(child_pid, 0)
        except ChildProcessError:
            pass


if __name__ == "__main__":
    sys.exit(main())
