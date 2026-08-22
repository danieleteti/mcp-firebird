# Editions & licensing

[← back to the README](../README.md)

Short version: **if you are using it on your own databases, it is free, and it stays free.**
No trial, no expiry, no licence key, no seat count, no limit on how many tables or databases
you point it at. Install it, use it in production, use it every day. Nothing phones home.

The one thing you cannot do is hand it to somebody else.

MCP Firebird is **source-available, not open source** as the Open Source Initiative defines the
term. Saying that plainly matters more than a badge: from **v0.2.0** it is licensed under the
[PolyForm Internal Use License 1.0.0](../LICENSE). Versions up to and including **v0.1.0 were
released under Apache-2.0 and remain so** for everyone who received them: a licence already
granted cannot be revoked, and this project does not pretend otherwise.

### What you may do, free of charge

- Run it against any database you like: yours, your employer's, your client's. Development,
  staging, production, all of them.
- Run it at any scale. A hundred tables or ten thousand; one database or fifty.
- **Use it in your consulting practice.** Diagnose, tune, audit and support your clients'
  Firebird databases with it, and charge them for your time. It is your tool; keep it.
- Read the source. All of it. Learn from it, and use what you learn.
- Modify it. Fix a bug, add a detector, change a message. Run your modified build.
- Use it in a company of any size, commercial or not, for-profit or not, with no fee and no
  registration.

### What requires a licence

One idea, expressed three ways: **letting the software out of your hands.**

- **Redistributing it.** Publishing a fork, uploading a build, putting it on a CD, sending the
  binary to a customer, leaving it installed on a client's server when the engagement ends.
- **Embedding it in a product you sell.** Shipping it inside your ERP, your installer, your
  Docker image, your appliance, in source or binary form, modified or not.
- **Offering it as a service.** Standing it up behind an API or a hosted agent that people
  outside your organisation can reach.

Where the software runs, and whose database it examines, is your business. Where copies of it end
up is ours.

If your case is one of these, the licence exists and it is not expensive relative to what you are
building with it. Write to **d.teti@bittime.it**.

### When you need to buy a licence: worked cases

| Your situation | Licence needed? |
|---|---|
| Your DBA runs it against the company's production Firebird every morning | **No.** |
| Your team of forty developers each run it locally | **No.** No seat count, no registration. |
| You are a consultant, and you run it from your laptop against your client's database | **No.** It is your tool and it stays your tool. Charge them what you like. |
| Same, but you are sitting at the client's desk, running it on their server | **No.** Take it with you when you leave. |
| You leave a copy of it installed on your client's server when you go | **Yes.** The software left your hands. |
| You are a hosting provider, and you run it against the databases you host | **No.** |
| ...and you give your customers a button that runs it for them | **Yes.** That is offering it as a service. |
| You ship it inside your Delphi ERP so your customers get "AI database tuning" | **Yes.** Embedding in a product you supply. |
| You publish a fork on GitHub with your improvements | **Yes.** Talk to us first: we would rather merge it. |
| You are writing a blog post, a talk, or a university course about it | **No.** Read it, quote it, teach it. |
| You are on `v0.1.0`, which you obtained under Apache-2.0 | **No.** That version stays Apache-2.0 for you forever. |

The rule behind the table, if you would rather reason than look things up: **ask where the
software ends up, never what you did with it.** As long as every copy of MCP Firebird stays in
your hands, you owe nothing: not for the scale you run it at, not for the money it makes you,
not for whose database you point it at. The moment a copy leaves, we should talk.

