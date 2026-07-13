import json, os, subprocess, pytest

EXE = os.environ.get("MCP_FB_EXE", r"C:\DEV\mcp-firebird\bin\MCPFirebird.exe")

# mcp-firebird-enterprise reuses this suite verbatim against its own executable, adding its own
# tests on top. It sets MCP_FB_EXE to its executable and MCP_FB_EDITION=enterprise, which skips
# the tests asserting the Enterprise tools are locked. Both editions expose the same six tool
# names, so everything else in the suite runs unchanged against either.

class StdioClient:
    def __init__(self, proc): self.proc = proc; self._id = 0; self.init_result = None
    def call(self, method, params=None):
        self._id += 1
        msg = {"jsonrpc": "2.0", "id": self._id, "method": method, "params": params or {}}
        self.proc.stdin.write((json.dumps(msg) + "\n").encode()); self.proc.stdin.flush()
        line = self.proc.stdout.readline()
        return json.loads(line)

@pytest.fixture
def client():
    proc = subprocess.Popen([EXE], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    c = StdioClient(proc)
    c.init_result = c.call("initialize", {"protocolVersion": "2025-03-26", "capabilities": {},
                          "clientInfo": {"name": "pytest", "version": "1"}})
    yield c
    proc.stdin.close(); proc.terminate()

@pytest.fixture
def raw_client():
    """Spawn the server WITHOUT calling initialize, so tests can drive the
    handshake themselves."""
    proc = subprocess.Popen([EXE], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    c = StdioClient(proc)
    yield c
    proc.stdin.close(); proc.terminate()
