#!/usr/bin/env python3
"""
Hook de Claude Code -> Dynamic Notch.

Claude Code ejecuta este script en sus eventos de ciclo de vida (UserPromptSubmit, PreToolUse,
PostToolUse, Notification, Stop, SessionEnd) y le pasa un JSON por stdin. El script mantiene el
estado de cada sesión en /tmp y envía un resumen a Dynamic Notch (POST 127.0.0.1:48123/claude),
que lo muestra como la bolita satélite de Claude.

El progreso sale de la lista de tareas de Claude (herramienta update_plan) cuando existe:
(pasos completados + avance dentro del paso actual) / total. Sin lista, avanza de forma
asintótica con cada herramienta. Siempre es monótono dentro de un turno.

Reglas: nunca bloquear ni alterar a Claude. Sin salida por stdout, siempre exit 0, timeouts cortos.
"""
import fcntl
import json
import math
import os
import sys
import time
import urllib.request

IPC_URL = "http://127.0.0.1:48123/claude"
STATE_DIR = "/tmp/dynamic_notch_claude"
PROGRESS_CEILING = 0.97


def post(payload):
    try:
        req = urllib.request.Request(
            IPC_URL,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        urllib.request.urlopen(req, timeout=0.3).read()
    except Exception:
        pass  # Dynamic Notch no está abierto: no pasa nada


def basename(path):
    return os.path.basename(str(path).rstrip("/")) if path else ""


def short(text, limit=72):
    text = " ".join(str(text).split())
    return text if len(text) <= limit else text[: limit - 1] + "…"


def describe_tool(name, tool_input):
    """Frase corta y humana de lo que Claude está haciendo."""
    ti = tool_input if isinstance(tool_input, dict) else {}
    fname = basename(ti.get("file_path") or ti.get("notebook_path") or ti.get("path") or "")
    if name == "Read":
        return ("doc.text", f"Leyendo {fname}" if fname else "Leyendo archivos")
    if name in ("Edit", "MultiEdit", "NotebookEdit"):
        return ("pencil", f"Editando {fname}" if fname else "Editando código")
    if name == "Write":
        return ("square.and.pencil", f"Escribiendo {fname}" if fname else "Creando archivo")
    if name == "Bash":
        desc = ti.get("description") or ""
        if desc:
            return ("terminal", short(desc))
        cmd = (ti.get("command") or "").strip().split()
        return ("terminal", f"Ejecutando {cmd[0]}" if cmd else "Ejecutando comando")
    if name in ("Grep", "Glob"):
        pattern = ti.get("pattern") or ""
        return ("magnifyingglass", f"Buscando “{short(pattern, 28)}”" if pattern else "Buscando en el código")
    if name in ("WebSearch", "WebFetch"):
        return ("globe", "Investigando en la web")
    if name in ("Agent", "Task"):
        return ("person.2", short("Delegando: " + (ti.get("description") or "subtarea")))
    if name == "Skill":
        return ("wand.and.stars", f"Usando skill {ti.get('skill', '')}".strip())
    if name == "ToolSearch":
        return ("shippingbox", "Cargando herramientas")
    if name.endswith("update_plan"):
        return ("checklist", "Actualizando el plan")
    if name.endswith("wrap_up"):
        return ("checkmark.seal", "Cerrando el turno")
    if "Browser" in name or "chrome" in name:
        return ("safari", "Usando el navegador")
    if "Simulator" in name:
        return ("iphone", "Probando en el simulador")
    if name.startswith("mcp__"):
        return ("puzzlepiece", short(name.split("__")[-1].replace("_", " ").capitalize(), 40))
    return ("sparkle", short(name, 40))


def apply_plan_update(state, tool_input):
    """Replica la semántica de update_plan: items (lista completa), advance, done, start."""
    ti = tool_input if isinstance(tool_input, dict) else {}
    steps = state.get("steps", [])
    if isinstance(ti.get("items"), list):
        steps = [
            {"title": short(it.get("content", ""), 60), "status": it.get("status", "pending")}
            for it in ti["items"]
            if isinstance(it, dict)
        ]
    if ti.get("advance"):
        idx = next((i for i, s in enumerate(steps) if s["status"] == "in_progress"), None)
        if idx is not None:
            steps[idx]["status"] = "completed"
            nxt = next((i for i in range(idx + 1, len(steps)) if steps[i]["status"] == "pending"), None)
            if nxt is not None:
                steps[nxt]["status"] = "in_progress"
    for n in ti.get("done", []) or []:
        if isinstance(n, int) and 1 <= n <= len(steps):
            steps[n - 1]["status"] = "completed"
    start = ti.get("start")
    if isinstance(start, int) and 1 <= start <= len(steps):
        for s in steps:
            if s["status"] == "in_progress":
                s["status"] = "pending"
        steps[start - 1]["status"] = "in_progress"
    current = next((i for i, s in enumerate(steps) if s["status"] == "in_progress"), None)
    if current != state.get("current_step"):
        state["within_step"] = 0.0  # Nuevo paso: el avance interno empieza de cero
    state["current_step"] = current
    state["steps"] = steps


def compute_progress(state):
    steps = state.get("steps", [])
    if steps:
        total = len(steps)
        done = sum(1 for s in steps if s["status"] == "completed")
        within = state.get("within_step", 0.0) if state.get("current_step") is not None else 0.0
        raw = (done + within) / total
    else:
        # Sin plan: curva asintótica por número de herramientas
        raw = 0.9 * (1.0 - math.exp(-state.get("tools", 0) / 18.0))
    progress = max(state.get("progress", 0.0), min(PROGRESS_CEILING, raw))
    state["progress"] = progress
    return progress


def new_turn_state(prompt, now):
    first_line = next((l for l in str(prompt).splitlines() if l.strip()), "")
    return {
        "title": short(first_line, 64) or "Nueva tarea",
        "started_at": now,
        "state": "working",
        "steps": [],
        "current_step": None,
        "within_step": 0.0,
        "progress": 0.02,
        "tools": 0,
        "files": [],
        "icon": "sparkle",
        "action": "Pensando…",
    }


def main():
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except Exception:
        return
    event = data.get("hook_event_name", "")
    session = str(data.get("session_id") or "default")
    now = time.time()

    os.makedirs(STATE_DIR, exist_ok=True)
    path = os.path.join(STATE_DIR, f"{session}.json")
    with open(path, "a+") as fh:
        fcntl.flock(fh, fcntl.LOCK_EX)  # Herramientas en paralelo: un escritor a la vez
        fh.seek(0)
        try:
            state = json.loads(fh.read() or "{}")
        except Exception:
            state = {}

        tool_name = data.get("tool_name", "")
        tool_input = data.get("tool_input", {})

        if event == "UserPromptSubmit" or not state:
            state = new_turn_state(data.get("prompt", ""), now)
            state["project"] = basename(data.get("cwd", ""))

        if event == "PreToolUse":
            state["state"] = "working"
            state["icon"], state["action"] = describe_tool(tool_name, tool_input)
        elif event == "PostToolUse":
            if state.get("state") == "waiting":
                # El usuario ya respondió al permiso: no dejar el aviso pegado
                state["icon"], state["action"] = "sparkle", "Continuando…"
            state["state"] = "working"
            state["tools"] = state.get("tools", 0) + 1
            if tool_name.endswith("update_plan"):
                apply_plan_update(state, tool_input)
            elif state.get("current_step") is not None:
                # Cada herramienta avanza una fracción de lo que falta del paso actual (máx. 85% del paso)
                w = state.get("within_step", 0.0)
                state["within_step"] = w + (0.85 - w) * 0.18
            if tool_name in ("Edit", "MultiEdit", "Write", "NotebookEdit"):
                f = basename((tool_input or {}).get("file_path") or (tool_input or {}).get("notebook_path"))
                if f and f not in state["files"]:
                    state["files"].append(f)
        elif event == "Notification":
            state["state"] = "waiting"
            state["icon"] = "hand.raised"
            state["action"] = short(data.get("message") or "Esperando tu respuesta")
        elif event == "Stop":
            state["state"] = "done"
            state["progress"] = 1.0
            for s in state.get("steps", []):
                s["status"] = "completed"
            state["icon"] = "checkmark"
            state["action"] = "Listo"
        elif event == "SessionEnd":
            state["state"] = "ended"

        if event not in ("Stop", "SessionEnd"):
            compute_progress(state)

        fh.seek(0)
        fh.truncate()
        json.dump(state, fh)

    current = state.get("current_step")
    steps = state.get("steps", [])
    post({
        "session": session[:8],
        "event": event,
        "state": state.get("state", "working"),
        "title": state.get("title", ""),
        "project": state.get("project", ""),
        "progress": state.get("progress", 0.0),
        "steps": steps,
        "stepIndex": current,
        "action": state.get("action", ""),
        "icon": state.get("icon", "sparkle"),
        "tools": state.get("tools", 0),
        "files": state.get("files", []),
        "startedAt": state.get("started_at", now),
    })
    if event == "SessionEnd":
        try:
            os.remove(path)
        except Exception:
            pass


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