There is also a paid **[Enterprise edition](#enterprise-edition)**, a different product, not a
crippled free tier. Everything described in the rest of this README is in the free one.

---

## Enterprise edition

### Where the free edition ends

The free edition is not a demo, and it is not the Enterprise edition with the good parts taken
out. It is the whole of one job, done properly: **it makes the database answer for itself.**

It reads your schema. It explains your plans. It finds the index you are missing and the four
you do not need. It catches the missing primary key, the stale statistics, the transaction
pinning garbage collection since Tuesday. For most databases, most of the time, that is where
the problem is, and that is where the problem gets fixed. Plenty of people will use it for years
and never need anything else, and they will never be asked for a cent.

Then one day it comes back and tells you the truth: *your schema is fine. Your indexes are fine.
No natural scans, no external sorts, statistics fresh.* And the database is still slow.

**That is the line.** The free edition has answered its question honestly and completely, and the
answer is that the problem is not in the database. It is in the machine underneath it, and no
`SELECT` will ever show you that. Not because the tool is holding back, but because SQL cannot
see outside its own process.

### Where the Enterprise edition begins

It is 2 GB of page buffers on a host with 8 GB of RAM. It is `forced writes` switched off for a
batch load two years ago and never switched back. It is `LockHashSlots` still at its 2010 default
under four hundred connections, an index four levels deep, a bugcheck written to `firebird.log`
every Tuesday at 03:00 that nobody reads.

The free edition connects to Firebird the way your application does: an ordinary SQL connection,
with ordinary rights. **The Enterprise edition asks for more.** It attaches to the Services
Manager as an administrator (which is how it streams `firebird.log` back, drives the Trace API,
and reads the physical storage report), and it reads the server's own configuration and hardware.
That is a different privilege, a different blast radius, and a different conversation with
whoever owns the server. Hence a different product.

And it does not stop at telling you what is wrong. **It runs the experiment.** Capture a baseline
under real load, change exactly one parameter, measure again, compare the distributions (the p95
and the p99, never the average), and keep the change or put it back. Nobody sells you a number.
The database tells you the number.

| | Free | Enterprise |
|---|---|---|
| Schema, docs, plans, index advice, schema audit | ✅ | ✅ |
| Transaction & sweep health (`MON$`) | ✅ | ✅ |
| `fb_diagnose`: the entry point, what is already known and the ordered route to run next | ❌ | ✅ |
| `fb_analyze_config`: `firebird.conf` / `databases.conf`, read against this engine, this architecture, this workload | ❌ | ✅ |
| `fb_analyze_storage`: index depth, page fill ratios, record-version chains, page distribution | ❌ | ✅ |
| `fb_parse_log` (`firebird.log`): errors, sweeps, bugchecks, crashes | ❌ | ✅ |
| `fb_capture_trace` (Trace API): the real workload, and what actually costs | ❌ | ✅ |
| `fb_trace_start` / `fb_trace_status` / `fb_trace_stop`: the long window, up to two hours of trace drained in the background | ❌ | ✅ |
| `fb_analyze_host`: RAM against page buffers, CPU against parallel workers, storage class | ❌ | ✅ |
| Baselines, distributions, before/after comparison: the experiment | ❌ | ✅ |

Note what is *not* in that table: nothing was moved out of the free edition to build the paid one.
Every free tool stays free, and the ones still to be written stay on the side of the line they
belong to. The boundary is not a paywall drawn through a feature list. It is the line between
querying a database and administering a server, and the free edition was always on one side of it.

The hard part was never parsing `firebird.conf`; anyone can parse an INI file. And nobody can
honestly hand you the right value for `LockHashSlots`: **Firebird's own documentation states no
optimum for it**, nor for the page cache, nor for the sort cache. What experience buys you is
knowing *which* parameter your symptom implicates: that throughput collapsing under concurrency
while the CPU stays calm points at the lock table and never at the page cache. That map is the
product. The value at the end of it is not asserted. It is measured, on your database, under
your load.

You will know when you need it, because the free edition will have told you.

The nine tools above already appear in `tools/list` in the free edition, so your assistant can see
them and say what it would do with them. Call one and it tells you how to get it.

**Enterprise licences, commercial licences and support subscriptions:** d.teti@bittime.it
