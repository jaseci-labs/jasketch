"""Shared fixtures for the JaSketch end-to-end suite.

The server under test is started with the SAME jac binary the project pins
(`[project] jac-version` in jac.toml). Resolution order:

    1. $JAC_BIN                     - explicit override (CI, local pinned build)
    2. .jac/venv/bin/jac*           - the binary this project's venv was built from
    3. `jac` on PATH                - last resort

Never let it silently fall through to PATH on a developer machine: a `jac` on
PATH is often an editable dev build tracking jaseci `main`, which compiles the
app with a different (newer) compiler than the one it will be deployed on, and
makes a green run meaningless.
"""

import glob
import os
import socket
import subprocess
import time
import urllib.error
import urllib.request

import pytest
from playwright.sync_api import Page

JASKETCH_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# A cold start compiles the client bundle (Vite + bun), which is slow on a clean
# checkout; a warm .jac/client cache makes it seconds.
SERVER_BOOT_TIMEOUT = 300.0
APP_READY_TIMEOUT = 60_000  # ms for the canvas to render


def _jac_binary() -> str:
    override = os.environ.get("JAC_BIN")
    if override:
        return override
    venv_bin = sorted(glob.glob(os.path.join(JASKETCH_DIR, ".jac", "venv", "bin", "jac*")))
    if venv_bin:
        return venv_bin[0]
    return "jac"


def _get_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _wait_for_http(url: str, proc: subprocess.Popen, timeout: float) -> bool:
    """Poll until the app answers, failing fast if the server process dies."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            return False
        try:
            with urllib.request.urlopen(url, timeout=5) as resp:
                if resp.status == 200:
                    return True
        except (urllib.error.URLError, OSError):
            time.sleep(1.0)
    return False


@pytest.fixture(scope="session")
def base_url():
    """Start the JaSketch server on a free port, yield its base URL."""
    port = _get_free_port()
    env = dict(os.environ)
    log_path = os.path.join(JASKETCH_DIR, ".jac-e2e-server.log")
    with open(log_path, "wb") as log:
        proc = subprocess.Popen(
            [_jac_binary(), "start", "--port", str(port)],
            cwd=JASKETCH_DIR,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=subprocess.STDOUT,
        )
        url = f"http://127.0.0.1:{port}"
        if not _wait_for_http(url, proc, SERVER_BOOT_TIMEOUT):
            proc.kill()
            with open(log_path) as fh:
                tail = "".join(fh.readlines()[-40:])
            pytest.fail(f"Server failed to come up on {url}\n--- server log tail ---\n{tail}")
        yield url
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()


@pytest.fixture(scope="module")
def app(browser, base_url) -> Page:
    """Navigate to JaSketch, wait for the canvas to be ready."""
    context = browser.new_context(permissions=["clipboard-read", "clipboard-write"])
    page = context.new_page()
    page.goto(base_url, wait_until="load")
    page.locator("canvas").first.wait_for(state="visible", timeout=APP_READY_TIMEOUT)
    yield page
    context.close()
