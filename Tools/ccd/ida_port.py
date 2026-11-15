# IDAPython (idat -A -S"ida_port.py out.txt"): scheduler functions AMDCCDScheduler depends on, for porting.
import idaapi, idautils, idc, ida_hexrays, ida_auto, ida_lines

ida_auto.auto_wait()
out = open(idc.ARGV[1], "w")


def p(*a):
    out.write(" ".join(str(x) for x in a) + "\n")


ida_hexrays.init_hexrays_plugin()
names = ["_choose_starting_pset", "_thread_setrun", "_choose_processor_smt", "_choose_processor",
         "_pset_update_processor_state", "_processor_set_primary", "_get_threadtask", "_cpu_number",
         "_sched_dualq_dispatch", "_thread_affinity_set"]
for n in names:
    ea = idc.get_name_ea_simple(n)
    p("=" * 20, n, hex(ea) if ea != idc.BADADDR else "MISSING")
    if ea == idc.BADADDR:
        continue
    f = idaapi.get_func(ea)
    callers = sorted({idc.get_func_name(x.frm) for x in idautils.XrefsTo(ea) if idc.get_func_name(x.frm)})
    p("callers:", ", ".join(callers[:20]))
    if f:
        p("size", f.end_ea - f.start_ea)
    if n in ("_get_threadtask", "_cpu_number", "_thread_affinity_set", "_sched_dualq_dispatch"):
        continue
    if n == "_choose_starting_pset" and f:
        p("-- disasm")
        for h in idautils.Heads(f.start_ea, f.end_ea):
            p(f"+0x{h - f.start_ea:03x}  {idc.get_bytes(h, idc.get_item_size(h)).hex():<24} {idc.GetDisasm(h)}")
    try:
        p("-- decompile")
        p(str(ida_hexrays.decompile(ea)))
    except Exception as e:
        p("decompile failed", e)
out.close()
idc.qexit(0)
