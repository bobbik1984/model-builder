"""Run a Ruby script in the designer's OPEN SketchUp model (Model Builder live link).

Usage (agents call this):
    python tools/mb_exec.py --task <task_dir> script.rb [--timeout 900]

The script must define:

    module MBScript
      def self.run(model, out_dir)
        ...
        "short result text"
      end
    end

The plugin runs it as one undoable operation (the designer may be asked to
approve) and returns JSON: {ok, result | error, backtrace, files, created, seconds}.
Exit code 0 = ok, 1 = script error/refused, 2 = timeout or bad call.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
import time
from pathlib import Path


def main() -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("script")
    ap.add_argument("--task", default=os.environ.get("MB_TASK_DIR"), help="task folder (from prompt.md)")
    ap.add_argument("--timeout", type=float, default=900, help="seconds to wait (approval can take a while)")
    a = ap.parse_args()
    if not a.task:
        print("error: --task <task_dir> is required (see prompt.md)", file=sys.stderr)
        return 2
    task = Path(a.task)
    inbox, outbox = task / "inbox", task / "outbox"
    if not inbox.is_dir():
        print(f"error: {inbox} not found; is this the right task folder?", file=sys.stderr)
        return 2
    src = Path(a.script)
    if not src.is_file():
        print(f"error: script not found: {src}", file=sys.stderr)
        return 2

    stem = re.sub(r"[^A-Za-z0-9_-]", "_", src.stem)[:40]
    # time-ordered and unique even when two calls start at the same moment
    name = f"{time.strftime('%H%M%S')}{int(time.time() * 1000) % 1000:03d}_{os.getpid() % 10000:04d}_{stem}"
    tmp = inbox / f"{name}.rb.tmp"
    shutil.copyfile(src, tmp)
    os.replace(tmp, inbox / f"{name}.rb")  # atomic: the plugin never sees a half-written file

    result_path = outbox / f"{name}.json"
    deadline = time.time() + a.timeout
    while time.time() < deadline:
        if result_path.is_file():
            try:
                res = json.loads(result_path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                time.sleep(0.2)
                continue
            print(json.dumps(res, indent=2, ensure_ascii=False))
            return 0 if res.get("ok") else 1
        time.sleep(0.3)
    print(json.dumps({"ok": False, "error": f"timeout after {a.timeout}s: SketchUp did not answer "
                      "(is the task still running and SketchUp open? the designer may not have approved yet)"}))
    return 2


if __name__ == "__main__":
    sys.exit(main())
