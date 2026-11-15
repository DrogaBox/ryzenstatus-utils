# IDAPython: full disassembly with bytes of _choose_starting_pset, plus get_threadtask.
import idaapi, idautils, idc, ida_auto, ida_hexrays
ida_auto.auto_wait()
out = open(idc.ARGV[1], "w")
for n in ["_choose_starting_pset", "_get_threadtask"]:
    ea = idc.get_name_ea_simple(n)
    f = idaapi.get_func(ea)
    out.write("== %s %x size %d\n" % (n, ea, f.end_ea - f.start_ea))
    for h in idautils.Heads(f.start_ea, f.end_ea):
        out.write("%x  %-24s %s\n" % (h - ea, idc.get_bytes(h, idc.get_item_size(h)).hex(), idc.generate_disasm_line(h, 0)))
ida_hexrays.init_hexrays_plugin()
out.write(str(ida_hexrays.decompile(idc.get_name_ea_simple("_get_threadtask"))) + "\n")
out.close()
idc.qexit(0)
