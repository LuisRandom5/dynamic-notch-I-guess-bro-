#!/usr/bin/env python3
import sys
import os

script_dir = os.path.dirname(os.path.abspath(__file__))
hook_script = os.path.join(script_dir, "antigravity_hook.py")
os.execv(sys.executable, [sys.executable, hook_script, "pre_tool"] + sys.argv[1:])
