# KEXT_WAVE_PLAN.md — Brief técnico completo para Gemini 3.8 (High)

> **Handoff document.** Repo: **RyzenStatus**, branch `main`, base `b83204ae`.
> Escrito 2026-09-05. Toda cita `file:line` fue verificada contra el árbol el
> 2026-09-05. **Re-verificá cada cita antes de tocar nada.**
> Ejecutar en orden: Fase A → B → C → D. Un commit por hallazgo/feature con el ID
> del audit en el mensaje.

---

## 0. Misión

1. **Re-auditar TODO lo pendiente de los kexts** (`SMCAMDProcessor_Source/`):
   conciliar las 5 olas de auditoría previas contra el código actual y determinar,
   con evidencia file:line, qué sigue abierto y qué quedó obsoleto (MOOT).
2. **Minar los kexts en busca de TODO lo que RyzenStatus pueda exponer**: nueva
   telemetría, nuevos controles, nueva UI. Proponer + implementar integraciones.
3. Entregar como **kernel wave v1.20.0** (kexts → 3.34.2), DESPUÉS de cerrar la
   release app-only 1.19.0 (§6-D3; el bump 1.19.0/59 ya está en disco).

---

## 1. Restricciones duras (violar cualquiera = handoff fallido)

1. **ABI congelada.** `AMDRyzenCPUPowerManagement/Info.plist:48-49` fija
   `OSBundleCompatibleVersion = 3.16.0`. Agregaciones **read-only** (selectores
   nuevos, llaves SMC nuevas) NO requieren bump. Solo un cambio de
   significado/tamaño de un selector EXISTENTE lo requeriría → en ese caso STOP y
   consultar al owner.
2. **Selectores congelados.** Los números existentes y sus contratos I/O no se
   tocan (política en `Sources/RyzenStatus/Core/AMDKextSelectors.swift:1-10`).
   Features nuevas = números nuevos en rangos libres: `32…39` (CPU/SMU),
   `104…109` (GPU), `112…119` (SMU/CO). Implementar en el switch de
   `AMDRyzenCPUPMUserClient.cpp` **y** en `AMDKextSelector` en el MISMO commit.
3. **Contrato de buffers F-12/F-16 es ley** (patrón en
   `AMDRyzenCPUPMUserClient.cpp:203-206, 373-376`): rechazar buffer chico con
   `kIOReturnBadArgument` ANTES de copiar; reportar `min(maxLen, requiredSize)`;
   zero-fill de todo paquete de salida; nunca crecer `structureOutputSize`.
4. **Privilegio:** todo selector de ESCRITURA pasa por `hasPrivilege(selector)`
   (`:82-104`; ejemplos 97/99 en `:1289-1317, 1352-1377`). Lecturas nuevas que
   puedan stallar el workloop (MMIO/SMU polling) también se gatean (lección F-05).
5. **Jerarquía de locks:** no invertir `smuCmdLock`
   (`AMDRyzenCPUPowerManagement.hpp:410`, `cpp:1223-1259`), `superIOLock`,
   `rendezvousLock`, `gpuLock` (KRN-05/11). Lock nuevo → documentarlo en un bloque
   de comentario de lock-ordering al inicio del `.hpp`.
6. **Sin escrituras SMU a Zen 5; Curve Optimizer Zen 4 sigue BLOQUEADO** hasta
   verificar en hardware real (guardas en `AMDRyzenCPUPowerManagement.cpp:660-674`).
   Fail-closed siempre.
