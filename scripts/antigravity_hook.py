#!/usr/bin/env python3
"""
Antigravity official hook bridge for Dynamic Notch.
Handles lifecycle events: SessionStart, PreToolUse, PostToolUse, and Stop.
Provides two-way command authorization and real-time live activity HUD updates.
"""
import sys
import json
import urllib.request
import urllib.error
import os

IPC_BASE = "http://127.0.0.1:48123"

def send_ipc(endpoint, data, timeout=2.0):
    try:
        url = f"{IPC_BASE}{endpoint}"
        req = urllib.request.Request(
            url,
            data=json.dumps(data).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=timeout) as res:
            res_body = res.read().decode("utf-8")
            return json.loads(res_body) if res_body else {}
    except Exception as e:
        return None

TASK_SESSION_FILE = "/tmp/antigravity_task_session.json"

def get_task_session():
    import time
    now = time.time()
    try:
        if os.path.exists(TASK_SESSION_FILE):
            with open(TASK_SESSION_FILE, "r") as f:
                data = json.load(f)
                # Si han pasado menos de 180s y no está finalizado, mantener la sesión de tarea acumulada
                if now - data.get("last_updated", now) < 180 and not data.get("completed", False):
                    return data
    except Exception:
        pass
    return new_task_session(now)

def new_task_session(now):
    return {
        "start_time": now,
        "last_updated": now,
        "tools_count": 0,
        "progress": 0.12,
        "completed": False,
        "retry": 0,              # Ciclos de corrección tras un build/test fallido
        "in_retry": False,       # True mientras se corrige el último fallo
        "verify_started": None,  # Inicio del último build/test (para medir la duración de un ciclo)
        "last_cycle_sec": None,  # Duración del último ciclo build/test → fallo
        "eta": None
    }

# Progreso máximo antes de que el agente termine (el 100% solo llega con Stop)
PROGRESS_CEILING = 0.96

def advance_progress(session, phase_min_prog):
    """Avance monótono y asintótico: cada herramienta recorre una fracción de lo que falta,
    así la barra nunca se congela en el tope ni retrocede, aunque haya muchos reintentos."""
    old_prog = session.get("progress", 0.12)
    in_retry = session.get("in_retry", False)
    # En un reintento el avance es más fino: la tarea "se alarga" sin dar marcha atrás
    fraction = 0.06 if in_retry else 0.10
    step = max(0.004, (PROGRESS_CEILING - old_prog) * fraction)
    # Durante un reintento el mínimo de fase no hace saltar la barra (p. ej. el build vuelve a pedir 0.85)
    floor = old_prog if in_retry else max(old_prog, phase_min_prog)
    new_prog = min(PROGRESS_CEILING, max(floor, old_prog + step))
    session["progress"] = new_prog
    return new_prog

def estimate_remaining(session, progress, now):
    """ETA por ritmo observado (tiempo transcurrido / progreso), suavizado.
    En un reintento nunca es menor que la duración del último ciclo build → fallo."""
    elapsed = max(1.0, now - session.get("start_time", now))
    rate_eta = elapsed * (1.0 - progress) / max(0.05, progress)
    prev = session.get("eta")
    eta = rate_eta if prev is None else (prev * 0.6 + rate_eta * 0.4)
    if session.get("in_retry") and session.get("last_cycle_sec"):
        eta = max(eta, session["last_cycle_sec"])
    eta = int(max(3, min(180, round(eta))))
    session["eta"] = eta
    return eta

VERIFY_MARKERS = ("build_app.sh", "swift build", "swift test", "xcodebuild", "pytest", "npm test", "npm run build")

def is_verify_command(cmd):
    return any(m in cmd for m in VERIFY_MARKERS)

FAILURE_MARKERS = ("error:", "BUILD FAILED", "** BUILD FAILED **", "FAILED", "Traceback (most recent call last)",
                   "fatal error", "Compiling failed", "tests failed", "npm ERR!")

def tool_failed(payload, tool_call):
    """Detecta (de forma defensiva) si la herramienta terminó con error."""
    candidates = [payload.get(k) for k in ("toolResult", "tool_response", "result", "output", "response")]
    candidates.append(tool_call.get("result"))
    for c in candidates:
        if c is None:
            continue
        if isinstance(c, dict):
            for k in ("exitCode", "exit_code", "returnCode", "return_code", "code"):
                code = c.get(k)
                if isinstance(code, int) and code != 0:
                    return True
            if c.get("success") is False or c.get("is_error") is True or c.get("isError") is True:
                return True
            text = " ".join(str(c.get(k, "")) for k in ("stdout", "stderr", "output", "error", "content"))
        else:
            text = str(c)
        if any(m in text for m in FAILURE_MARKERS):
            return True
    for k in ("exitCode", "exit_code"):
        code = payload.get(k)
        if isinstance(code, int) and code != 0:
            return True
    return payload.get("success") is False or payload.get("isError") is True

