"""
PyInvoke task runner for the MCP Firebird project.

A thin Python entry point over the existing PowerShell/batch tooling so the whole
build + test workflow is one command set. The PowerShell scripts under tests/ remain
the single source of truth; these tasks just orchestrate them.

Setup:
    python -m pip install invoke

Usage (run from the repo root):
    invoke --list                  # show all tasks
    invoke build                   # build the core test project and the MCP app
    invoke core --version 5.0      # run the DUnitX core suite against one FB version
    invoke matrix                  # core suite across every present FB version
    invoke compliance              # Python stdio MCP compliance suite (on FB 5.0), against a
                                   # private exe + .env under build/compliance/
    invoke boundary                # enforce the core/MVCFramework boundary
    invoke all                     # full matrix + boundary + compliance (run_all.ps1)

Requirements: Windows, PowerShell 7 (`pwsh`), RAD Studio 37.0 / Delphi 13 Athens (for builds),
the Firebird zip-kits under fb_versions/, and (for `compliance`) pytest.
"""

import os
import shutil

from invoke import task

ROOT = os.path.dirname(os.path.abspath(__file__))
VERSIONS = ["2.5", "3.0", "4.0", "5.0"]

FBKIT = os.path.join(ROOT, "tests", "fbkit.ps1")
MAKE_SEED = os.path.join(ROOT, "tests", "seed", "make_seed.ps1")
RUN_ALL = os.path.join(ROOT, "tests", "run_all.ps1")
BOUNDARY = os.path.join(ROOT, "tests", "check_core_boundary.ps1")
SPDX = os.path.join(ROOT, "scripts", "check_spdx.ps1")
VERSIONS_PSD1 = os.path.join(ROOT, "tests", "fbkit.versions.psd1")

CORE_EXE = os.path.join(ROOT, "tests", "coreproject", "MCPFirebirdCoreTests.exe")
SEED_DB = os.path.join(ROOT, "tests", "seed", "TESTDB.FDB")
PY_SUITE = os.path.join(ROOT, "tests", "test_mcp_firebird_stdio.py")
PY_SUITE_FULL = os.path.join(ROOT, "tests", "test_mcp_firebird_full.py")
LOGGER_CONFIG = os.path.join(ROOT, "bin", "loggerpro.stdio.json")

# The compliance suite runs its own private copy of the exe: bin\MCPFirebird.exe is
# usually held open by a live MCP client, and its bin\.env points at whatever database
# the developer is actually working on — not at the seeded TESTDB the suite asserts on.
COMPLIANCE_DIR = os.path.join(ROOT, "build", "compliance")
COMPLIANCE_EXE = os.path.join(COMPLIANCE_DIR, "MCPFirebird.exe")


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #
def _pwsh(c, script, *args, **run_kwargs):
    """Run a PowerShell 7 script with positional/named args, from the repo root."""
    parts = ["pwsh", "-NoProfile", "-File", f'"{script}"', *args]
    return c.run(" ".join(parts), **run_kwargs)


def _fbkit(c, action, version, hide=False):
    return _pwsh(c, FBKIT, "-Action", action, "-Version", version, hide=hide, warn=True)


def _kit_present(version):
    """True if the zip-kit directory for `version` exists under fb_versions/."""
    import re

    try:
        text = open(VERSIONS_PSD1, encoding="utf-8").read()
    except OSError:
        return True  # don't block if the registry can't be read
    # match e.g.  '5.0' = @{ Dir = 'Firebird-5.0.4...';
    m = re.search(rf"'{re.escape(version)}'\s*=\s*@\{{[^}}]*?Dir\s*=\s*'([^']+)'", text)
    if not m:
        return True
    return os.path.isdir(os.path.join(ROOT, "fb_versions", m.group(1)))


def _client_lib(c, version):
    return _fbkit(c, "client", version, hide=True).stdout.strip()


def _port(c, version):
    return _fbkit(c, "port", version, hide=True).stdout.strip()


def _check(version):
    if version not in VERSIONS:
        raise SystemExit(f"Unknown version {version!r}; expected one of {VERSIONS}")


# --------------------------------------------------------------------------- #
# build
# --------------------------------------------------------------------------- #
@task(help={"clean": "Run a Clean;Build (default) — pass --no-clean for incremental."})
def build_core(c, clean=True):
    """Build the DUnitX core test project (Win64 Debug)."""
    c.run(os.path.join(ROOT, "_build_core.bat"), pty=False)


@task(help={"out": "Build the exe into this folder instead of bin/ (leaves bin/ untouched)."})
def build_app(c, out=None):
    """Build the MCP stdio server app (Win64 Debug) -> bin/MCPFirebird.exe."""
    bat = os.path.join(ROOT, "_build_app.bat")
    c.run(f'"{bat}" "{out}"' if out else bat, pty=False)


@task(build_core, build_app, default=True)
def build(c):
    """Build both the core test project and the MCP app."""
    print("Build complete: core tests + MCP app.")


