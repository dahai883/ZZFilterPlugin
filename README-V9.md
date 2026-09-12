# ZZFilterPlugin v9

v9 is a stability-first diagnostic build for authorized testing of the host app.

Changes from v8:
- Does not hook arbitrary/fuzzy runtime methods (avoids the v7-style crash risk).
- Adds a runtime candidate scanner that records likely list/model/cell selectors without changing them.
- Adds a jailbreak-friendly diagnostic log at `/var/mobile/ZZFilterPlugin-v9.log`, with `/tmp/ZZFilterPlugin-v9.log` as fallback.
- Records scanner summary, candidate class/selector names, and network response structure without dumping response bodies, cookies, or tokens.
- Keeps the existing UI/network counters so the next run can tell whether the problem is the UI hook path or the response schema.

After injection, reproduce one search and one filter action, then run:

    tail -n 200 /var/mobile/ZZFilterPlugin-v9.log

If that path does not exist, try:

    tail -n 200 /tmp/ZZFilterPlugin-v9.log

The build is intentionally diagnostic-first: it does not claim to bypass licensing, activation, authentication, or other security controls.