def save_task_session(session):
    import time
    session["last_updated"] = time.time()
    try:
        with open(TASK_SESSION_FILE, "w") as f:
            json.dump(session, f)
    except Exception:
        pass

def notify_tool_progress(tool_name, args):
    try:
        file_target = args.get("TargetFile") or args.get("AbsolutePath") or ""
        cmd = args.get("CommandLine", "")
        
        step_title = ""
        status_text = "Trabajando..."
        phase_min_prog = 0.15
        added = 0
        deleted = 0
        
        fname = file_target.split("/")[-1] if file_target else ""
        
        if "replace" in tool_name:
            step_title = f"Edit {fname}" if fname else "Edit Code"
            status_text = "Guardando cambios..."
            phase_min_prog = 0.55
            rep = args.get("ReplacementContent", "")
            target = args.get("TargetContent", "")
            if rep:
                added += len(rep.splitlines())
            if target:
                deleted += len(target.splitlines())
            chunks = args.get("ReplacementChunks", [])
            if chunks:
                for c in chunks:
                    added += len(c.get("ReplacementContent", "").splitlines())
                    deleted += len(c.get("TargetContent", "").splitlines())
        elif "write" in tool_name:
            step_title = f"Write {fname}" if fname else "Create File"
            status_text = "Escribiendo archivo..."
            phase_min_prog = 0.60
            code = args.get("CodeContent", "")
            added += len(code.splitlines())
        elif "view" in tool_name or "read" in tool_name:
            step_title = f"Read {fname}" if fname else "Read File"
            status_text = "Analizando código..."
            phase_min_prog = 0.25
        elif "grep" in tool_name or "list" in tool_name or "search" in tool_name:
            query = args.get("Query", "") or args.get("query", "")
            step_title = f"Search '{query[:16]}'" if query else "Buscar en código"
            status_text = "Investigando..."
            phase_min_prog = 0.20
        elif "run_command" in tool_name:
            first = cmd.split()[0] if cmd.split() else "command"
            clean_cmd = cmd.strip()
            if "./scripts/build_app.sh" in clean_cmd:
                step_title = "Build Dynamic Notch"
                status_text = "Compilando proyecto..."
                phase_min_prog = 0.85
            elif "screencapture" in clean_cmd:
                step_title = "Captura de pantalla"
                status_text = "Inspeccionando..."
                phase_min_prog = 0.70
            elif "git" in clean_cmd:
                step_title = f"Git {first}"
                status_text = "Verificando repo..."
                phase_min_prog = 0.75
            else:
                step_title = f"Run {first}"
                status_text = "Ejecutando proceso..."
                phase_min_prog = 0.65
        else:
            step_title = tool_name.replace("_", " ").title()
            status_text = "Trabajando..."
            phase_min_prog = 0.30
            
        import time
        now = time.time()
        session = get_task_session()
        session["tools_count"] = session.get("tools_count", 0) + 1
        
        if "run_command" in tool_name and is_verify_command(cmd):
            session["verify_started"] = now
        
        # Progreso acumulativo y monótono: jamás disminuye ni se reinicia a cero
        final_prog = advance_progress(session, phase_min_prog)
        
        retry = session.get("retry", 0)
        if session.get("in_retry"):
            # Sub-fase de reintento: el usuario ve que el agente está corrigiendo, no que se colgó
            status_text = f"Reintento {retry + 1}: corrigiendo errores..."
            if "run_command" in tool_name and is_verify_command(cmd):
                status_text = f"Reintento {retry + 1}: verificando..."
        
        remaining_sec = estimate_remaining(session, final_prog, now)
        save_task_session(session)
        remaining_str = f"~ {remaining_sec}s"
        
        display_file = fname if fname else (cmd[:28] if cmd else "Sources/DynamicNotch")
        progress_data = {
            "event": "step",
            "agent": "Antigravity",
            "task": "Dynamic Notch",
            "step": step_title,
            "file": display_file,
            "status": status_text,
            "added": added,
            "deleted": deleted,
            "diff": {"added": added, "deleted": deleted},
            "progress": final_prog,
            "remaining": remaining_sec,
            "remaining_text": remaining_str
        }
        send_ipc("/progress", progress_data, timeout=0.8)
    except Exception:
        pass

def handle_session_start():
    try:
        import time
        now = time.time()
        session = new_task_session(now)
        save_task_session(session)
        send_ipc("/progress", {
            "event": "start",
            "agent": "Antigravity",
            "task": "Dynamic Notch",
            "step": "Iniciando análisis",
            "status": "Iniciando...",
            "progress": 0.12,
            "remaining": 50,
            "remaining_text": "~ 50s"
        }, timeout=1.0)
    except Exception:
        pass
    print(json.dumps({}))

