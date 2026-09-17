#!/usr/bin/env python3
"""Harness stub server for round15 runner unit test (no external network).
Serves canned responses so the full runner (curl cases + python urllib assertions)
executes end-to-end against a local stub."""
import json, re
from http.server import BaseHTTPRequestHandler, HTTPServer

CAND = {
    "total_matched": 0, "status": "ok", "returned": 0, "pool_exhausted": False,
    "applied_filters": {}, "summary": [], "scoring_basis": {},
    "broadening_attempts": [], "protected_dims": [], "relaxed_dims": [],
    "persona_ids": [], "llm_calls": 1, "subject": "", "warnings": [],
    "subject_basis": "", "protected_dims_sources": {}, "declared_protected_cap": 0,
    "broadening_stop_reason": "",
}
STATUS = "Persona DB Status\n  Version v5.15\n  Main personas 1069\n"
OPENAPI = json.load(open(r"C:/Users/is830/AppData/Local/Temp/openapi-v515.json", encoding="utf-8"))

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_GET(self):
        p = self.path
        if p.startswith("/personadb/status"):
            self.send_response(200); self.send_header("Content-Type","text/plain")
            b = STATUS.encode(); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
        elif p.startswith("/openapi.json"):
            self._send(200, OPENAPI)
        elif p.startswith("/personadb/candidates"):
            if "opMode=%E4%BA%82%E5%AF%AB" in p:   # #47 invalid opMode
                self._send(400, {"error": {"code": "INVALID_OPMODE", "message": "x"}})
            else:
                self._send(200, CAND)
        else:
            self._send(404, {"error": {"code": "NOT_FOUND"}})

if __name__ == "__main__":
    import sys
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18099
    print(f"STUB_LISTENING {port}", flush=True)
    HTTPServer(("127.0.0.1", port), H).serve_forever()
