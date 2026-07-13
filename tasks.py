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
RSVARS = r"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
DPROJ_APP = os.path.join(ROOT, "app", "MCPFirebird.dproj")
DIST = os.path.join(ROOT, "build", "dist")


@task(help={"version": "Tag to build, e.g. 0.2.1. Must already exist as a git tag."})
def release(c, version):
    """Package a downloadable release: a RELEASE build of the exe, and what it needs to run.

    Everything else in this file builds Debug, which is right for testing and wrong for a
    download: the Debug exe is 36 MB and ships a 77 MB .rsm of debug symbols beside it.

    What goes in, and what deliberately does not:

    - MCPFirebird.exe, built Release.
    - .env.example and loggerpro.stdio.json, which are the whole of the configuration.
    - NOT bin\\.env. That is the maintainer's own database and password.
    - NOT fbclient.dll. The copy in bin/ is Firebird 3.0.14 while this server is tested against
      2.5, 3.0, 4.0 and 5.0 -- each using its OWN client library. Shipping one client would make
      that choice for the user, silently and sometimes wrongly: a 3.0 client against a 5.0
      database mishandles the types 4.0 introduced. The .env names firebird.client_lib for
      exactly this reason, and the release tells the user to point it at their own server's
      client. A wrong client in the zip is worse than no client in the zip.
    """
    if os.path.exists(DIST):
        shutil.rmtree(DIST)
    os.makedirs(DIST)

    c.run(f'cmd /c ""{RSVARS}" && msbuild "{DPROJ_APP}" /t:Clean;Build '
          f'/p:Config=Release /p:Platform=Win64 /p:DCC_ExeOutput="{DIST}" '
          f'/p:DCC_DcuOutput="{os.path.join(ROOT, "build", "dcu")}""', pty=False)

    exe = os.path.join(DIST, "MCPFirebird.exe")
    if not os.path.exists(exe):
        raise SystemExit("The Release build produced no exe. Nothing is packaged.")

    # The linker drops a .rsm beside the exe -- 72 MB of remote debug symbols, which zip happily
    # squeezes small enough that nobody notices they downloaded them. They are of no use to anyone
    # but us, and they are half the map of the source we do not ship.
    for junk in os.listdir(DIST):
        if junk.lower().endswith((".rsm", ".map", ".drc", ".tds")):
            os.remove(os.path.join(DIST, junk))

    for f in ("bin/.env.example", "bin/loggerpro.stdio.json"):
        shutil.copy2(os.path.join(ROOT, f), DIST)
    shutil.copy2(os.path.join(ROOT, "README.md"), DIST)
    shutil.copy2(os.path.join(ROOT, "LICENSE"), DIST)

    zip_base = os.path.join(ROOT, "build", f"MCPFirebird-{version}-win64")
    shutil.make_archive(zip_base, "zip", DIST)
    print(f"\n{zip_base}.zip  ({os.path.getsize(zip_base + '.zip') / 1e6:.1f} MB)")
    print("Contents:")
    for f in sorted(os.listdir(DIST)):
        print(f"  {f}  ({os.path.getsize(os.path.join(DIST, f)):,} bytes)")

    # Never publish a binary nobody has run. A Release build is not a Debug build with fewer bytes:
    # different optimisation, assertions compiled out, different RTTI -- and this server leans on
    # RTTI to publish its tools. The suite that proves the Debug exe proves nothing about this one.
    #
    # It runs AFTER the archive is sealed, so the .env it needs can never find its way inside it.
    print("\nProving the exe that is about to be published, against a real Firebird 5.0.")
    _fbkit(c, "start", "5.0")
    try:
        _pwsh(c, MAKE_SEED, "-Version", "5.0")
        with open(os.path.join(DIST, ".env"), "w", encoding="utf-8") as f:
            f.write(
                f"firebird.host=localhost\n"
                f"firebird.port={_port(c, '5.0')}\n"
                f"firebird.database={SEED_DB}\n"
                f"firebird.user=SYSDBA\n"
                f"firebird.password=masterkey\n"
                f"firebird.charset=UTF8\n"
                f"firebird.client_lib={_client_lib(c, '5.0')}\n"
                f"logger.config.file=loggerpro.stdio.json\n"
            )
        c.run(f'python -m pytest "{PY_SUITE}" "{PY_SUITE_FULL}" -v', pty=False,
              env={"MCP_FB_EXE": exe})
    finally:
        _fbkit(c, "stop", "5.0")
    print(f"\n{zip_base}.zip is proven and ready to upload.")


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