7. **Build del kext:** `xcodebuild` está bloqueado (xcode-select →
   CommandLineTools) pero existe Xcode.app. Compilar con
   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project
   SMCAMDProcessor_Source/SMCAMDProcessor.xcodeproj …`. NUNCA `sudo xcode-select`.
   Primer acto: `-list` de schemes y registrar el comando exacto aquí.
8. **Trampas app vigentes** (de `HANDOFF_F27-F30.md`):
   - `UI/MenuPanel/MenuPanelView.swift:800`: "errors" de strict-concurrency = bug
     de rendering del compilador Swift. NO "arreglarlos".
   - NUNCA cambiar `AmdControlSection.loadFanPicker()` a `includeNames: false`.
   - `./build.sh` es **zsh**; jamás `sh build.sh`.
   - `./Tools/concurrency-gate.sh` debe seguir exit 0.
9. **No re-introducir código eliminado a propósito:** MWAIT, `pmRyzen_exit_idle()`,
   `cppcRead/WriteAllowed` (`SMCAMDProcessor_Source/README.md:254-289`).
10. **Versiones:** ola kernel = app **1.20.0 (60)**, kexts **3.34.2**
    (`Config/Version.xcconfig:10-11`). 1.19.0 primero (§6-D3).

---

## 2. Libro mayor de auditorías previas

| Ola | Commit | Dónde está el registro | Items kext |
|---|---|---|---|
| Audit completo v1.15.1 (190 hallazgos, 6 tracks) | `14f4df70` | `AUDIT.md` — **borrado del repo** por `4fd11d29`. Recuperar: `git show 14f4df70:AUDIT.md > AUDIT_ARCHIVE.md` | B-01, F-01…F-30 |
| Ola KRN "Phase 1" | `85865a17` | SOLO el DARE record en el cuerpo del commit — **el reporte KRN jamás se commiteó** | KRN-01…30 documentados 26; **17/20/21/22 sin disposición** |
| Fix ABI kernel | `f05e7fba` | cuerpo del commit | efiRT->put(), ABI 3.16.0 |
| Ola verificada v1.18.0 | `f4106f92` | cuerpo + `CHANGELOG.md` §1.18.0 (kext renumerado — **otra numeración**, no confundir) | 10 fixes; kexts → 3.34.1 |
| Segunda opinión app F-27…F-30 | `b83204ae` | `HANDOFF_F27-F30.md` (untracked) | solo app; kext byte-idéntico |

Superficie actual: kext implementa **0–31, 90–103, 110–111** (cases en
`AMDRyzenCPUPMUserClient.cpp:134-1534`). Binarios staging = 3.34.1.

---

## 3. Fase A — Conciliación de auditorías

Entregable: **`KEXT_FINDINGS.md`** commiteado — una fila por hallazgo:
`ID · file:line · estado (OPEN / MOOT / FIXED-BY-<commit> / REJECTED+motivo) · evidencia`.

### A-1. Recuperar fuentes
```bash
git show 14f4df70:AUDIT.md > AUDIT_ARCHIVE.md   # untracked
```

### A-2. Lista de sospechosos

**YA VERIFICADO (2026-09-05, no re-dudar — ir directo a Fase B):**

- **F-05 — OPEN (crítico).** Flujo exacto:
  `SMCAMDProcessor/Keyimplementations.cpp:61-74` `RGPUPowerValue::readAccess()`
  → `AMDRyzenCPUPowerManagement.cpp:1709-1712` `getGPUPower()`
  → `AMDGPU.cpp:586+` `getPower()` → `smu9GetPower()` (`:388-430`):
  **busy-wait hasta 100 ms** (`AMDGPU_SMU_TIMEOUT_US=100000`, `:46-47`) bajo
  `gpuLock`, invocado desde el thread de CUALQUIER proceso que lea la llave SMC.
- **F-07 — OPEN.** `AMDRyzenCPUPMUserClient.cpp:23` guarda
  `fOwningTask = owningTask;` **sin retain**; `hasPrivilege():91` lo dereferencia
  → ventana UAF. KRN-24 solo agregó `clientClose()`.
- **N-01 — NUEVO.** Cases 28/29 (`AMDRyzenCPUPMUserClient.cpp:896-925, 925-952`)
  ignoran el `IOReturn` de `getGPUTemperature/getGPUPower` → elementos sin
  inicializar copiados a userspace en fallo = infoleak residual pese al F-16.

**VERIFICAR EN FASE A:**

| ID | Reclamo (AUDIT.md 1.15.1) | Dónde verificar |
|---|---|---|
| F-09 | P-state takeover corre en modo telemetry-only | `AMDRyzenCPUPowerManagement.cpp` — `allowDispatch`, gate KRN-13 |
| F-13k | `ccdTemperatures` mix de lock-domain | provider timer `:377-382` + `getCCDTemp` |
| F-14k | Resolver kernel: base hardcodeada + log "unsafe wrmsr" engañoso | `symresolver/kernel_resolver.h/.c` |
| F-15k | SMC mailbox sin arbitraje con driver AMD nativo | sección SMU `cpp:1062-1314` |
| F-22k | Slider manual de fan deja de seguir el PWM real | cases 94/95/96 + `overrideFanControl` (`:1289-1317`) |
| B-13 | App pide 10 clocks P-state, kext devuelve 8 | selector 1 ambos lados |
| B-25 | Watchdog detecta reload pero nunca reconecta | app `ProcessorModel.swift` + `kextloadAlerts` |
| B-30 | Curvas re-subidas + spam privilegio por refresh | `FanCurveController.syncCurvesToKext()` |

### A-3. Disposición de KRN-17/20/21/22
```bash
git show 85865a17 -- SMCAMDProcessor_Source/ > /tmp/krn-full.diff
```
Inferir temas por vecindad numérica del DARE record; cruzar diff completo vs los
26 claims; revisar `CHANGELOG.md` §1.16.0. Veredicto por ID.

### A-4. Fresh-eyes sobre 4 archivos
`AMDRyzenCPUPowerManagement.cpp/.hpp`, `AMDRyzenCPUPMUserClient.cpp`,
`AMDGPU.cpp`, `Keyimplementations.cpp`. Focus: aritmética de buffers,
truncamiento de enteros, cobertura de locks, divergencias copy-paste.
Hallazgo nuevo = ID `N-xx`.

**Gate: fin de Fase A = `KEXT_FINDINGS.md` commiteado + sign-off del owner.**

---

## 4. Fase B — Fixes verificados (código concreto)

### FIX-1 (F-05): GPU desde el caché del provider, jamás MMIO en demanda
El provider YA cachea en su timer (`AMDRyzenCPUPowerManagement.cpp:390-392`).
**Cambio 1 — `Keyimplementations.cpp`:**
```cpp
SMC_RESULT RGPUPowerValue::readAccess() {
    if (!provider) return SmcError;
    if (package >= provider->gpuCount) return SmcError;
    __sync_synchronize();
    uint16_t *ptr = reinterpret_cast<uint16_t *>(data);
    *ptr = VirtualSMCAPI::encodeSp(type, (double)provider->gpuPowers[package]);
    return SmcSuccess;
}
// RGPUTempValue::readAccess() idéntico con gpuTemperatures[package]
```
**Cambio 2 — cases 28/29 UserClient:**
```cpp
for (uint32_t i = 0; i < copyCount; i++) {
    dataOut[i] = (i < provider->gpuCount) ? provider->gpuPowers[i] : 0.0f;
}
// case 28 análogo con gpuTemperatures[i]
```
**Aceptación:** ninguna llamada `getGPU*` fuera del timer del provider.

### FIX-2 (F-07): retener el owning task
```cpp
// .hpp:  void free() override;
// .cpp initWithTask (~:23):
    fOwningTask = owningTask;
    task_reference(owningTask);
