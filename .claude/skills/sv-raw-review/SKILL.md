---
name: sv-raw-review
description: Rules for reading SystemVerilog source directly when the odve-index MCP cannot answer (a tool returned error, the file is in no elaborated unit, the index is unavailable) or when a review genuinely needs the code - how to read as little as possible, by outline and ranges, following filelists not directories, never the UVM library. Use it whenever you are about to Read or cat a .sv/.svh file, grep across odve/, or review generated agent code line by line.
---

# Reading raw SystemVerilog, when you must

Reading source is the expensive path: a UVM class file is hundreds of lines
and the agent needs five of them. These rules keep raw reads small and make
sure the index gets its chance first.

1. **Ask the index first, even for a review.** `sym_outline(path)` tells you
   where the methods are; `code_at(path, line, context)` or `code_at(path,
   line, end_line=...)` reads exactly the range. Open the whole file only when
   the outline is empty (`error: file not indexed` → `index_update` first).
2. **Follow filelists, not directories.** What the simulator compiles is
   `vrf/list/fl_*.f` and `list/*.f` (`fl_resolve`); a directory listing shows
   dead files, vendored duplicates (`uvm/.../docs/html/src` is a second copy
   of UVM) and files no list compiles. Do not `grep -r` over `odve/`; grep
   over `fl_resolve(...).files` if you must grep at all.
3. **Never read `uvm/` to learn an API.** `sym_members("uvm_component")`,
   `class_info("uvm_sequence")`, `sym_def("uvm_config_db")` answer from the
   elaborated library; the sources there are 250 k lines.
4. **Review generated code in this order:** `fl_of_file` (is it compiled?),
   `diag(file=...)` (does slang accept it?), `sym_outline` (does it declare
   what the task asked?), `sym_refs` of the new symbols (are they wired?),
   then `code_at` on the methods that matter. Then the simulators
   (`vrf-workflow`) - slang diagnostics are advisory.
5. **Say what you did not read.** When the answer rests on an outline and a
   few ranges, say so; when the index was stale or a unit had errors
   (`index_status`), say that too.
6. **Keep the index honest.** After every edit of `.sv/.svh/.f` the hook
   updates it; without the hook call `index_update`. A new file that
   `fl_of_file` reports `listed: false` must be added to a filelist - that
   is the usual reason a change "does nothing" in simulation.
