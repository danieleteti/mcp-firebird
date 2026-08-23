"""
Comprehensive end-to-end suite for the MCP Firebird stdio server.

Exercises every JSON-RPC method, all 15 fb_ tools, all three prompts, the schema
resource, and the error/recovery paths against a real Firebird 5.0 seeded with
tests/seed/seed.sql + problems.sql. Assertions are tied to the guaranteed seed
fixtures and use substring/upper() checks rather than brittle exact equality.

Companion to test_mcp_firebird_stdio.py — both share the fixtures in conftest.py.
"""
import json
import os
import re
import time

import pytest

from conftest import EXE, StdioClient

# The Enterprise edition runs this suite verbatim against its own executable, and identifies
# itself differently on purpose: an MCP client must be able to tell the two servers apart.
IS_ENTERPRISE = os.environ.get("MCP_FB_EDITION") == "enterprise"
SERVER_NAME = "mcp-firebird-enterprise" if IS_ENTERPRISE else "mcp-firebird"


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
    assert res["serverInfo"]["name"] == SERVER_NAME
    assert res["serverInfo"]["version"] == "0.6.0"
    caps = res["capabilities"]
    assert "tools" in caps and "resources" in caps and "prompts" in caps


def test_initialize_handshake_via_stored_result(client):
    # conftest stores the initialize response on the client object.
    res = client.init_result["result"]
    assert res["serverInfo"]["name"] == SERVER_NAME
    assert res["serverInfo"]["version"] == "0.6.0"
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
    "fb_query",
    "fb_analyze_query",
    "fb_suggest_indexes",
    "fb_suggest_index_drops",
    "fb_audit_table",
    "fb_audit_security",
    "fb_evaluate_goal",
    "fb_monitor_transactions",
    "fb_sample_activity",
    "fb_backup_start",
    "fb_backup_status",
    "fb_monitor_attachments",
}

