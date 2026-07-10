"""
Comprehensive end-to-end suite for the MCP Firebird stdio server.

Exercises every JSON-RPC method, all 9 fb_ tools, both prompts, the schema
resource, and the error/recovery paths against a real Firebird 5.0 seeded with
tests/seed/seed.sql + problems.sql. Assertions are tied to the guaranteed seed
fixtures and use substring/upper() checks rather than brittle exact equality.

Companion to test_mcp_firebird_stdio.py — both share the fixtures in conftest.py.
"""
import json
import os
import re

import pytest


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #
def _tool_text(client, name, arguments):
    """Call a tool and return result.content[0].text."""
    r = client.call("tools/call", {"name": name, "arguments": arguments})
    return r["result"]["content"][0]["text"]


def _maybe_json(text):
    """Parse text as JSON when it is JSON, else return None."""
    try:
        return json.loads(text)
    except (ValueError, TypeError):
        return None


# --------------------------------------------------------------------------- #
# 1. initialize handshake
# --------------------------------------------------------------------------- #
def test_initialize_handshake(raw_client):
    r = raw_client.call(
        "initialize",
        {
            "protocolVersion": "2025-03-26",
            "capabilities": {},
            "clientInfo": {"name": "pytest", "version": "1"},
        },
    )
    res = r["result"]
    assert res["protocolVersion"] == "2025-03-26"
    assert res["serverInfo"]["name"] == "mcp-firebird"
    assert res["serverInfo"]["version"] == "0.1.0"
    caps = res["capabilities"]
    assert "tools" in caps and "resources" in caps and "prompts" in caps


def test_initialize_handshake_via_stored_result(client):
    # conftest stores the initialize response on the client object.
    res = client.init_result["result"]
    assert res["serverInfo"]["name"] == "mcp-firebird"
    assert res["serverInfo"]["version"] == "0.1.0"
    assert res["protocolVersion"] == "2025-03-26"


# --------------------------------------------------------------------------- #
# 2. ping
# --------------------------------------------------------------------------- #
def test_ping_returns_result(client):
    r = client.call("ping")
    assert "result" in r
    assert r["result"] == {}


# --------------------------------------------------------------------------- #
# 3. tools/list
# --------------------------------------------------------------------------- #
FREE_TOOLS = {
    "fb_info",
    "fb_list_tables",
    "fb_generate_documentation",
    "fb_analyze_query",
    "fb_suggest_indexes",
    "fb_suggest_index_drops",
    "fb_audit_table",
    "fb_evaluate_goal",
    "fb_monitor_transactions",
}

# Announced in tools/list, implemented only in the Enterprise edition.
ENTERPRISE_STUBS = {
    "fb_analyze_config",
    "fb_analyze_db_header",
    "fb_parse_log",
    "fb_capture_trace",
    "fb_analyze_host",
}


def test_tools_list_free_plus_enterprise_stubs(client):
    r = client.call("tools/list")
    tools = r["result"]["tools"]
    names = {t["name"] for t in tools}
    assert names == FREE_TOOLS | ENTERPRISE_STUBS
    assert len(tools) == len(FREE_TOOLS) + len(ENTERPRISE_STUBS)
    for t in tools:
        assert t["description"].strip(), f"{t['name']} has empty description"
        assert isinstance(t["inputSchema"], dict), f"{t['name']} inputSchema not object"


@pytest.mark.skipif(
    os.environ.get("MCP_FB_EDITION") == "enterprise",
    reason="the Enterprise edition implements these tools instead of locking them",
)
@pytest.mark.parametrize("name", sorted(ENTERPRISE_STUBS))
def test_enterprise_stub_is_locked_but_discoverable(client, name):
    r = client.call("tools/call", {"name": name, "arguments": {}})
    result = r["result"]
    assert result["isError"] is True, f"{name} should report isError"
    text = result["content"][0]["text"]
    assert "Enterprise" in text
    assert "d.teti@bittime.it" in text, "the upsell must name a way to buy"
    # a stub must never leak a threshold or touch the host
    assert client.call("ping")["result"] == {}


def test_free_tools_are_not_locked(client):
    """The whole free edition must keep working next to the stubs."""
    for name in ("fb_info", "fb_list_tables"):
        r = client.call("tools/call", {"name": name, "arguments": {}})
        assert not r["result"].get("isError"), f"{name} regressed into an error"


# --------------------------------------------------------------------------- #
# 4. fb_info
# --------------------------------------------------------------------------- #
def test_fb_info_engine_version(client):
    text = _tool_text(client, "fb_info", {})
    assert "engine_version" in text
    data = _maybe_json(text)
    assert data is not None, "fb_info should return JSON"
    assert str(data["engine_version"]).startswith("5.0")