def handle_pre_tool():
    try:
        raw_input = sys.stdin.read()
        if not raw_input.strip():
            print(json.dumps({"decision": "allow"}))
            return
        
        payload = json.loads(raw_input)
        tool_call = payload.get("toolCall", {})
        tool_name = tool_call.get("name", "")
        args = tool_call.get("args", {})
        
        notify_tool_progress(tool_name, args)
        
        if tool_name != "run_command":
            print(json.dumps({"decision": "allow"}))
            return
        
        cmd = args.get("CommandLine", "")
        cmd_clean = cmd.strip()
        
        # Prefijos seguros permitidos directamente
        safe_prefixes = [
            "git", "cat", "tail", "head", "grep", "rg", "ls", "ps", "pgrep",
            "kill", "killall", "curl", "find", "echo", "diff", "stat", "file",
            "which", "xcrun", "swift", "xcodebuild", "defaults", "osascript",
            "open", "sw_vers", "uname", "lsof", "sqlite3", "python3", "python",
            "screencapture", "sips",
            "./scripts/build_app.sh", "./scripts/", "mkdir", "cp", "mv", "touch"
        ]
        first_token = cmd_clean.split()[0] if cmd_clean.split() else ""
        if any(cmd_clean.startswith(prefix) for prefix in safe_prefixes) or first_token in safe_prefixes:
            # Si no es destructivo extremo ni sudo, auto-permitir
            if not ("rm -rf" in cmd_clean or "sudo" in cmd_clean):
                print(json.dumps({"decision": "allow"}))
                return
            
        # Requiere autorización: suspender conexión en /authorize hasta decisión del usuario (25s timeout)
        req_data = {
            "type": "permission",
            "title": "Antigravity",
            "subtitle": "Autorización de Comando",
            "message": "¿Ejecutar en terminal?",
            "command": cmd,
            "enableTextReply": True,
            "timeout": 25.0,
            "options": [
                {"id": "deny", "label": "Rechazar", "isDestructive": True},
                {"id": "allow", "label": "Permitir", "isPrimary": True}
            ]
        }
        
        res = send_ipc("/authorize", req_data, timeout=27.0)
        if res:
            decision = res.get("decision") or res.get("action", "")
            if decision == "allow":
                print(json.dumps({"decision": "allow"}))
            else:
                reason = res.get("reason") or "Rechazado por el usuario desde Dynamic Notch"
                reply = res.get("reply")
                if reply and reply != "null":
                    reason += f": {reply}"
                print(json.dumps({"decision": "deny", "reason": reason}))
        else:
            # Fallback a ask en caso de que Dynamic Notch no responda
            print(json.dumps({"decision": "ask", "reason": "Dynamic Notch no disponible"}))
            
    except Exception as e:
        print(json.dumps({"decision": "ask", "reason": str(e)}))

def handle_post_tool():
    try:
        raw_input = sys.stdin.read()
        if raw_input.strip():
            import time
            now = time.time()
            payload = json.loads(raw_input)
            tool_call = payload.get("toolCall", {})
            tool_name = tool_call.get("name", "")
            cmd = tool_call.get("args", {}).get("CommandLine", "")
            session = get_task_session()
            prog = session.get("progress", 0.50)
            status = "Avanzando..."
            step = f"Completado {tool_name}"
            
            if "run_command" in tool_name and is_verify_command(cmd):
                started = session.get("verify_started")
                if tool_failed(payload, tool_call):
                    # Fallo de build/test: abrir (o continuar) un ciclo de reintento sin retroceder la barra
                    if started:
                        session["last_cycle_sec"] = max(5.0, now - started)
                    session["in_retry"] = True
                    session["retry"] = session.get("retry", 0) + 1
                    status = f"Reintento {session['retry'] + 1}: corrigiendo errores..."
                    step = "Build con errores"
                else:
                    session["in_retry"] = False
                    status = "Verificación correcta"
                session["verify_started"] = None
            elif session.get("in_retry"):
                status = f"Reintento {session.get('retry', 0) + 1}: corrigiendo errores..."
            
            eta = estimate_remaining(session, prog, now)
            save_task_session(session)
            send_ipc("/progress", {
                "event": "step_done",
                "agent": "Antigravity",
                "step": step,
                "status": status,
                "progress": prog,
                "retry": session.get("retry", 0),
                "remaining": eta,
                "remaining_text": f"~ {eta}s"
            }, timeout=0.8)
    except Exception:
        pass
    print(json.dumps({}))

def handle_stop():
    try:
        session = get_task_session()
        session["completed"] = True
        session["progress"] = 1.0
        save_task_session(session)
            
        send_ipc("/progress", {
            "event": "finish",
            "agent": "Antigravity",
            "task": "Tarea Completada",
            "status": "Completado • Listo",
            "completed": True,
            "progress": 1.0,
            "remaining": 0,
            "remaining_text": "Listo"
        }, timeout=2.0)
    except Exception:
        pass
    # Contract for stop hook is {}
    print(json.dumps({}))

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "pre_tool"
    if mode == "session_start":
        handle_session_start()
    elif mode == "post_tool":
        handle_post_tool()
    elif mode == "stop":
        handle_stop()
    else:
        handle_pre_tool()

if __name__ == "__main__":
    main()