// .cpp:
void AMDRyzenCPUPMUserClient::free() {
    if (fOwningTask) { task_deallocate(fOwningTask); fOwningTask = nullptr; }
    IOUserClient::free();
}
```

### FIX-3 (N-01): zero-init antes de leer por-GPU (mismo si FIX-1 lo vuelve inofensivo)

### FIX-4…N — resto de OPEN de Fase A, uno por commit, menor riesgo primero.

---

## 5. Fase C — Features (el pedido grande)

Protocolo: (1) evidencia file:line, (2) selector/SMC key + modelo Swift,
(3) superficie UI, (4) `[TELEMETRY]` vs `[CONTROL]`. Telemetría primero.

- **C-1. C6 por núcleo `[TELEMETRY]`** — selector **32**; accounting ya existe
  (`pmAMDRyzen.c:258-327`, `eff_idleacc/eff_timeaccd`). Código esqueleto en el
  plan original; app: `C6Sampling` + overlay per-core (B-35.5).
- **C-2. IPC + freq por núcleo `[TELEMETRY]`** — selector **33**, patrón del case 5;
  gráfico de frecuencia (B-35.1) + badge IPC; formateo puro a `--test`.
- **C-3. Tabla P-states `[TELEMETRY]`** — cases 0/1 + `pstateCur`; arreglar B-13.
- **C-4. Curve Optimizer Zen 4 `[CONTROL]`** — research offsets vs Linux
  `amd-pmf`/`amdgpu nv.c`; capability bitmap; fail-closed; owner prueba en hardware.
- **C-5. Ranking silicio `[TELEMETRY]`** — selector 21 + `AMDCoreRanking`; strip
  "best cores" (B-35.4).
- **C-6. Control manual por fan `[CONTROL]`** — selectors 94/95/96/97; prereqs
  F-22k + B-30; piso térmico ≥85 °C → PWM ≥ 200.
- **C-7. GPU vía llaves SMC `[TELEMETRY]`** — `TGxD/TGxP/TGxd/TGxp`, `PGxR/PGxC`
  (`SMCAMDProcessor.cpp:47-59`); `SystemMonitor.swift:976` prefiere kext-SMC.
- **C-8. Identidad baseboard `[TELEMETRY]`** — selector 16 + 26; fila About.
- **C-9. Auto-reconexión kext `[RELIABILITY]`** (= fix B-25) — watchdog → cerrar
  connect + reabrir en `Task.detached` con generation guard; toast.
- **C-10. Mina cross-driver (solo documentar)** — `amd-pmf`, `k10temp`, `amdgpu`,
  `zenstates.py`; shortlist con citas registro-por-registro.

---

## 6. Release engineering (Fase D)

- **D-1.** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild
  -project SMCAMDProcessor_Source/SMCAMDProcessor.xcodeproj -list` → registrar
  comando exacto; staging a `build/dmg-kexts/` (make-dmg.sh:51-52); plists 3.34.2.
