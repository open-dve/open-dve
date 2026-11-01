"""A stdlib-only MCP stdio server (the same one pcie-spec/kb uses).

Why: the MCP path is the fast lane for an agent - structured results, no
shell, no output truncation - and it must work on a fresh clone with a bare
Python 3. The protocol the tools need is small: newline-delimited JSON-RPC
2.0 on stdin/stdout with `initialize`, `notifications/initialized`, `ping`,
`tools/list` and `tools/call`. Everything else is answered with "method not
found", which clients treat as "not supported".

Mirrors the subset of `mcp.server.MCPServer` the tools use: the `tool()`
decorator and `run()`. Input schemas come from the tool's signature
(str / int / bool / float / list[str], Optional = not required) and the
description from its docstring."""
from __future__ import annotations
import inspect
import json
import sys
import typing

PROTOCOL_VERSION = "2025-06-18"

_JSON_TYPES = {str: "string", int: "integer", float: "number", bool: "boolean"}


def _schema_for(param: inspect.Parameter) -> tuple[dict, bool]:
    """JSON-schema fragment for one parameter, and whether it is required."""
    ann = param.annotation
    required = param.default is inspect.Parameter.empty
    origin = typing.get_origin(ann)
    if origin is typing.Union or (origin is not None and str(origin) == "<class 'types.UnionType'>"):
        args = [a for a in typing.get_args(ann) if a is not type(None)]
        ann = args[0] if args else str
        origin = typing.get_origin(ann)
    if origin in (list, typing.List):
        item = typing.get_args(ann)[0] if typing.get_args(ann) else str
        return {"type": "array", "items": {"type": _JSON_TYPES.get(item, "string")}}, required
    return {"type": _JSON_TYPES.get(ann, "string")}, required


class MCPServer:
    def __init__(self, name: str, instructions: str = ""):
        self.name, self.instructions = name, instructions
        self._tools: dict[str, dict] = {}

    def tool(self):
        def deco(fn):
            props, req = {}, []
            for p in inspect.signature(fn).parameters.values():
                schema, required = _schema_for(p)
                props[p.name] = schema
                if required:
                    req.append(p.name)
            self._tools[fn.__name__] = {
                "fn": fn,
                "spec": {"name": fn.__name__,
                         "description": inspect.getdoc(fn) or "",
                         "inputSchema": {"type": "object", "properties": props, "required": req}},
            }
            return fn
        return deco

    # ---- protocol
    def _handle(self, msg: dict):
        method, params, mid = msg.get("method"), msg.get("params") or {}, msg.get("id")
        if method == "initialize":
            return {"protocolVersion": params.get("protocolVersion") or PROTOCOL_VERSION,
                    "capabilities": {"tools": {"listChanged": False}},
                    "serverInfo": {"name": self.name, "version": "stdlib"},
                    "instructions": self.instructions}
        if method == "ping":
            return {}
        if method == "tools/list":
            return {"tools": [t["spec"] for t in self._tools.values()]}
        if method == "tools/call":
            tool = self._tools.get(params.get("name", ""))
            if tool is None:
                return {"content": [{"type": "text", "text": f"unknown tool {params.get('name')!r}"}],
                        "isError": True}
            try:
                text = tool["fn"](**(params.get("arguments") or {}))
                return {"content": [{"type": "text", "text": str(text)}], "isError": False}
            except Exception as e:  # the tool's own error, reported as a tool error
                return {"content": [{"type": "text", "text": f"{type(e).__name__}: {e}"}], "isError": True}
        if mid is None:          # a notification we do not care about
            return None
        raise LookupError(method)

    def handle_line(self, line: str):
        """One request line -> one reply line (or None). Used by run() and by the tests."""
        line = line.strip()
        if not line:
            return None
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            return None
        mid = msg.get("id")
        try:
            result = self._handle(msg)
        except LookupError as e:
            if mid is None:
                return None
            reply = {"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": f"Method not found: {e}"}}
        else:
            if mid is None:
                return None
            reply = {"jsonrpc": "2.0", "id": mid, "result": result}
        return json.dumps(reply, ensure_ascii=False)

    def run(self):
        out = sys.stdout
        for line in sys.stdin:
            reply = self.handle_line(line)
            if reply is not None:
                out.write(reply + "\n")
                out.flush()
