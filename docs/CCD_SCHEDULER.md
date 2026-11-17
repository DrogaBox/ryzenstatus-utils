# AMDCCDScheduler: one CCD per app, on macOS

`AMDCCDScheduler.kext` makes macOS schedule like a Ryzen with two CCDs wants it to. It keeps the threads of each
app on one CCD, so threads that pass data to each other share that CCD's L3 cache instead of crossing the
Infinity Fabric for every hand-off. When the CCD runs out of free cores, macOS spreads the app over both CCDs as
before, so work that needs every core loses nothing.

On a Ryzen 9 5900XT a Node worker pool ran **about 12% faster** (14% on another boot) with steadier times, and a
24-thread zstd job ran at the same speed as without the kext.

As far as we could find (November 2026), nothing else does this on macOS. Linux has CCD-aware scheduling
(the `amd_x3d_vcache` driver, for example) and on Windows there are tools that pin games to one CCD; macOS had
nothing, and no user-space setting reaches the threads macOS creates for apps.

| | |
|---|---|
| Version | 0.3.0 |
| Status | booted and measured on a Ryzen 9 5900XT, macOS 26.7.3 (25G342); Sonoma and Sequoia checked against Apple's installer kernels, not booted yet |
| CPUs | Ryzen with two or more CCDs: 5900X, 5950X, 5900XT, 7900X, 7950X, 9900X, 9950X and similar (only the 5900XT was tested) |
| macOS | 14.8.9 (23J631), 15.8.2 / 15.8.3 (24H232 / 24H241), 26.7.2 / 26.7.3 (25G332 / 25G342); on any other kernel it stays off by itself and says why |
| Needs | Lilu |
| Source | [`SMCAMDProcessor_Source/AMDCCDScheduler`](../SMCAMDProcessor_Source/AMDCCDScheduler) |

RyzenStatus shows its state and counters in **Settings › AMD Ryzen Power › CCD scheduler**.

---

## Results

Ryzen 9 5900XT (2 CCDs × 8 cores, 32 threads), macOS 26.7.3, kext 0.2.2. The three modes were measured in the
same session, switching `debug.ccd_mode` between runs and rotating the order so drift hits all of them;
medians of 7 runs (Node) and 5 runs (zstd), [`Tools/ccd/modes.zsh`](../Tools/ccd/modes.zsh).

| Load | Kext off (stock macOS) | Kext on (mode 1) | Change |
|---|---|---|---|
| Node worker pool, 4 workers passing messages ([`workers.js`](../Tools/ccd/workers.js)) | 850 ms (843–943) | **751 ms (735–815)** | **−11.6%** |
| Node worker pool, 8 workers | 855 ms (785–1118) | **754 ms (744–766)** | **−11.8%** |
| zstd -T24 -10, 1.15 GB | 7286 ms (7204–7505) | 7293 ms (7217–7420) | +0.1% (ranges overlap: no change) |

- With the kext the Node ranges do not overlap with stock macOS: the gain is not noise. Times are also much
  steadier (8 workers: 744–766 ms against 785–1118 ms).
- The stock times move from boot to boot (806–876 ms for 4 workers over three boots); with the kext on, the
  Node medians stayed at 739–754 ms on all three. On the boot with the slowest stock times the gain was 14%.
- zstd fills most of the CPU from one process. That is the case where an app must use both CCDs, and it does.
- 0.3.0, on a later boot with the same script: Node 4 workers 899 → 733 ms (−18.5%), 8 workers
  918 → 756 ms (−17.6%), zstd 7257 → 7285 ms (ranges overlap). The times with the kext match 0.2.2; stock macOS
  was slower on that boot. Read the gain as 12 to 18% depending on the boot.

### Version history

| Version | What it did | Node, 8 workers | zstd -T24 |
|---|---|---|---|
| 0.1.0 | moved only a thread's very first placement | no gain | no change |
| 0.2.0 | gives each process a home CCD, every placement starts there | −14.1% | **+1.8% (slower)** |
| 0.2.1 | same, only while the kernel's idle map shows a free CPU on the home CCD | −14.0% | **+2.8% (slower)** |
| 0.2.2 | same, only while the home CCD has a free **physical** core | −11.8% | +0.1% (no change) |
| 0.3.0 | 0.2.2 with one table per kernel: Sonoma, Sequoia and Tahoe | −17.6% | +0.4% (no change) |

Each line is a separate boot with its own stock baseline. 0.2.1 failed because the kernel's idle map counts an
idle SMT sibling as free: the home CCD almost always looked free, so an all-core job kept queueing on it. The
check that worked is the same one `choose_processor_smt()` makes first: a recommended, idle, primary core.

The kext keeps the 0.1.0 behaviour as mode 2, so the comparison can be repeated on any machine.