- **D-2.** `Config/Version.xcconfig` → 3.34.2; documentar decisión ABI (esperado:
  sin bump).
- **D-3.** Cerrar 1.19.0 PRIMERO: `--test` → build → selftest → make-dmg → commit.
  Luego kernel wave: app 1.20.0 (60) + CHANGELOG `## [1.20.0]`.
- **D-4.** DMG 1.20.0: montar y verificar kexts 3.34.2, app version, codesign.

## 7. Checklist de verificación

```
./build.sh --test                      # 3,793 checks + tests nuevos
./build.sh                             # app compila
./Tools/concurrency-gate.sh            # 0 diagnósticos AMD-layer
./build/RyzenStatus --selftest         # SELFTEST OK
kexts: Info.plist 3.34.2, decisión ABI documentada
KEXT_FINDINGS.md commiteado
DMG monta; Kexts/ con 3.34.2
```

## 8. Fuera de alcance

MWAIT/paths eliminados; escrituras SMU no verificadas Zen 4/5; strict-concurrency
global; notarización; renumerar selectores existentes.

## 9. Reporte final esperado

1. `KEXT_FINDINGS.md` commiteado. 2. Commits con IDs. 3. Comandos de build kext
documentados. 4. DMG 1.20.0 verificado + checklist verde. 5. Riesgos/decisiones
para el owner (ABI, Zen 4 enable).
