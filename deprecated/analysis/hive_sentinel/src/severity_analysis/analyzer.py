import json


def analyze_severity(entry):
    reasons = set()
    score = 0

    # Check for unexpected exec
    exec_id = entry.get("process_exec", {}).get("process", {}).get("exec_id", "")
    reason = (
        "⚠️ Suspicious command execution detected: Marked as 'unexpected' execution."
    )
    if "unexpected" in exec_id.lower() and reason not in reasons:
        reasons.add(reason)
        score += 3

    # Check for root privilege and execution context
    proc = entry.get("process_exec", {}).get("process", {})
    if proc.get("uid") == 0 and proc.get("auid") == 0:
        if not proc.get("in_init_tree", True):
            reason = "⚠️ Root-level command executed outside the normal init process tree. Possible direct shell access."
            if reason not in reasons:
                reasons.add(reason)
                score += 2
        else:
            reason = "⚠️ Command executed with root privileges."
            if reason not in reasons:
                reasons.add(reason)
                score += 1

    # Check if arguments indicate apt or update usage
    args = proc.get("arguments", "").lower()
    reason = "⚠️ Detected package manager command (e.g., apt update). Could indicate installation attempt."
    if ("apt" in args or "update" in args) and reason not in reasons:
        reasons.add(reason)
        score += 1.3

    # DNS logs analysis
    dns_logs = entry.get("dns_logs", [])
    for d in dns_logs:
        qname = json.loads(d.get("req_body", "{}"))["queries"][0]["name"]
        if "security.ubuntu.com" in qname:
            reason = "⚠️ DNS query to security.ubuntu.com detected. Indicates interactive package installation."
            if reason not in reasons:
                reasons.add(reason)
                score += 1.5

    # HTTP logs: APT-like download patterns
    http_logs = entry.get("http_logs", [])
    for h in http_logs:
        if "ubuntu.com" in h.get("req_headers", "") and h.get("req_path", "").endswith(
            "InRelease"
        ):
            reason = "⚠️ HTTP request to Ubuntu archive/security servers for InRelease files. Indicates package list update."
            if reason not in reasons:
                reasons.add(reason)
                score += 1

    # Final severity mapping
    if score <= 2:
        severity = "Low"
    elif score <= 5:
        severity = "Medium"
    elif score <= 7:
        severity = "High"
    else:
        severity = "Critical"

    return {
        "pod": entry.get("pod_name"),
        "pid": entry.get("pid"),
        "timestamp": entry.get("time", "N/A"),
        "severity": severity,
        "reasons": sorted(reasons),
        "score": score,
    }