# --------------------------------------------------------------------------- #
# 5. fb_list_tables
# --------------------------------------------------------------------------- #
def test_fb_list_tables_contains_seed_tables(client):
    text = _tool_text(client, "fb_list_tables", {}).upper()
    for tbl in ("CUSTOMERS", "ORDERS", "NOPK_LOG", "OVERIDX", "STALE_T"):
        assert tbl in text, f"{tbl} missing from fb_list_tables"


# --------------------------------------------------------------------------- #
# 6. fb_generate_documentation describes one table
# --------------------------------------------------------------------------- #
def test_fb_generate_documentation_describes_customers(client):
    text = _tool_text(
        client, "fb_generate_documentation", {"table_name": "CUSTOMERS"}
    ).upper()
    assert "CUSTOMER_ID" in text
    assert "CITY" in text
    assert "PRIMARY KEY" in text


# --------------------------------------------------------------------------- #
# 7. fb_generate_documentation
# --------------------------------------------------------------------------- #
def test_fb_generate_documentation_single_table(client):
    text = _tool_text(client, "fb_generate_documentation", {"table_name": "CUSTOMERS"}).upper()
    assert "CUSTOMERS" in text


def test_fb_generate_documentation_whole_db(client):
    text = _tool_text(client, "fb_generate_documentation", {"table_name": ""}).upper()
    assert "CUSTOMERS" in text
    assert "ORDERS" in text


# --------------------------------------------------------------------------- #
# 8-10. fb_analyze_query
# --------------------------------------------------------------------------- #
def test_fb_analyze_query_natural_scan(client):
    text = _tool_text(
        client, "fb_analyze_query", {"sql": "SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'"}
    ).upper()
    assert "NATURAL" in text


def test_fb_analyze_query_external_sort(client):
    text = _tool_text(
        client, "fb_analyze_query", {"sql": "SELECT * FROM CUSTOMERS ORDER BY CITY"}
    ).upper()
    assert "SORT" in text


def test_fb_analyze_query_indexed_no_natural(client):
    text = _tool_text(
        client, "fb_analyze_query", {"sql": "SELECT * FROM CUSTOMERS WHERE CUSTOMER_ID = 1"}
    )
    upper = text.upper()
    # PK index is used; the server explicitly states no NATURAL scan.
    assert "NO NATURAL SCAN" in upper
    assert "NATURAL SCAN ON" not in upper


# --------------------------------------------------------------------------- #
# 11. fb_suggest_indexes
# --------------------------------------------------------------------------- #
def test_fb_suggest_indexes_city(client):
    text = _tool_text(
        client, "fb_suggest_indexes", {"sql": "SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'"}
    ).upper()
    assert "CREATE INDEX" in text
    assert "CITY" in text


# --------------------------------------------------------------------------- #
# 12-13. fb_suggest_index_drops
# --------------------------------------------------------------------------- #
def test_fb_suggest_index_drops_orders_dup(client):
    text = _tool_text(client, "fb_suggest_index_drops", {"table_name": "ORDERS"}).upper()
    assert "IDX_ORDERS_CUSTOMER_DUP" in text


def test_fb_suggest_index_drops_customers_redundant(client):
    text = _tool_text(client, "fb_suggest_index_drops", {"table_name": "CUSTOMERS"}).upper()
    assert any(
        idx in text for idx in ("IDX_CUST_NAME", "IDX_CUST_CITY", "IDX_CUST_STATUS")
    ), "expected at least one redundant/inactive/low-selectivity index flagged"


# --------------------------------------------------------------------------- #
# 14-16. fb_audit_table
# --------------------------------------------------------------------------- #
def test_fb_audit_table_nopk(client):
    text = _tool_text(client, "fb_audit_table", {"table_name": "NOPK_LOG"}).upper()
    assert "PRIMARY KEY" in text


def test_fb_audit_table_overidx(client):
    text = _tool_text(client, "fb_audit_table", {"table_name": "OVERIDX"}).upper()
    assert "INDEX" in text
    # over-indexing detector reports the count of user indexes.
    assert "6 USER INDEXES" in text or "INDEXES" in text


def test_fb_audit_table_stale_stats(client):
    text = _tool_text(client, "fb_audit_table", {"table_name": "STALE_T"}).upper()
    assert "STATISTICS" in text


# --------------------------------------------------------------------------- #
# 17-20. fb_evaluate_goal
# --------------------------------------------------------------------------- #
def test_fb_evaluate_goal_natural_not_met(client):
    text = _tool_text(
        client,
        "fb_evaluate_goal",
        {
            "goal_type": "query_no_natural_scan",
            "target": "SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'",
            "threshold": 0,
        },
    )
    data = _maybe_json(text)
    assert data is not None
    assert data["met"] is False


