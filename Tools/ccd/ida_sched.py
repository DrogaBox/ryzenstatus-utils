# IDAPython (idat -A -S): scheduler pieces for a CCD-aware placement hook on the x86 kernel.
import idaapi, idautils, idc, ida_hexrays, ida_auto

ida_auto.auto_wait()
out = open(idc.ARGV[1], "w")

def p(*a):
    out.write(" ".join(str(x) for x in a) + "\n")

names = ["_choose_starting_pset", "_thread_setrun", "_choose_processor_smt", "_thread_affinity_set",
         "_ml_affinity_to_pset", "_choose_processor", "_choose_next_pset", "_sched_dualq_dispatch"]
for n in names:
    ea = idc.get_name_ea_simple(n)
    p("==", n, hex(ea) if ea != idc.BADADDR else "MISSING")
    if ea == idc.BADADDR:
        continue
    callers = sorted({idc.get_func_name(x.frm) for x in idautils.XrefsTo(ea) if idc.get_func_name(x.frm)})
    p("   callers:", ", ".join(callers[:20]))

ida_hexrays.init_hexrays_plugin()
for n in ["_choose_starting_pset"]:
    ea = idc.get_name_ea_simple(n)
    f = idaapi.get_func(ea)
    p("== first bytes", n, idc.get_bytes(ea, 24).hex())
    p("== size", f.end_ea - f.start_ea)
    try:
        p(str(ida_hexrays.decompile(ea)))
    except Exception as e:
        p("decompile failed", e)
out.close()
idc.qexit(0)