### What the cross-CCD trip costs

[`Tools/ccd/pingpong.c`](../Tools/ccd/pingpong.c): two threads pass one cache line back and forth.

| Placement | Round trip |
|---|---|
| Same CCD | 62–68 ns |
| Different CCDs | ~155 ns |
| No hint (what apps get from stock macOS) | 7 of 10 runs on different CCDs, ~155 ns |

Before the kext existed, the same idea was checked from user space with a `DYLD_INSERT_LIBRARIES` shim that
gives every pthread of a process the same affinity tag ([`Tools/ccd/ccdtag.c`](../Tools/ccd/ccdtag.c),
[`Tools/ccd/bench.py`](../Tools/ccd/bench.py)): Node 4 workers 1.383 → 1.032 s, 8 workers 1.270 → 1.037 s,
zstd and xz with 8 threads unchanged. The shim only reaches threads made with `pthread_create`; most app
threads on macOS are GCD workqueue threads that the kernel creates, and only a kernel hook reaches those.

---

## Why macOS splits an app across CCDs

macOS already knows the CCDs. On x86, xnu builds one processor set (pset) per last-level cache
([`osfmk/i386/cpu_topology.c`](https://github.com/apple-oss-distributions/xnu/blob/xnu-12377.121.6/osfmk/i386/cpu_topology.c)).
A 5900XT reports `hw.cacheconfig = 32 2 2 16` (16 logical CPUs per L3), so it has two psets, one per CCD.

It uses them to spread work, not to keep it together. In the 25G342 kernel (IDA/Hex-Rays):

1. `thread_setrun()` asks `choose_starting_pset()` where to start looking for a CPU, then
   `choose_processor_smt()` for the CPU itself.
2. `choose_starting_pset()` starts a thread that ran before in the pset of its last processor, and a new thread
   in the pset **after** the task's `pset_hint` (`choose_next_pset`; the xnu source comments it with *"NRG this
   seems like the wrong thing to do"*).
3. After every placement, `thread_setrun()` writes the pset it picked back into `task->pset_hint` (at `+0x1ef`),
   so the hint follows whichever thread of the task was placed last and flips between the CCDs.
4. `choose_processor_smt()` takes the first idle primary core in the starting pset and, if there is none, in the
   other psets, before it falls back to SMT siblings.

The threads of one app therefore keep landing on both CCDs. That is why 0.1.0, which only changed step 2 for
a thread's first placement, measured no gain: the next wakeup undid it.

---

## How the kext works

It wraps `choose_starting_pset()` with Lilu's `routeFunction`. The original always runs first; the kext only
decides whether to replace its answer.

**Mode 1 (default).**

1. The first time a process is seen, it gets a **home CCD**: the pset xnu itself chose for it at that moment,
   which alternates between processes, so the load stays balanced across CCDs.
2. On every later placement of any of its threads, if the original answered "the other CCD" and the home CCD
   has a recommended, idle, primary core, the search starts on the home CCD instead. The original's processor
   hint, which points inside the other CCD, is dropped.
3. If the home CCD has no free physical core, the original's answer stands and `choose_processor_smt()` spreads
   the thread as stock macOS does.

Left alone, always: realtime threads (priority 97 and up: audio, video), threads with an explicit affinity set,
threads of `kernel_task`, and any case where a pset is offline or outside the node.

**Mode 2** is 0.1.0: only a thread's first placement, towards the current `pset_hint`. **Mode 0** calls the
original only.

The home table is lock-free: 16384 slots of one 64-bit word (task pointer and pset id), 8-slot probing, filled
with compare-and-swap. A process that keeps running refreshes its slot's time stamp at most once a second; when
a probe window is full, the slot hit longest ago is reused, so short-lived processes (a build) never push a
live app out. The counters live in one cache line per CPU, so the hook does not bounce a shared line between
CCDs on every wakeup.

### Kernel facts it depends on (25G342)

From IDA/Hex-Rays of `/System/Library/Kernels/kernel`, UUID `28267FD5-3E1E-3686-8A1C-E73E2466FCFB`
(xnu-12377.161.15):

- `_choose_starting_pset` at `0xffffff80002a46c0` (546 bytes), only caller `_thread_setrun`, called up to four
  times per placement with the processor hint reset to null before each call.
- Thread: `+0x570` affinity_set, `+0x4b8` last_processor, `+0x434` sched_pri (int16); task through
  `_get_threadtask`, `task+0x68` pset_hint.
- Pset: `+0x0` pset_id, `+0x8` online_processor_count, `+0x30` recommended_bitmask, `+0x58`
  cpu_state_map[PROCESSOR_IDLE], `+0x70` primary_map. Node: `+0x18` pset_map.
  - `pset_update_processor_state()` keeps one CPU map per processor state at `pset+0x38 + 8 × state`
    (idle = 4); `processor_set_primary()` clears each SMT sibling's bit in `+0x70`;
    `choose_processor_smt()` reads `+0x30 & +0x58 & +0x70` to find an idle primary core (`+0x1a4`, `+0x201`).
- `pset_array[1]` is still null when Lilu plugins install, so the kext learns each pset's address from the
  kernel's own answers instead of reading that array. The first 0.2.0 build relied on it; at boot it found the
  mismatch, stayed off and logged why.

### The same facts on Sonoma and Sequoia (0.3.0)

The kernels inside Apple's installers, read in IDA the same way (`Tools/ccd/ida_port.py` on each boot kernel
collection). 15.8.2 and 15.8.3 ship one kernel (UUID `747934E9-FD01-36AB-8E97-06A578AB22F9`), and so do 26.7.2
and 26.7.3 (`28267FD5-…`). `choose_starting_pset` has the same logic in all three and one caller,
`thread_setrun`; only the offsets moved:

| | 14.8.9 (23J631) | 15.8.2 / 15.8.3 | 26.7.2 / 26.7.3 |
|---|---|---|---|
| thread affinity_set / last_processor | `+0x570` / `+0x4b8` | `+0x568` / `+0x4b0` | `+0x570` / `+0x4b8` |
| task pset_hint | `+0x70` | `+0x68` | `+0x68` |
| pset online_processor_count | `+0x4` | `+0x4` | `+0x8` |
| node pset_map | `+0x28` | `+0x20` | `+0x18` |
| pset recommended / idle / primary maps | `+0x58` / `+0x80` / `+0x98` | `+0x30` / `+0x58` / `+0x70` | `+0x30` / `+0x58` / `+0x70` |
| where the CPU picker reads those maps | `choose_processor+0x60e` | `choose_processor_smt+0x1ac` | `choose_processor_smt+0x201` |
| pset count | bits of `pset_node0`'s pset_map | bits of `pset_node0`'s pset_map | `sched_num_psets` |

`sched_pri` (`+0x434`, int16), `pset_id` (`+0x0`) and the realtime threshold (97) are the same everywhere.
Sonoma has no `choose_processor_smt`; its `choose_processor` makes the same test (recommended & idle &
primary), and `processor_set_primary` clears the SMT sibling's bit at `+0x98` there. Not verified at runtime on
Sonoma or Sequoia: that `pset_node0`'s map already holds both psets when Lilu plugins install. If it does not,
the kext reports one processor set and stays off.

### Safety

- The hook is installed only if one kernel table matches completely: the first 76 to 87 bytes of
  `_choose_starting_pset` (relative displacements masked), its call to `_get_threadtask`, five more spots that
  encode the offsets above, and the CPU picker's reads of the three pset maps. On another kernel it stays off and
  `sysctl debug.ccd_log` says, for each table, which bytes differed.
- With a single pset (single-CCD CPU) it installs nothing.
- The instructions Lilu moves into its trampoline are not relative in any of the three kernels (Tahoe:
  `push rbp; mov rbp,rsp; push r15; push r14; push rbx; push rax; mov rax,[rsi+0x570]`; Sequoia and Sonoma: the
  same frame with `push r13; push r12` and register moves), so they relocate safely.
- `-ccdoff` keeps it from loading; `sysctl -w debug.ccd_mode=0` turns it off live.
- The hook logic is tested in user space against fake kernel objects, once with each kernel table's offsets
  (`AMDCCDScheduler/tests/run.sh`, 141 checks, built once with AddressSanitizer + UndefinedBehaviorSanitizer and
  once with ThreadSanitizer). The tables themselves are checked too: each matches bytes built from itself and
  rejects the other tables', a changed byte and a wrong call target. Per table: first placement, drift of `pset_hint`, busy home CCD (only SMT siblings idle, idle
  but not recommended), realtime / affinity / kernel_task untouched, offline home, modes 0 and 2, per-CPU
  counters, 40000 and 50000 short-lived processes next to 1000 live ones (no live process lost its home), and
  16 threads placing the same 64 new processes at once (one home each).

