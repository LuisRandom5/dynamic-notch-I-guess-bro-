#!/usr/bin/env python3
"""
Status line de Claude Code que además le reporta a Dynamic Notch el uso de la suscripción.

Claude Code le pasa por stdin un JSON que (en planes Pro/Max) incluye:
  rate_limits.five_hour.used_percentage / resets_at   (límite de la sesión de 5 h)
  rate_limits.seven_day.used_percentage / resets_at   (límite semanal)
El script lo reenvía a POST 127.0.0.1:48123/claude/usage y lo guarda en
/tmp/dynamic_notch_claude/usage.json. Imprime una línea corta para la status line.
"""
import json
import os
import sys
import time
import urllib.request

STATE_DIR = "/tmp/dynamic_notch_claude"


def main():
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except Exception:
        data = {}
    limits = data.get("rate_limits") or {}
    five = limits.get("five_hour") or {}
    week = limits.get("seven_day") or {}
    usage = {
        "session": str(data.get("session_id") or "")[:8],
        "fiveHourUsed": five.get("used_percentage"),
        "fiveHourResetsAt": five.get("resets_at"),
        "sevenDayUsed": week.get("used_percentage"),
        "sevenDayResetsAt": week.get("resets_at"),
        "updatedAt": time.time(),
    }
    if usage["fiveHourUsed"] is not None or usage["sevenDayUsed"] is not None:
        try:
            os.makedirs(STATE_DIR, exist_ok=True)
            with open(os.path.join(STATE_DIR, "usage.json"), "w") as fh:
                json.dump(usage, fh)
            req = urllib.request.Request(
                "http://127.0.0.1:48123/claude/usage",
                data=json.dumps(usage).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            urllib.request.urlopen(req, timeout=0.3).read()
        except Exception:
            pass

    model = (data.get("model") or {}).get("display_name") or "Claude"
    parts = [model]
    if usage["fiveHourUsed"] is not None:
        parts.append(f"sesión {100 - round(usage['fiveHourUsed'])}% libre")
    if usage["sevenDayUsed"] is not None:
        parts.append(f"semana {100 - round(usage['sevenDayUsed'])}% libre")
    print(" · ".join(parts))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print("Claude")
