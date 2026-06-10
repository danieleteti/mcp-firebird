def test_initialize_reports_server_name(client):
    r = client.call("ping")
    assert "result" in r

def test_tools_list_contains_fb_tools(client):
    r = client.call("tools/list")
    names = {t["name"] for t in r["result"]["tools"]}
    for expected in {"fb_info", "fb_list_tables", "fb_describe_table",
                     "fb_generate_documentation", "fb_analyze_query",
                     "fb_suggest_indexes", "fb_suggest_index_drops",
                     "fb_evaluate_goal", "fb_audit_table"}:
        assert expected in names

def test_fb_info_returns_engine_version(client):
    r = client.call("tools/call", {"name": "fb_info", "arguments": {}})
    text = r["result"]["content"][0]["text"]
    assert "engine_version" in text

def test_fb_analyze_query_flags_natural_scan(client):
    r = client.call("tools/call", {"name": "fb_analyze_query",
        "arguments": {"sql": "SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'"}})
    text = r["result"]["content"][0]["text"]
    assert "NATURAL" in text.upper()

def test_fb_evaluate_goal_no_natural_scan_not_met(client):
    r = client.call("tools/call", {"name": "fb_evaluate_goal",
        "arguments": {"goal_type": "query_no_natural_scan",
                      "target": "SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'",
                      "threshold": 0}})
    text = r["result"]["content"][0]["text"]
    assert '"met"' in text and ("false" in text.lower())

def test_fb_audit_table_flags_missing_pk(client):
    r = client.call("tools/call", {"name": "fb_audit_table",
        "arguments": {"table_name": "NOPK_LOG"}})
    text = r["result"]["content"][0]["text"]
    assert "PRIMARY KEY" in text.upper()

def test_optimization_goal_prompt_present(client):
    r = client.call("prompts/list")
    names = {p["name"] for p in r["result"]["prompts"]}
    assert "optimization_goal" in names