# --------------------------------------------------------------------------- #
# Firebird kit lifecycle
# --------------------------------------------------------------------------- #
@task(help={"version": "Firebird version: 2.5 | 3.0 | 4.0 | 5.0 (default 5.0)"})
def start(c, version="5.0"):
    """Start a Firebird zip-kit server."""
    _check(version)
    _fbkit(c, "start", version)


@task(help={"version": "Firebird version (default 5.0)"})
def stop(c, version="5.0"):
    """Stop a Firebird zip-kit server."""
    _check(version)
    _fbkit(c, "stop", version)


@task(help={"version": "Firebird version (default 5.0)"})
def seed(c, version="5.0"):
    """(Re)create the seeded TESTDB.FDB for a version (server must be running)."""
    _check(version)
    _pwsh(c, MAKE_SEED, "-Version", version)


# --------------------------------------------------------------------------- #
# tests
# --------------------------------------------------------------------------- #
@task(help={"version": "Firebird version (default 5.0)",
            "keep-running": "Leave the FB server up after the run."})
def core(c, version="5.0", keep_running=False):
    """Run the DUnitX core suite against one FB version (start, seed, test, stop)."""
    _check(version)
    if not os.path.exists(CORE_EXE):
        print("Core exe not found — building it first.")
        build_core(c)
    _fbkit(c, "start", version)
    try:
        _pwsh(c, MAKE_SEED, "-Version", version)
        env = {
            "FBTEST_PORT": _port(c, version),
            "FBTEST_DB": SEED_DB,
            "FBTEST_CLIENTLIB": _client_lib(c, version),
        }
        c.run(f'"{CORE_EXE}"', env=env, pty=False)
    finally:
        if not keep_running:
            _fbkit(c, "stop", version)


@task
def matrix(c):
    """Run the DUnitX core suite across every FB version present under fb_versions/."""
    if not os.path.exists(CORE_EXE):
        build_core(c)
    failed = []
    for v in VERSIONS:
        if not _kit_present(v):
            print(f"SKIP FB {v} (kit not present)")
            continue
        print(f"==== Core suite on FB {v} ====")
        _fbkit(c, "start", v)
        try:
            _pwsh(c, MAKE_SEED, "-Version", v)
            env = {
                "FBTEST_PORT": _port(c, v),
                "FBTEST_DB": SEED_DB,
                "FBTEST_CLIENTLIB": _client_lib(c, v),
            }
            r = c.run(f'"{CORE_EXE}"', env=env, pty=False, warn=True)
            if r.exited != 0:
                failed.append(v)
        finally:
            _fbkit(c, "stop", v)
    if failed:
        raise SystemExit(f"Core tests FAILED on: {', '.join(failed)}")
    print("Core matrix: all present versions passed.")


@task
def boundary(c):
    """Enforce the boundaries: no MVCFramework in sources/, and no host access outside PlanAnalyzer."""
    _pwsh(c, BOUNDARY)


@task
def spdx(c):
    """Every production source carries the PolyForm Internal Use SPDX header."""
    _pwsh(c, SPDX)


def _write_compliance_env(c, version):
    """Give the compliance exe its own .env pointing at the seeded TESTDB on this kit."""
    os.makedirs(COMPLIANCE_DIR, exist_ok=True)
    shutil.copy2(LOGGER_CONFIG, COMPLIANCE_DIR)  # logger.config.file resolves against the exe folder
    with open(os.path.join(COMPLIANCE_DIR, ".env"), "w", encoding="utf-8") as f:
        f.write(
            f"firebird.host=localhost\n"
            f"firebird.port={_port(c, version)}\n"
            f"firebird.database={SEED_DB}\n"
            f"firebird.user=SYSDBA\n"
            f"firebird.password=masterkey\n"
            f"firebird.charset=UTF8\n"
            f"firebird.client_lib={_client_lib(c, version)}\n"
            f"logger.config.file=loggerpro.stdio.json\n"
        )


@task(help={"version": "Firebird version to run the server against (default 5.0)",
            "keep-running": "Leave the FB server up after the run.",
            "no-build": "Reuse the existing build/compliance exe instead of rebuilding."})
def compliance(c, version="5.0", keep_running=False, no_build=False):
    """Run the Python stdio MCP compliance suite against a private build of the app."""
    _check(version)
    if not no_build or not os.path.exists(COMPLIANCE_EXE):
        build_app(c, out=COMPLIANCE_DIR)
    _fbkit(c, "start", version)
    try:
        _pwsh(c, MAKE_SEED, "-Version", version)
        _write_compliance_env(c, version)
        c.run(f'python -m pytest "{PY_SUITE}" "{PY_SUITE_FULL}" -v', pty=False,
              env={"MCP_FB_EXE": COMPLIANCE_EXE})
    finally:
        if not keep_running:
            _fbkit(c, "stop", version)


@task
def all(c):
    """Full suite: core matrix + boundary check + Python compliance (run_all.ps1)."""
    _pwsh(c, RUN_ALL)