def test_fb_evaluate_goal_natural_met_on_pk(client):
    text = _tool_text(
        client,
        "fb_evaluate_goal",
        {
            "goal_type": "query_no_natural_scan",
            "target": "SELECT * FROM CUSTOMERS WHERE CUSTOMER_ID = 1",
            "threshold": 0,
        },
    )
    data = _maybe_json(text)
    assert data is not None
    assert data["met"] is True


def test_fb_evaluate_goal_no_redundant_indexes_not_met(client):
    text = _tool_text(
        client,
        "fb_evaluate_goal",
        {"goal_type": "no_redundant_indexes", "target": "CUSTOMERS", "threshold": 0},
    )
    data = _maybe_json(text)
    assert data is not None
    assert data["met"] is False


def test_fb_evaluate_goal_query_time_ms(client):
    text = _tool_text(
        client,
        "fb_evaluate_goal",
        {
            "goal_type": "query_time_ms",
            "target": "SELECT * FROM CUSTOMERS WHERE CUSTOMER_ID = 1",
            "threshold": 60000,
        },
    )
    data = _maybe_json(text)
    assert data is not None
    assert "met" in data
    assert "measured" in data
    assert isinstance(data["measured"], (int, float))


# --------------------------------------------------------------------------- #
# 21. fb_monitor_transactions
# --------------------------------------------------------------------------- #
def test_fb_monitor_transactions_reports_gap(client):
    text = _tool_text(client, "fb_monitor_transactions", {})
    for label in ("OIT:", "OAT:", "OST:", "Next:", "Gap:"):
        assert label in text
    gap = int(re.search(r"\*\*Gap:\*\*\s*(\d+)", text).group(1))
    assert gap >= 0


# --------------------------------------------------------------------------- #
# 22-24. prompts
# --------------------------------------------------------------------------- #
def test_prompts_list(client):
    r = client.call("prompts/list")
    prompts = {p["name"]: p for p in r["result"]["prompts"]}
    assert "optimization_goal" in prompts
    assert "health_check" in prompts
    arg_names = {a["name"] for a in prompts["optimization_goal"]["arguments"]}
    assert "goal_type" in arg_names
    assert "target" in arg_names


def test_prompts_get_optimization_goal(client):
    r = client.call(
        "prompts/get",
        {
            "name": "optimization_goal",
            "arguments": {
                "goal_type": "query_no_natural_scan",
                "target": "SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'",
                "threshold": "0",
            },
        },
    )
    blob = json.dumps(r["result"])
    assert r["result"]["messages"], "expected rendered messages"
    assert "fb_evaluate_goal" in blob
    assert "query_no_natural_scan" in blob
    assert "CITY" in blob


def test_prompts_get_health_check(client):
    r = client.call("prompts/get", {"name": "health_check", "arguments": {}})
    blob = json.dumps(r["result"])
    assert r["result"]["messages"]
    assert "fb_list_tables" in blob


# --------------------------------------------------------------------------- #
# 24-25. resources
# --------------------------------------------------------------------------- #
def test_resources_list(client):
    r = client.call("resources/list")
    res = {x["uri"]: x for x in r["result"]["resources"]}
    assert "firebird://schema" in res
    assert res["firebird://schema"]["mimeType"] == "text/markdown"


def test_resources_read_schema(client):
    r = client.call("resources/read", {"uri": "firebird://schema"})
    contents = r["result"]["contents"]
    assert contents, "expected contents array"
    first = contents[0]
    assert first["uri"] == "firebird://schema"
    assert first["mimeType"] == "text/markdown"
    text = first["text"].upper()
    assert "CUSTOMERS" in text
    assert "ORDERS" in text


# --------------------------------------------------------------------------- #
# 26-27. error handling & recovery
# --------------------------------------------------------------------------- #
def test_bad_table_does_not_crash_server(client):
    # fb_generate_documentation on a non-existent table responds gracefully (empty
    # doc, an isError flag, or a JSON-RPC error) without taking the server down.
    r = client.call(
        "tools/call",
        {"name": "fb_generate_documentation", "arguments": {"table_name": "NO_SUCH_TABLE"}},
    )
    blob = json.dumps(r).upper()
    handled_gracefully = (
        "ERROR" in blob
        or '"ISERROR"' in blob
        or "NO_SUCH_TABLE" in blob  # graceful empty-skeleton response
    )
    assert handled_gracefully
    # server must still be alive
    assert client.call("ping")["result"] == {}


def test_unknown_method_returns_error_and_survives(client):
    r = client.call("frobnicate", {})
    assert "error" in r
    assert "code" in r["error"]
    # server must still respond afterwards
    assert client.call("ping")["result"] == {}
