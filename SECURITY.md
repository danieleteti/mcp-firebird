# Security Policy

## Supported versions

MCP Firebird is pre-1.0; security fixes land on the latest `main`.

## Reporting a vulnerability

Please report vulnerabilities **privately** by email to **d.teti@bittime.it** — do not open a
public issue. Include repro steps, affected Firebird/engine version, and impact. You will get an
acknowledgement and a fix timeline.

## Safety model

The server is **read-only**: it exposes no tool that runs DDL or write SQL. Write tools (planned
for M3) will ship behind an explicit opt-in setting. It connects to a single configured database
and never writes to stdout outside the MCP transport. Treat the `.env` connection credentials as secrets — only `bin/.env.example`
is committed.