`check_layout.py` runs the same byte test against a kernel without booting it, for every table. It takes a
kernel file or the `BootKernelExtensions.kc` from a macOS installer:

```bash
python3 -I SMCAMDProcessor_Source/AMDCCDScheduler/check_layout.py            # running kernel
python3 -I SMCAMDProcessor_Source/AMDCCDScheduler/check_layout.py /path/to/BootKernelExtensions.kc
```

On the installer kernels of 14.8.9, 15.8.2, 15.8.3, 26.7.2 and 26.7.3 each matches exactly one table.

---

## Interface

| | |
|---|---|
| Boot-args | `-ccdoff` (do not load), `-ccddbg` (Lilu debug log), `ccdmode=0\|1\|2` (start mode; default 1) |
| `debug.ccd_mode` | read/write (root): 1 home CCD per app, 0 off, 2 the 0.1.0 behaviour. Resets to the boot value on restart. |
| `debug.ccd_state` | 0 not run, 1 installed, 2 symbol missing, 3 layout mismatch, 4 route failed, 5 one pset only |
| `debug.ccd_stat` | `state S mode M psets P new N kept K same A nohint H full F` |
| `debug.ccd_log` | install log, one line per event |

Counters, summed over all CPUs since boot (field names kept from 0.1.0 so older readers still parse):

