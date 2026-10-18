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

def notify_tool_progress(tool_name, args):
    try:
        file_target = args.get("TargetFile") or args.get("AbsolutePath") or ""
        cmd = args.get("CommandLine", "")
        
        step_title = ""
        status_text = "Trabajando..."
        added = 0
        deleted = 0
        
        fname = file_target.split("/")[-1] if file_target else ""
        
        if "replace" in tool_name:
            step_title = f"Edit {fname}" if fname else "Edit Code"
            status_text = "Guardando..."
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
            status_text = "Escribiendo..."
            code = args.get("CodeContent", "")
            added += len(code.splitlines())
        elif "view" in tool_name or "read" in tool_name:
            step_title = f"Read {fname}" if fname else "Read File"
            status_text = "Leyendo..."
        elif "grep" in tool_name or "list" in tool_name or "search" in tool_name:
            query = args.get("Query", "") or args.get("query", "")
            step_title = f"Search '{query[:16]}'" if query else "Buscar en código"
            status_text = "Buscando..."
        elif "run_command" in tool_name:
            first = cmd.split()[0] if cmd.split() else "command"
            clean_cmd = cmd.strip()
            if "./scripts/build_app.sh" in clean_cmd:
                step_title = "Build Dynamic Notch"
                status_text = "Compilando..."
            elif "screencapture" in clean_cmd:
                step_title = "Captura de pantalla"
                status_text = "Inspeccionando..."
            elif "git" in clean_cmd:
                step_title = f"Git {first}"
                status_text = "Verificando..."
            else:
                step_title = f"Run {first}"
                status_text = "Ejecutando..."
        else:
            step_title = tool_name.replace("_", " ").title()
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
    return {
        "start_time": now,
        "last_updated": now,
        "tools_count": 0,
        "progress": 0.12,
        "completed": False
    }

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
            
        session = get_task_session()
        session["tools_count"] = session.get("tools_count", 0) + 1
        cnt = session["tools_count"]
        
        # Progreso general acumulativo: suma avance con cada herramienta ejecutada
        # y asegura que jamás disminuya ni se reinicie a cero.
        old_prog = session.get("progress", 0.12)
        incremental_prog = old_prog + 0.04
        computed_prog = max(old_prog, max(phase_min_prog, incremental_prog))
        final_prog = min(0.95, computed_prog)
        session["progress"] = final_prog
        save_task_session(session)
        
        # Estimación de tiempo restante aproximado para completar la tarea del usuario
        if final_prog < 0.30:
            remaining_sec = 45
        elif final_prog < 0.50:
            remaining_sec = 30
        elif final_prog < 0.70:
            remaining_sec = 20
        elif final_prog < 0.85:
            remaining_sec = 12
        else:
            remaining_sec = 5
            
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
        session = {
            "start_time": now,
            "last_updated": now,
            "tools_count": 0,
            "progress": 0.12,
            "completed": False
        }
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
            payload = json.loads(raw_input)
            tool_call = payload.get("toolCall", {})
            tool_name = tool_call.get("name", "")
            session = get_task_session()
            prog = session.get("progress", 0.50)
            send_ipc("/progress", {
                "event": "step_done",
                "agent": "Antigravity",
                "step": f"Completado {tool_name}",
                "status": "Avanzando...",
                "progress": prog
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
