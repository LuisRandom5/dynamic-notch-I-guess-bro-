#!/usr/bin/env python3
"""
Hook PermissionRequest de Claude Code -> tarjeta de autorización en Dynamic Notch.

Cuando Claude necesita permiso para una herramienta, muestra en el notch qué quiere hacer
(comando, archivo, URL) con botones Permitir / Rechazar, y espera la decisión.

- Permitir  -> {"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": {"behavior": "allow"}}}
- Rechazar  -> behavior "deny" con el motivo (y la respuesta escrita, si la hay) para Claude.
- Sin respuesta a tiempo o Dynamic Notch cerrado -> no imprime nada y Claude muestra su diálogo normal.
"""
import json
import os
import sys
import urllib.request

AUTHORIZE_URL = "http://127.0.0.1:48123/authorize"
WAIT_SECONDS = 50  # El hook se registra con timeout de 60 s; el notch responde antes


def short(text, limit):
    text = str(text or "").strip()
    return text if len(text) <= limit else text[: limit - 1] + "…"


def describe(tool_name, tool_input):
    """(subtítulo, mensaje, detalle) legibles para la tarjeta."""
    ti = tool_input if isinstance(tool_input, dict) else {}
    path = ti.get("file_path") or ti.get("notebook_path") or ti.get("path") or ""
    name = os.path.basename(str(path)) if path else ""
    if tool_name == "Bash":
        return ("Ejecutar comando", short(ti.get("description") or "Claude quiere ejecutar un comando", 120),
                short(ti.get("command"), 600))
    if tool_name in ("Edit", "MultiEdit", "NotebookEdit"):
        return ("Editar archivo", f"Claude quiere modificar {name}", short(path, 300))
    if tool_name == "Write":
        return ("Escribir archivo", f"Claude quiere crear o reemplazar {name}", short(path, 300))
    if tool_name in ("WebFetch", "WebSearch"):
        return ("Acceso a la web", "Claude quiere consultar internet",
                short(ti.get("url") or ti.get("query"), 300))
    detail = json.dumps(ti, ensure_ascii=False)
    return (f"Usar {tool_name.split('__')[-1]}", f"Claude quiere usar {tool_name}", short(detail, 400))


def main():
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except Exception:
        return
    subtitle, message, detail = describe(data.get("tool_name", ""), data.get("tool_input", {}))
    request = {
        "type": "permission",
        "title": "Claude",
        "subtitle": subtitle,
        "message": message,
        "command": detail,
        "enableTextReply": True,
        "timeout": WAIT_SECONDS,
        "options": [
            {"id": "deny", "label": "Rechazar", "isDestructive": True},
            {"id": "allow", "label": "Permitir", "isPrimary": True},
        ],
    }
    try:
        req = urllib.request.Request(
            AUTHORIZE_URL,
            data=json.dumps(request).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=WAIT_SECONDS + 3) as res:
            answer = json.loads(res.read().decode("utf-8") or "{}")
    except Exception:
        return  # Notch cerrado, timeout (408) o error: Claude sigue con su diálogo normal

    decision = answer.get("decision") or answer.get("action")
    if decision == "allow":
        out = {"behavior": "allow"}
    elif decision == "deny":
        reason = "Rechazado por el usuario desde Dynamic Notch"
        reply = answer.get("reply")
        if reply:
            reason += f": {reply}"
        out = {"behavior": "deny", "message": reason}
    else:
        return
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": out}}))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