# Announced in tools/list, implemented only in the Enterprise edition.
ENTERPRISE_STUBS = {
    "fb_diagnose",
    "fb_analyze_config",
    "fb_analyze_storage",
    "fb_parse_log",
    "fb_capture_trace",
    "fb_analyze_host",
    "fb_trace_start",
    "fb_trace_status",
    "fb_trace_stop",
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


def test_fb_generate_documentation_documents_views_domains_and_checks(client):
    one = _tool_text(client, "fb_generate_documentation", {"table_name": "BRANCHES"})
    assert "D_CITY" in one, one
    assert "VARCHAR(60)" in one, "a UTF8 database stores 60 characters as 240 bytes"
    assert "CHK_BRANCH_STAFF" in one
    view = _tool_text(client, "fb_generate_documentation", {"table_name": "V_CUSTOMER_ORDERS"})
    assert "(view)" in view, view
    assert "View source" in view


def test_fb_generate_documentation_whole_db(client):
    text = _tool_text(client, "fb_generate_documentation", {"table_name": ""}).upper()
    assert "CUSTOMERS" in text
    assert "ORDERS" in text


# --------------------------------------------------------------------------- #
# 7b. non-ASCII survives the stdio wire, in both directions
# --------------------------------------------------------------------------- #
# Two ways an em dash used to reach the client as garbage, and both were silent:
# the transport wrote stdout in the console/ANSI code page, and the compiler read the
# .pas sources — UTF-8 but without a BOM — as ANSI, so the literal was already mojibake
# before it was written. All-ASCII payloads worked either way, which is why neither was
# noticed. "â€" is what a UTF-8 multi-byte sequence looks like after a Windows-1252
# misread; it must never appear in anything we hand the client.
MOJIBAKE = "â€"


def test_non_ascii_round_trips_over_stdio(client):
    # Outbound: the server's own text. The seed leaves IDX_CUST_CITY inactive, and the
    # generator marks it with an em dash (U+2014) — server-generated, not echoed input.
    doc = _tool_text(client, "fb_generate_documentation", {"table_name": "CUSTOMERS"})
    assert "— INACTIVE" in doc, ascii(doc)

    # Inbound: an accented, non-Latin-1 name reaches the server intact and comes back
    # unchanged in the heading, even though no such table exists.
    name = "CITTÀ_UTENTI_€_日本"
    assert name in _tool_text(client, "fb_generate_documentation", {"table_name": name})


def test_tool_descriptions_are_not_mojibake(client):
    # The tool descriptions are the first thing an LLM reads about this server, and most
    # of them carry an em dash. A misread source ships that garbage into every tools/list.
    for t in client.call("tools/list")["result"]["tools"]:
        assert MOJIBAKE not in t["description"], f"{t['name']}: {ascii(t['description'])}"


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
def test_fb_analyze_query_on_bad_sql_is_an_error_not_an_all_clear(client):
    """A statement Firebird refuses produces no plan — and must never be reported as a clean one.

    The plan comes from isql under SET PLANONLY ON, which prints its diagnostics into the same
    output. Harvesting only the PLAN lines turned "Table unknown" into an empty plan and the
    reassuring "No NATURAL scan: every table is accessed via an index."
    """
    r = client.call(
        "tools/call",
        {"name": "fb_analyze_query", "arguments": {"sql": "SELECT * FROM NO_SUCH_TABLE_HERE"}},
    )
    result = r["result"]
    text = result["content"][0]["text"]
    assert result.get("isError") is True, f"a refused statement must report isError, got: {text}"
    assert "NO NATURAL SCAN" not in text.upper()
    assert "NO_SUCH_TABLE_HERE" in text.upper(), "the error must name what Firebird refused"


def test_fb_suggest_indexes_reactivates_a_dormant_index_instead_of_duplicating_it(client):
    """IDX_CUST_CITY covers CITY, but it is INACTIVE — so the plan is CUSTOMERS NATURAL.

    The advisor knew the column had no *usable* index and stopped there, so it prescribed
    CREATE INDEX IDX_CUSTOMERS_CITY: a second index over the same column, beside the sleeping
    one. Two indexes, both written on every INSERT, one of them dead — and the actual fix, one
    ALTER away, never named. The tool must say which index to wake, not leave the caller to
    notice.
    """
    text = _tool_text(
        client, "fb_suggest_indexes", {"sql": "SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'"}
    ).upper()
    assert "ALTER INDEX IDX_CUST_CITY ACTIVE" in text, "the remedy is to reactivate the index"
    assert "INACTIVE" in text, "and to say why the existing index is not being used"
    assert "CREATE INDEX" not in text, "creating a second index over CITY duplicates IDX_CUST_CITY"


def test_fb_suggest_indexes_still_creates_one_when_no_index_covers_the_column(client):
    """The reactivation path must not swallow the ordinary case: ORDERS.TOTAL has no index at
    all, dormant or otherwise, and there CREATE INDEX is the right answer.

    TOTAL is ORDER_ID * 1.5 over 5000 rows, so `> 7000` keeps a few hundred of them. The
    threshold is part of the test: a predicate that keeps most of the table is a scan the
    optimizer is right about, and the advisor is expected to say so instead of prescribing an
    index that would be written on every INSERT and read by nobody."""
    text = _tool_text(
        client, "fb_suggest_indexes", {"sql": "SELECT * FROM ORDERS WHERE TOTAL > 7000"}
    ).upper()
    assert "CREATE INDEX" in text
    assert "ON ORDERS (TOTAL)" in text
    assert "ALTER INDEX" not in text


# The DDL is the product of this tool: it is advertised as ready to run. A query with aliases —
# the common case in real code — is where that promise breaks.
ALIASED_JOIN = (
    "SELECT c.NAME FROM CUSTOMERS c JOIN ORDERS o ON o.CUSTOMER_ID = c.CUSTOMER_ID "
    "WHERE c.CITY = 'Rome'"
)


def test_fb_suggest_indexes_resolves_the_alias_to_the_table(client):
    """Firebird prints the ALIAS in the plan ("O NATURAL"). CREATE INDEX ... ON O (TOTAL) does
    not run: there is no table O."""
    text = _tool_text(
        client, "fb_suggest_indexes", {"sql": "SELECT * FROM ORDERS o WHERE o.TOTAL > 7000"}
    ).upper()
    assert "ON ORDERS (TOTAL)" in text, "the DDL must name the table, not the alias"
    assert "ON O (" not in text


def test_fb_suggest_indexes_ignores_columns_of_other_tables(client):
    """Columns were harvested from the whole statement and pinned on every NATURAL table,
    whatever they belonged to — so a join key already carrying the primary-key index came back
    as an index to create."""
    text = _tool_text(client, "fb_suggest_indexes", {"sql": ALIASED_JOIN}).upper()
    assert "CUSTOMER_ID" not in text, "the join key is already indexed; it is not a suggestion"


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


def test_fb_audit_table_selectivity_is_locale_independent(client):
    """The selectivity numbers are read by machines. A decimal comma (an Italian Windows box,
    Format without invariant settings) makes "0,000004" unparseable to every consumer."""
    text = _tool_text(client, "fb_audit_table", {"table_name": "STALE_T"})
    line = next(l for l in text.splitlines() if "selectivity" in l.lower())
    assert not re.search(r"\d,\d", line), f"decimal comma in a selectivity figure: {line}"


def test_fb_audit_table_does_not_ask_to_refresh_an_inactive_index(client):
    """IDX_CUST_CITY is INACTIVE, so it has no statistics at all — not stale ones.

    Reporting a NULL selectivity as "stale" and prescribing SET STATISTICS is wrong advice
    twice over: the index cannot be used for reads, and the remedy is to drop it (which
    fb_suggest_index_drops already says).
    """
    text = _tool_text(client, "fb_audit_table", {"table_name": "CUSTOMERS"}).upper()
    assert "SET STATISTICS INDEX IDX_CUST_CITY" not in text
    assert "IDX_CUST_CITY HAS STALE STATISTICS" not in text


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


def test_fb_monitor_attachments_sees_the_connection_asking(client):
    # The server answers this over its own attachment, so a count of zero is not a quiet
    # database -- it is a broken query. There is always at least one: this one.
    text = _tool_text(client, "fb_monitor_attachments", {})
    count = int(re.search(r"\*\*(\d+) attachment\(s\) connected\.\*\*", text).group(1))
    assert count >= 1, text
    assert "SYSDBA" in text.upper()


def test_fb_monitor_attachments_thresholds_are_honoured(client):
    # Nothing here has been idle for a thousand minutes, so the generous call must find nothing.
    # Both thresholds are echoed nowhere, so what proves they arrived is the absence of findings.
    text = _tool_text(
        client,
        "fb_monitor_attachments",
        {"idle_minutes": 1000, "long_statement_seconds": 100000},
    )
    assert "No idle-connection or long-statement issues found." in text, text


# --------------------------------------------------------------------------- #
# 21b. fb_query
# --------------------------------------------------------------------------- #
def test_fb_query_returns_the_rows(client):
    text = _tool_text(
        client, "fb_query", {"sql": "SELECT CUSTOMER_ID, NAME FROM CUSTOMERS WHERE CUSTOMER_ID = 1"}
    )
    assert "| CUSTOMER_ID | NAME |" in text, text
    assert "CUST_1" in text
    assert "1 row(s)" in text


def test_fb_query_caps_the_rows(client):
    # The seed holds 5000 customers. Without a cap this answer is the table.
    text = _tool_text(client, "fb_query", {"sql": "SELECT * FROM CUSTOMERS", "max_rows": 5})
    assert "5 row(s)" in text, text
    assert "stopped at the cap of 5" in text, text
    # Header, separator and five data rows: anything more means the cap did not hold.
    assert len([ln for ln in text.splitlines() if ln.startswith("| ")]) == 6, text


def test_fb_query_defaults_to_one_hundred_rows(client):
    # One narrow column: with SELECT * the character budget stops this first, which is a
    # different limit and a different message.
    text = _tool_text(client, "fb_query", {"sql": "SELECT CUSTOMER_ID FROM CUSTOMERS"})
    assert "stopped at the cap of 100" in text, text


def test_fb_query_stops_a_wide_result_on_size(client):
    # The row cap bounds rows, not width. Four columns of 200 characters exhaust the budget
    # long before the hundredth row, and the answer has to say which limit it hit.
    text = _tool_text(
        client,
        "fb_query",
        {"sql": "SELECT LPAD('', 200, 'x'), LPAD('', 200, 'x'), LPAD('', 200, 'x'), "
                "LPAD('', 200, 'x') FROM CUSTOMERS"},
    )
    assert "too wide" in text, text
    assert len(text) < 40000, "the budget did not bound the answer"


def test_fb_query_refuses_a_delete(client):
    # The read-only TPB would refuse it anyway; this is the polite refusal in front of it,
    # and it must not come back as a JSON-RPC error but as a tool result that explains itself.
    text = _tool_text(client, "fb_query", {"sql": "DELETE FROM CUSTOMERS"})
    assert "Not executed" in text, text
    assert "SELECT" in text


def test_fb_query_refuses_unbound_placeholders(client):
    text = _tool_text(client, "fb_query", {"sql": "SELECT * FROM CUSTOMERS WHERE CITY = ?"})
    assert "Not executed" in text, text


def test_fb_query_reports_a_bad_table_as_an_error(client):
    r = client.call(
        "tools/call",
        {"name": "fb_query", "arguments": {"sql": "SELECT * FROM NO_SUCH_TABLE_HERE"}},
    )
    assert r["result"]["isError"] is True, r["result"]


# --------------------------------------------------------------------------- #
# 21c. fb_audit_security
# --------------------------------------------------------------------------- #
def test_fb_audit_security_flags_the_public_grants(client):
    text = _tool_text(client, "fb_audit_security", {})
    assert "PUBLIC" in text, text
    assert "CUSTOMERS" in text
    assert "NOPK_LOG" in text
    assert "critical" in text, "a write grant to PUBLIC is not a warning"


def test_fb_audit_security_flags_delegation_and_dead_roles(client):
    text = _tool_text(client, "fb_audit_security", {})
    assert "REPORT_USER" in text, text
    assert "GRANT OPTION" in text
    assert "DEAD_ROLE" in text


def test_fb_audit_security_leaves_out_the_system_tables(client):
    # PUBLIC holds SELECT on most of RDB$: reporting those buries the grants somebody made.
    text = _tool_text(client, "fb_audit_security", {})
    assert "RDB$RELATIONS" not in text, text


def test_fb_audit_security_says_what_it_cannot_see(client):
    text = _tool_text(client, "fb_audit_security", {})
    assert "Not ruled out by this check" in text, text
    assert "security database" in text


# --------------------------------------------------------------------------- #
# 22-24. prompts
# --------------------------------------------------------------------------- #
def test_prompts_list(client):
    r = client.call("prompts/list")
    prompts = {p["name"]: p for p in r["result"]["prompts"]}
    assert "optimization_goal" in prompts
    assert "health_check" in prompts
    assert "classify_problem" in prompts
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
    # A health review that never asks who may read the data reviews half the database.
    assert "fb_audit_security" in blob


def test_prompts_get_classify_problem(client):
    r = client.call("prompts/get", {"name": "classify_problem", "arguments": {
        "symptom": "the order screen crawls every afternoon"}})
    blob = json.dumps(r["result"])
    assert r["result"]["messages"]
    assert "the order screen crawls every afternoon" in blob
    # It must classify before reaching for a tool, and it must admit where an SQL
    # connection cannot settle the question.
    for expected in ("local inefficiency", "coordination and contention",
                     "temporal accumulation", "locality collapse", "fb_sample_activity"):
        assert expected in blob, f"{expected} missing from the classification prompt"


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
# 25b. what a check cannot see, and evidence that is measured rather than read
# --------------------------------------------------------------------------- #
@pytest.mark.parametrize(
    "name,arguments",
    [
        ("fb_query", {"sql": "SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'"}),
        ("fb_analyze_query", {"sql": "SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'"}),
        ("fb_suggest_indexes", {"sql": "SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'"}),
        ("fb_suggest_index_drops", {"table_name": "ORDERS"}),
        ("fb_audit_table", {"table_name": "NOPK_LOG"}),
        ("fb_audit_security", {}),
        ("fb_monitor_transactions", {}),
        ("fb_monitor_attachments", {}),
        ("fb_backup_status", {}),
    ],
)
def test_tools_state_what_they_do_not_rule_out(client, name, arguments):
    # A clean answer to a narrow question reads as a clean bill of health to whoever relays it.
    # Every advisory tool has to say where it is blind, whether or not it found anything.
    assert "Not ruled out by this check:" in _tool_text(client, name, arguments)


def test_fb_analyze_query_measures_the_query_it_analyzed(client):
    # A plan names the access path; only execution says how many records that path touched.
    # The seed holds 5000 customers and this query keeps all of them.
    text = _tool_text(client, "fb_analyze_query", {"sql": "SELECT * FROM CUSTOMERS"})
    assert "**Measured:**" in text
    assert "5000 row(s)" in text
    assert re.search(r"records read: [1-9]\d*\s+sequential", text), text


def test_fb_analyze_query_does_not_execute_a_statement_that_could_write(client):
    # The tool executes what it is given in order to measure it. It is given whatever the
    # caller typed, so the plan is still analyzed but the statement must not run.
    text = _tool_text(client, "fb_analyze_query", {"sql": "DELETE FROM CUSTOMERS WHERE 1 = 0"})
    assert "**PLAN:**" in text, "the plan is still worth having"
    assert "**Not measured:**" in text


def test_fb_evaluate_goal_refuses_to_time_a_write(client):
    r = client.call("tools/call", {"name": "fb_evaluate_goal", "arguments": {
        "goal_type": "query_time_ms", "target": "DELETE FROM CUSTOMERS", "threshold": 1000}})
    assert r["result"]["isError"] is True
    assert "SELECT" in r["result"]["content"][0]["text"]
    # and the rows are still there
    assert "5000" in _tool_text(client, "fb_analyze_query", {"sql": "SELECT * FROM CUSTOMERS"})


# --------------------------------------------------------------------------- #
# 25c. fb_sample_activity — a window, not an instant
# --------------------------------------------------------------------------- #
def test_fb_sample_activity_reports_a_window_of_deltas(client):
    text = _tool_text(client, "fb_sample_activity", {"seconds": 1})
    assert "**Window:**" in text
    for row in ("records read sequentially", "records read by index",
                "transactions started", "horizon moved"):
        assert row in text, f"{row} missing from the sample table"
    assert "Not ruled out by this check:" in text


def test_fb_sample_activity_rates_are_locale_independent(client):
    # Same trap as the selectivity figures in fb_audit_table: under an Italian locale %.1f
    # renders one point zero as "1,0", and the client parsing this table will not ask.
    text = _tool_text(client, "fb_sample_activity", {"seconds": 1})
    rates = re.findall(r"\| records read (?:sequentially|by index) \| -?\d+ \| (\S+) \|", text)
    assert rates, f"no per-second column found:\n{text}"
    for rate in rates:
        assert "," not in rate, f"locale-formatted rate {rate!r} in the sample table"
        assert re.fullmatch(r"-?\d+\.\d+", rate), rate


def test_fb_sample_activity_sees_work_done_inside_the_window(client):
    # Two clients: this one holds the window open while the other scans. MON$ freezes its
    # snapshot per transaction, so a sampler that fails to start a new one reports zero here.
    import subprocess as sp
    import threading

    def scan():
        c = StdioClient(sp.Popen([EXE], stdin=sp.PIPE, stdout=sp.PIPE))  # noqa: S603
        c.call("initialize", {"protocolVersion": "2025-03-26", "capabilities": {},
                              "clientInfo": {"name": "load", "version": "1"}})
        for _ in range(6):
            c.call("tools/call", {"name": "fb_evaluate_goal", "arguments": {
                "goal_type": "query_time_ms",
                "target": "SELECT COUNT(*) FROM CUSTOMERS", "threshold": 60000}})
        c.proc.stdin.close()
        c.proc.terminate()

    t = threading.Thread(target=scan)
    t.start()
    try:
        text = _tool_text(client, "fb_sample_activity", {"seconds": 3})
    finally:
        t.join()
    seq = int(re.search(r"\| records read sequentially \| (-?\d+) \|", text).group(1))
    assert seq > 0, f"a scan ran throughout the window and the sample saw nothing:\n{text}"


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


# --------------------------------------------------------------------------- #
# backup: start returns at once, status tells the truth about what happened
# --------------------------------------------------------------------------- #
def test_backup_start_returns_immediately_and_status_finishes(client):
    started = time.monotonic()
    r = client.call("tools/call", {"name": "fb_backup_start", "arguments": {}})
    elapsed = time.monotonic() - started
    text = r["result"]["content"][0]["text"]

    if r["result"].get("isError") and "firebird.backup_dir" in text:
        pytest.skip("no firebird.backup_dir configured for this run")

    assert not r["result"].get("isError"), text
    assert elapsed < 5, f"fb_backup_start blocked for {elapsed:.1f}s; it must return at once"

    deadline = time.monotonic() + 300
    while time.monotonic() < deadline:
        s = client.call("tools/call", {"name": "fb_backup_status", "arguments": {}})
        status = s["result"]["content"][0]["text"]
        if "still running" not in status:
            break
        time.sleep(2)
    else:
        pytest.fail("backup did not finish within 300s")

    assert "restored into a scratch database" in status, status