- `new`: placements the kext looked at (user threads, not realtime, no affinity set).
- `kept`: the kernel would have started the thread on the other CCD; the kext started it on its app's CCD.
- `same`: the kernel's choice already was the app's CCD.
- `nohint`: processes that were given a home CCD.
- `full`: the home CCD had no free physical core, so the kernel's choice stood (0.2.1 and later).

48 seconds after boot on the 5900XT: about 2.9 million placements, from about 960 processes.

## In the app

`Sources/RyzenStatus/Services/AMD/CCDSchedulerService.swift` reads the sysctls (`CCDSchedulerStatus.parse` is
pure and unit-tested in `Tests/HardwareLayerTests.swift`) and counts L3 domains from `hw.cacheconfig`.
`UI/Settings/AmdCCDSchedulerSection.swift` is the section in AMD Ryzen Power:

- kext loaded and hooked: state (active, off, or comparison mode 2), CCD count, the live switch (writes
  `debug.ccd_mode` through the system password prompt, `AdminShell`), the five counters, and the kext log;
- kext loaded but not hooked: the reason in orange, and the log;
- kext not loaded on a multi-CCD CPU: a hint to add it;
- single-CCD CPU without the kext: hidden.

Strings: `Core/CCDSchedulerStrings.swift`, all 15 languages.

---

## Build, install, measure

```bash
bash SMCAMDProcessor_Source/AMDCCDScheduler/build.sh      # -> SMCAMDProcessor_Source/build/AMDCCDScheduler/
zsh SMCAMDProcessor_Source/AMDCCDScheduler/tests/run.sh   # hook tests (ASan/UBSan + TSan)
```

It uses `MacKernelSDK` and the Lilu headers in `SMCAMDProcessor_Source/build/kproj` (set `DEPS=` to use others).

Install: copy `AMDCCDScheduler.kext` to `EFI/OC/Kexts` and add it to `Kernel › Add` **after Lilu**. Keep a
bootable fallback EFI (USB) for the first boot.

After booting:

```bash
sysctl debug.ccd_state debug.ccd_stat debug.ccd_log
```

`state 1` and `installed: macOS … layout, 2 processor sets, mode 1` mean it is active. To measure the three modes on your
machine (asks for your password; about 3 minutes with a 1 GB file):

```bash
sudo zsh Tools/ccd/modes.zsh ~/ccd-modes.txt /path/to/a-1GB-file
```

## Porting to another macOS build

1. `python3 -I check_layout.py /System/Library/Kernels/kernel` (or the installer's `BootKernelExtensions.kc`).
   A match means nothing to do.
2. Otherwise open the kernel in IDA (`Tools/ccd/ida_port.py` dumps `choose_starting_pset` with its bytes and
   decompiles the CPU picker, `processor_set_primary` and `thread_setrun`), check that every field in the table
   above is still read the same way, and add a table to `kLayouts` in `AMDCCDScheduler.cpp` (`kHead…`, `kMore…`,
   `kPick…` and the offsets). `check_layout.py` and the tests pick it up by themselves. Never relax a signature
   to make it fit.

---

## Test coverage and limits

Tested (Ryzen 9 5900XT, macOS 26.7.3, 25G342):

- The cause, from source and Hex-Rays of the running kernel, including the `pset_hint` rewrite and the maps
  `choose_processor_smt` uses.
- Boots with 0.2.0, 0.2.1, 0.2.2 and 0.3.0: the hook installs (`state 1`; 0.3.0 logs the 26.7.2-26.7.3
  table), no panic; the counters move.
- The results above, measured with the kext itself (not the shim).
- The signatures match the running kernel and the installer kernels of 14.8.9, 15.8.2, 15.8.3, 26.7.2 and
  26.7.3 (`check_layout.py`); the hook tests pass under ASan/UBSan and TSan for every table.

Not covered yet:

- Apps other than the Node pool and zstd: browsers, Electron apps, games and audio were not measured.
- Any CPU other than the 5900XT.
- A boot on Sonoma or Sequoia: those tables come from the installer kernels and the tests only.
- Long-term use.
- The switch in the app end to end with this version.
