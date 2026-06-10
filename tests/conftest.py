import json, os, subprocess, pytest

EXE = os.environ.get("MCP_FB_EXE", r"C:\DEV\mcp-firebird\app\bin\MCPFirebird.exe")

class StdioClient:
    def __init__(self, proc): self.proc = proc; self._id = 0
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
    c.call("initialize", {"protocolVersion": "2025-03-26", "capabilities": {},
                          "clientInfo": {"name": "pytest", "version": "1"}})
    yield c
    proc.stdin.close(); proc.terminate()
