# Auditoría S10 — Guía de Implementación y Ejecución Quirúrgica

**Repositorio auditado:** `DrogaBox/ryzenstatus-utils` @ `main` (`c0a9e683`, v1.31.0 build 74)
**Alcance:** kext `AMDRyzenCPUPowerManagement` + UserClient IOKit, telemetría SuperIO, algoritmo de fan curves, concurrencia Swift, capa AppKit/SwiftUI y módulo Now Playing.
**Superficie real revisada:** 394 archivos Swift (`Sources/RyzenStatus`), `SMCAMDProcessor_Source/AMDRyzenCPUPowerManagement/*.{cpp,hpp}`, 3 drivers SuperIO (NCT668X / NCT67XX / IT86XXE).

**Destinatario de ejecución:** Gemini 3.8 Flash. Cada ticket es autónomo, con bloque exacto a buscar y bloque exacto a sustituir. **Los bloques de esta guía no se solapan entre sí**; se pueden aplicar en el orden del índice sin conflictos de parche.

---

## 0. Resumen ejecutivo — el hallazgo que domina la auditoría

La arquitectura general es sólida y muestra oleadas de auditoría previas ya aplicadas (marcadores `AUDIT F-xx`, `B-xx`, `KRN-xx`, `S2-T4b`). El lazo de control de ventiladores vive **en el kernel** (`evaluateFanCurves()`, timer de 500 ms), lo cual es la decisión correcta: la app solo sube una LUT de 256 puntos y lee telemetría. El empaquetado de estructuras que cruzan IOKit (`CPUSensorPacket` 304 B, `AMDFanCurveInput` 272 B) es **memory-safe y ejemplar** — serialización explícita byte a byte, nunca `MemoryLayout` sobre tipos con arrays Swift, validación de tamaño en ambos lados.

Sin embargo existe un patrón sistémico de **fallo peligroso por defecto** (*fail-dangerous*) en la cadena térmica:

> **Todas las rutas de error de temperatura colapsan a `0.0f`, y `0 °C` selecciona simultáneamente el punto más bajo de la curva y desarma el guard de emergencia de 85 °C.**

`getPackageTemp()` devuelve `0.0f` tanto para "0 grados reales" como para "lectura SMN/PCI fallida" (`AMDRyzenCPUPowerManagement.cpp:1210-1212`). Ese valor alimenta el EMA, produce `tempIdx = 0` → `lut[0]`, y hace que `rawSourceTemp >= 85.0f` sea permanentemente falso. Combinado con la **ausencia total de piso mínimo de PWM en modo curva** y la **ausencia de detección de estancamiento por RPM**, un único fallo persistente de lectura del SMN produce el peor escenario posible: duty mínimo, guard desactivado, y ningún mecanismo de detección.

Los tickets `KRN-00` … `KRN-05` corrigen exactamente esa cadena y son la prioridad absoluta. Todo lo demás es estabilidad, fugas de energía y correcciones de concurrencia.

### Índice de tickets

| ID | Severidad | Título | Capa |
|---|---|---|---|
| `KRN-00` | Crítica | Constantes de seguridad ausentes (piso de PWM, sentinel de temp inválida) | kext hpp |
| `KRN-01` | Crítica | EMA envenenable por NaN/temperatura inválida, de forma permanente | kext |
| `KRN-02` | Crítica | Sin piso mínimo de PWM en modo curva + guard evaluado contra sensor equivocado | kext |
| `KRN-03` | Crítica | Ventilador en modo manual queda latcheado para siempre si la app muere | kext UserClient |
| `KRN-04` | Alta | `getPackageTemp()` no distingue error de 0 °C | kext |
| `KRN-05` | Media | Selectores 96 y 102(-1) sin guard térmico | kext UserClient |
| `IOK-01` | Alta | TOCTOU / use-after-close sobre `io_connect_t`; llamada IOKit sin serializar | Swift |
| `IOK-02` | Alta | Selector 8 aborta toda la inicialización; `isKextAvailable` queda en `true` sin datos | Swift |
| `IOK-03` | Alta | Handle obsoleto pero no-cero jamás se recupera tras sleep | Swift |
| `IOK-04` | Media | Fallo de privilegio del selector 103 se descarta en silencio | Swift |
| `IOK-05` | Media | Sin `IOExternalMethodDispatch`: toda validación de tamaño es artesanal | kext (arquitectura) |
| `CON-01` | Alta | IOKit sincrónico en `@MainActor` disparado desde `didSet` de `@Published` | Swift |
| `CON-02` | Alta | Ningún observador de `willSleepNotification`: 4 timers siguen sondeando dormidos | Swift |
| `CON-03` | Alta | `pollTimer` en modo `.default`: el guard térmico manual se suspende al abrir un menú | Swift |
| `CON-04` | Baja | `iokitLock` muerto; bucles que no rompen con `self == nil`; `deinit` inalcanzable | Swift |
| `SIO-01` | Alta | Tacómetro sin validar: `0xFFFF` → 65535 RPM latcheado permanentemente en `fanPeakRPMs` | kext SuperIO |
| `SIO-02` | Media | `readWord()` no atómico: desgarro de bytes alto/bajo | kext SuperIO |
| `SIO-03` | Media | 0 RPM indistinguible de sensor muerto; sin detección de estancamiento | kext + Swift |
| `UI-01` | Media | `stateKey` sin token de apariencia: composites Dark/Light obsoletos toda la sesión | AppKit |
| `UI-02` | Media | Marquesina Now Playing a 20 Hz compone `NSImage` sin caché | AppKit |
| `UI-03` | Media | Dashboard desacoplado mantiene cadencia foreground al estar ocluido | AppKit |
| `UI-04` | Media | `AppVolumeMixer` residente con 3 listeners HAL estando "desactivado" | Swift |
| `UI-05` | Baja | `.screenRecorder` sin entrada en `FeatureRuntime.bindings` | Swift |
| `BLD-01` | Media | Sin Swift 6 / strict concurrency: ninguna de estas invariantes está forzada | Build |

---

# MÓDULO 1 — Seguridad térmica del kernel (CRÍTICO)

> **Aplicar `KRN-00` primero.** `KRN-01` y `KRN-02` dependen de sus constantes. Los tres bloques son regiones contiguas pero **disjuntas** de `evaluateFanCurves()`.

---

### [KRN-00] Constantes de seguridad ausentes: piso de PWM en modo curva y sentinel de temperatura inválida

- **Severidad**: Crítica (habilitador de KRN-01/KRN-02)
- **Archivos Afectados**: `SMCAMDProcessor_Source/AMDRyzenCPUPowerManagement/AMDRyzenCPUPowerManagement.hpp:95-100`
- **Diagnóstico & Causa Raíz**: El kext solo define el guard de emergencia (`kTHERMAL_GUARD_TEMP_C` / `kTHERMAL_GUARD_PWM`). No existe:
  1. Un **piso mínimo de PWM activo**. `overrideFanControl()` escribe literalmente cualquier valor no-cero de la LUT, incluidos `1`, `2`, `3` (≈0.4-1.2 % duty). Por debajo de ~15 % duty un rotor de 120 mm típico no arranca ni se mantiene: queda calado, consumiendo corriente de bloqueo, y como **no existe realimentación por RPM** (ver `SIO-03`) el sistema nunca lo detecta. `AMDFanSafety.minimumManualPWM = 3` en Swift solo cubre modo manual y además es demasiado bajo para ser un piso real.
  2. Un **sentinel de temperatura inválida**. `0.0f` se usa como valor de error, y `0 °C` es a la vez un índice legítimo de la LUT.
  3. Un **PWM de failsafe** para aplicar cuando la temperatura no es fiable.
- **Instrucción de Reemplazo para Gemini 3.8 Flash**:
  - Acción: REPLACE
  - Buscar bloque:
    ```cpp
//
// Thermal guard bounds shared between the power-management driver and the
// UserClient: above kTHERMAL_GUARD_TEMP_C, any fan command is clamped to at
// least kTHERMAL_GUARD_PWM (curve mode and manual mode alike).
//
static constexpr float    kTHERMAL_GUARD_TEMP_C = 85.0f;
static constexpr uint8_t  kTHERMAL_GUARD_PWM    = 200;   // ~78.4% duty
    ```
  - Sustituir por:
    ```cpp
    //
    // Thermal guard bounds shared between the power-management driver and the
    // UserClient: above kTHERMAL_GUARD_TEMP_C, any fan command is clamped to at
    // least kTHERMAL_GUARD_PWM (curve mode and manual mode alike).
    //
    static constexpr float    kTHERMAL_GUARD_TEMP_C = 85.0f;
    static constexpr uint8_t  kTHERMAL_GUARD_PWM    = 200;   // ~78.4% duty

    //
    // S10 KRN-00: hardware safety bounds for curve-mode fan output.
    //
    // kCURVE_MIN_ACTIVE_PWM — minimum duty that will actually be written to the
    // Super I/O once a fan is under curve control. PWM 0 keeps its special
    // meaning ("release this fan back to BIOS/SmartFan"), but ANY non-zero
    // request below this floor is raised to it. Rationale: this driver runs a
    // strictly open-loop controller (no RPM feedback, see SIO-03), so a duty
    // below the rotor's start threshold produces a silently stalled fan drawing
    // locked-rotor current with zero airflow and zero detection. 40/255 ≈ 15.7 %
    // is above the documented start duty of every mainstream 4-pin PWM fan.
    static constexpr uint8_t  kCURVE_MIN_ACTIVE_PWM = 40;    // ~15.7% duty

    // kTEMP_INVALID — explicit sentinel for "temperature could not be read".
    // getPackageTemp() historically returned 0.0f for BOTH a genuine 0 °C and a
    // failed SMN/PCI transaction; 0 °C simultaneously selects lut[0] (the
    // coldest, slowest point of the curve) AND makes the >= 85 °C guard test
    // false. That is fail-dangerous. Callers must test isTempValid().
    static constexpr float    kTEMP_INVALID = -1000.0f;

    // kFAILSAFE_PWM — duty applied when the control loop cannot trust its own
    // temperature input. Deliberately audible: a loud fan is a correct and
    // self-announcing failure mode, a silent stalled fan is not.
    static constexpr uint8_t  kFAILSAFE_PWM = 160;           // ~62.7% duty

    // Valid Zen package-temperature window (matches getPackageTemp()'s own
    // range test). NaN and infinities fail this test by construction.
    static inline bool isTempValid(float t) {
        return (t == t) && (t > -20.0f) && (t < 135.0f);
    }
    ```
- **Consideraciones de Seguridad & Edge Cases**: `kCURVE_MIN_ACTIVE_PWM = 40` es un compromiso deliberado: sube el ruido en reposo para curvas configuradas con anclas muy bajas (1-15 %), pero elimina el estancamiento silencioso. Si el proyecto quiere permitir modo 0-RPM real, la forma correcta es que la curva mapee a **exactamente 0** (liberar a BIOS), no a un duty ínfimo. `isTempValid` es `static inline` en el header y usa `(t == t)` en lugar de `isnan()` porque el entorno kernel de Lilu no garantiza `<cmath>`; `-ffast-math` no se usa en este target (verificado: `build.sh` y el proyecto Xcode del kext no lo activan), así que el idioma es seguro.
- **Comando de Verificación**:
  ```sh
  # El header es compartido; compila el kext para validar sintaxis/constexpr.
  cd SMCAMDProcessor_Source && xcodebuild -project AMDRyzenCPUPowerManagement.xcodeproj \
    -target AMDRyzenCPUPowerManagement -configuration Release build 2>&1 | tail -20
  # Debe terminar en "BUILD SUCCEEDED".
  ```

---

### [KRN-01] El EMA se envenena de forma permanente con NaN o temperatura inválida, desarmando el guard térmico

- **Severidad**: Crítica
- **Archivos Afectados**: `SMCAMDProcessor_Source/AMDRyzenCPUPowerManagement/AMDRyzenCPUPowerManagement.cpp:2290-2302`
- **Diagnóstico & Causa Raíz**: El filtro EMA (α = 0.2, período 500 ms, τ ≈ 2.24 s) no valida su entrada:
  1. **NaN es absorbente y permanente.** `curveSmoothedTemp[c] = 0.2*NaN + 0.8*prev = NaN`. `curveSmoothedSeeded[c]` solo se limpia en (re)init del kext — nunca se resetea, ni siquiera en `initSuperIO()` (que sí resetea `lastAppliedTemp`/`lastAppliedPWM` en `cpp:2241-2250`). Una vez NaN, ese carril de curva queda NaN hasta el reinicio: `(int)(NaN + 0.5f)` es UB (en práctica `0` o `INT_MIN`, luego clampeado a 0) → `lut[0]`, y `NaN >= 85.0f` es **falso** → **guard de emergencia permanentemente derrotado**.
  2. **`0.0f` de error entra como dato válido.** Una lectura SMN fallida (`getPackageTemp()` → `0.0f`) arrastra el EMA hacia 0 durante ~11 s, seleccionando el punto más frío de la curva mientras el silicio puede estar a 95 °C.
  3. El bucle corre para los 4 slots **incluso si no están mapeados a ningún ventilador**, así que un slot sin usar puede acumular basura que se activa en el instante en que el usuario lo mapea.
- **Instrucción de Reemplazo para Gemini 3.8 Flash**:
  - Acción: REPLACE
  - Buscar bloque:
    ```cpp
    // 2. Smooth temperature per curve once before evaluating fan loop (KRN-07, KRN-09)
    for (int c = 0; c < MAX_FAN_CURVES; c++) {
        FanCurveConfig &config = fanCurves[c];
        float rawSourceTemp = (config.sourceSensor == 1 && gpuTemp > 0.0f) ? gpuTemp : cpuTemp;
        if (!curveSmoothedSeeded[c]) {
            curveSmoothedTemp[c] = rawSourceTemp;
            curveSmoothedSeeded[c] = true;
        } else {
            float alpha = 0.2f;
            float prev = curveSmoothedTemp[c];
            curveSmoothedTemp[c] = (alpha * rawSourceTemp) + ((1.0f - alpha) * prev);
        }
    }
    ```
  - Sustituir por:
    ```cpp
    // 2. Smooth temperature per curve once before evaluating fan loop (KRN-07, KRN-09)
    //
    // S10 KRN-01: the EMA is now validated on both input and output.
    //  - A non-finite or out-of-range sample is NEVER fed into the filter; it is
    //    dropped and the slot is marked unseeded so the next good sample re-seeds
    //    instantly instead of crawling back over ~11 s from a poisoned value.
    //  - NaN used to be absorbing AND permanent (seeded flag was never cleared),
    //    which pinned the fan at lut[0] with the 85 °C guard silently disabled.
    //  - The per-slot validity flag is consumed by the fan loop below, which
    //    applies kFAILSAFE_PWM instead of trusting a stale/absent reading.
    for (int c = 0; c < MAX_FAN_CURVES; c++) {
        FanCurveConfig &config = fanCurves[c];

        // Pick the configured source, falling back to CPU when the GPU bridge
        // (selector 103) has not published a usable value yet.
        float rawSourceTemp = cpuTemp;
        if (config.sourceSensor == 1 && isTempValid(gpuTemp) && gpuTemp > 0.0f) {
            rawSourceTemp = gpuTemp;
        }

        if (!isTempValid(rawSourceTemp)) {
            // Reject the sample outright. Unseeding is deliberate: it prevents a
            // stale smoothed value from being reported as trustworthy, and lets
            // the next valid reading re-seed without EMA lag.
            curveSmoothedValid[c] = false;
            curveSmoothedSeeded[c] = false;
            continue;
        }

        if (!curveSmoothedSeeded[c]) {
            curveSmoothedTemp[c] = rawSourceTemp;
            curveSmoothedSeeded[c] = true;
        } else {
            const float alpha = 0.2f;
            float prev = curveSmoothedTemp[c];
            if (!isTempValid(prev)) {
                // Defensive: a previously poisoned accumulator re-seeds instead
                // of propagating the poison forward.
                curveSmoothedTemp[c] = rawSourceTemp;
            } else {
                curveSmoothedTemp[c] = (alpha * rawSourceTemp) + ((1.0f - alpha) * prev);
            }
        }

        // Final output guard: if the filter produced anything non-finite, fall
        // back to the raw sample rather than publishing garbage downstream.
        if (!isTempValid(curveSmoothedTemp[c])) {
            curveSmoothedTemp[c] = rawSourceTemp;
        }
        curveSmoothedValid[c] = true;
        curveRawSourceTemp[c] = rawSourceTemp;
    }
    ```
- **Consideraciones de Seguridad & Edge Cases**: Requiere tres arrays nuevos en el header (ver bloque de apoyo abajo). Si **ambas** fuentes fallan, `curveSmoothedValid[c]` queda `false` y `KRN-02` aplica `kFAILSAFE_PWM` — nunca `lut[0]`. Nótese que ahora la condición de fallback GPU→CPU también valida el rango, cerrando la vía en la que `gpuTemperatures[]` (llenado sin validar desde `AMDGPU::getTemperature()`, `cpp:394-397`) inyectaba valores como 511 °C directamente al filtro.
- **Bloque de apoyo obligatorio** (mismo ticket, archivo distinto, no solapa):
  - Acción: REPLACE
  - Archivo: `SMCAMDProcessor_Source/AMDRyzenCPUPowerManagement/AMDRyzenCPUPowerManagement.hpp:532-536`
  - Buscar bloque:
    ```cpp
    float curveSmoothedTemp[MAX_FAN_CURVES];
    bool curveSmoothedSeeded[MAX_FAN_CURVES] {};
    ```
  - Sustituir por:
    ```cpp
    float curveSmoothedTemp[MAX_FAN_CURVES];
    bool curveSmoothedSeeded[MAX_FAN_CURVES] {};
    // S10 KRN-01: per-curve trust flag for the smoothed temperature, plus the
    // unsmoothed sample the emergency guard must be evaluated against.
    // curveSmoothedValid[c] == false means "no trustworthy reading this tick" and
    // forces kFAILSAFE_PWM instead of lut[0].
    bool curveSmoothedValid[MAX_FAN_CURVES] {};
    float curveRawSourceTemp[MAX_FAN_CURVES] {};
    ```
- **Comando de Verificación**:
  ```sh
  cd SMCAMDProcessor_Source && xcodebuild -project AMDRyzenCPUPowerManagement.xcodeproj \
    -target AMDRyzenCPUPowerManagement -configuration Release build 2>&1 | grep -E "error|warning|BUILD"
  ```

---

### [KRN-02] Modo curva sin piso mínimo de PWM, y guard de emergencia evaluado contra el sensor equivocado

- **Severidad**: Crítica
- **Archivos Afectados**: `SMCAMDProcessor_Source/AMDRyzenCPUPowerManagement/AMDRyzenCPUPowerManagement.cpp:2317-2370`
- **Diagnóstico & Causa Raíz**: Tres defectos independientes en el cuerpo por ventilador:
  1. **Sin piso de PWM.** `uint8_t targetPWM = config.lut[tempIdx]` se escribe verbatim vía `overrideFanControl()`. La ventana peligrosa es exactamente **PWM 1…39** (≈0.4-15 %): el editor de curvas permite anclas de 1 % (`FanCurveEditor.swift:428`, `max(1.0, ...)`), y `1 % → round(1×2.55) = 3` raw. Rotor calado, sin airflow, sin detección.
  2. **Guard evaluado contra `rawSourceTemp`, no contra el peor sensor.** Para una curva con `sourceSensor == 1` (GPU), `rawSourceTemp` es la temperatura de la **GPU**. Escenario real: CPU a 95 °C, dGPU en idle a 40 °C → el guard de 85 °C nunca dispara y el ventilador de CPU se queda en el valor bajo derivado de la curva GPU. El guard de emergencia debe ser un límite **global** del sistema, no por-sensor.
  3. **Temperatura no fiable trata como 0 °C.** Sin la señal de validez de `KRN-01`, `tempIdx` cae a 0 → `lut[0]`.
  Adicionalmente `deltaTime = (now - lastTime)/1e9` no está acotado: tras un sleep o un stall del workloop, `limit = rampRate * deltaTime` se vuelve efectivamente infinito y el ramp-limiting desaparece en un solo paso.
- **Instrucción de Reemplazo para Gemini 3.8 Flash**:
  - Acción: REPLACE
  - Buscar bloque:
    ```cpp
        float rawSourceTemp = cpuTemp;
        if (config.sourceSensor == 1) {
            rawSourceTemp = gpuTemp > 0.0f ? gpuTemp : cpuTemp; // Fallback to CPU if GPU not updated
        }
        
        float smoothed = curveSmoothedTemp[curveIdx];
        
        // 4. Map temperature index (0 - 255) with proper rounding
        int tempIdx = (int)(smoothed + 0.5f);
        if (tempIdx < 0) tempIdx = 0;
        if (tempIdx > 255) tempIdx = 255;
        
        // 5. Look up target PWM from LUT
        uint8_t targetPWM = config.lut[tempIdx];
    ```
  - Sustituir por:
    ```cpp
        // S10 KRN-02 (a): trust gate. curveSmoothedValid[] is published by the
        // EMA stage above; false means neither the configured source nor the CPU
        // fallback produced a reading inside the valid Zen window this tick.
        // Previously an unreadable sensor decayed to 0.0f, which selected lut[0]
        // (slowest point) AND made the >= 85 °C test false — the two worst
        // outcomes at once. Now it forces an audible, self-announcing failsafe.
        if (!curveSmoothedValid[curveIdx]) {
            superIO->overrideFanControl(fanIdx, kFAILSAFE_PWM);
            lastAppliedPWM[fanIdx] = kFAILSAFE_PWM;
            lastAppliedTempSeeded[curveIdx] = false;
            lastPWMUpdateTime[fanIdx] = now;
            continue;
        }

        float rawSourceTemp = curveRawSourceTemp[curveIdx];
        float smoothed = curveSmoothedTemp[curveIdx];

        // S10 KRN-02 (b): the emergency guard is a SYSTEM-WIDE limit, so it is
        // armed from the hottest trustworthy sensor, never from the curve's own
        // configured source. A GPU-sourced curve used to leave a 95 °C CPU
        // running at the (cool) GPU curve's low duty.
        float guardTemp = rawSourceTemp;
        if (isTempValid(cpuTemp) && cpuTemp > guardTemp) guardTemp = cpuTemp;
        if (isTempValid(gpuTemp) && gpuTemp > guardTemp) guardTemp = gpuTemp;

        // 4. Map temperature index (0 - 255) with proper rounding.
        // smoothed is guaranteed finite and in (-20, 135) by the EMA stage.
        int tempIdx = (int)(smoothed + 0.5f);
        if (tempIdx < 0) tempIdx = 0;
        if (tempIdx > 255) tempIdx = 255;

        // 5. Look up target PWM from LUT
        uint8_t targetPWM = config.lut[tempIdx];
    ```
- **Segundo bloque del mismo ticket** (región disjunta, ~40 líneas más abajo):
  - Acción: REPLACE
  - Buscar bloque:
    ```cpp
        // 7.5. Apply Thermal Safety Guard (above kTHERMAL_GUARD_TEMP_C, force at least kTHERMAL_GUARD_PWM)
        if (rawSourceTemp >= kTHERMAL_GUARD_TEMP_C) {
            targetPWM = (targetPWM < kTHERMAL_GUARD_PWM) ? kTHERMAL_GUARD_PWM : targetPWM;
        }
    ```
  - Sustituir por:
    ```cpp
        // 7.5. Apply the minimum-duty floor, then the emergency thermal guard.
        //
        // S10 KRN-02 (c): PWM 0 keeps its special meaning ("hand this fan back
        // to BIOS/SmartFan"), but any non-zero request below
        // kCURVE_MIN_ACTIVE_PWM is raised to it. This controller is open-loop
        // (no RPM feedback), so writing 1..39 produced a silently stalled rotor
        // with no airflow and no way to notice. The floor is applied AFTER
        // hysteresis/ramp limiting so those stages cannot smuggle a sub-floor
        // value through, and BEFORE the guard so the guard always wins.
        if (targetPWM != 0 && targetPWM < kCURVE_MIN_ACTIVE_PWM) {
            targetPWM = kCURVE_MIN_ACTIVE_PWM;
        }

        // Emergency thermal guard, armed from the hottest trustworthy sensor.
        // Placed last so it overrides the floor, the ramp limiter and the
        // release-to-BIOS branch alike: a hot fan is never handed back to BIOS.
        if (guardTemp >= kTHERMAL_GUARD_TEMP_C) {
            targetPWM = (targetPWM < kTHERMAL_GUARD_PWM) ? kTHERMAL_GUARD_PWM : targetPWM;
        }
    ```
- **Consideraciones de Seguridad & Edge Cases**:
  - `targetPWM == 0` sigue liberando a BIOS (`setDefaultFanControl`), que es el camino seguro y la forma correcta de implementar 0-RPM: la LUT debe mapear a 0 exacto, no a 3.
  - Si `guardTemp >= 85 °C` y la LUT pedía 0, el guard eleva a 200 **antes** de la rama `targetPWM == 0`, así que el ventilador ya no se entrega a BIOS en caliente. Esto es un endurecimiento respecto al comportamiento previo.
  - Con `>= 90 °C` sostenido y el ventilador ya al máximo, el kext no puede hacer más: la mitigación real es PROCHOT/CHTC (selectores 45/46), fuera del alcance de este ticket.
  - Si el usuario no tiene privilegios, nada de esto se ejecuta: el lazo vive en kernel y no depende del cliente.
- **Comando de Verificación**:
  ```sh
  cd SMCAMDProcessor_Source && xcodebuild -project AMDRyzenCPUPowerManagement.xcodeproj \
    -target AMDRyzenCPUPowerManagement -configuration Release build 2>&1 | grep -E "error|BUILD"
  # Probe en hardware, tras cargar el kext:
  sudo dmesg | grep -i "AMDRyzenCPUPowerManagement" | tail -20
  ```

---

### [KRN-03] Un ventilador en modo manual queda latcheado indefinidamente si la app muere (crash / SIGKILL)

- **Severidad**: Crítica
- **Archivos Afectados**: `SMCAMDProcessor_Source/AMDRyzenCPUPowerManagement/AMDRyzenCPUPMUserClient.cpp:82-85`
- **Diagnóstico & Causa Raíz**: Éste es el estado residual más peligroso del subsistema. En modo manual, `fanToCurveMap[fan] == -1`, por lo que `evaluateFanCurves()` hace `continue` (`cpp:2305-2308`) y **nada vuelve a escribir ese ventilador jamás**. El guard térmico para ventiladores manuales vive en dos sitios y ninguno sobrevive a la muerte de la app:
  - `FanCurveController.enforceManualThermalGuard()` — timer de 1.5 s **en el proceso de la app**.
  - La ruta de *escritura* del selector 95 — solo actúa cuando alguien escribe.

  `clientClose()` es `terminate(); return kIOReturnSuccess;` — no restaura ventiladores. La única restauración en kernel está en `AMDRyzenCPUPowerManagement::stop()` (`cpp:806-816`), es decir, descarga del kext o apagado. Resultado tras un `SIGKILL` con un ventilador a PWM 3: **queda a ~1 % duty de forma indefinida, sin guard térmico de ningún tipo**. La ruta de salida limpia sí funciona (`AppDelegate.swift:186` → `resetFansToAutoSync()`), pero un crash no la ejecuta.
- **Instrucción de Reemplazo para Gemini 3.8 Flash**:
  - Acción: REPLACE
  - Buscar bloque:
    ```cpp
IOReturn AMDRyzenCPUPMUserClient::clientClose() {
    terminate();
    return kIOReturnSuccess;
}
    ```
  - Sustituir por:
    ```cpp
    IOReturn AMDRyzenCPUPMUserClient::clientClose() {
        //
        // S10 KRN-03: dead-man switch.
        //
        // clientClose() is the ONLY kernel callback guaranteed to run when the
        // userspace client goes away — including SIGKILL, a crash, or a force
        // quit, none of which reach AppDelegate.applicationWillTerminate and its
        // resetFansToAutoSync().
        //
        // Why this matters: a fan in manual mode has fanToCurveMap[fan] == -1,
        // so evaluateFanCurves() skips it entirely. Nothing in the kernel ever
        // writes it again, and the manual-mode thermal guard lives in the app's
        // 1.5 s timer. So a crash while a fan sat at PWM 3 (~1 % duty) left that
        // fan latched at 1 % forever, with no guard and no airflow.
        //
        // Handing every fan back to BIOS/SmartFan is the correct failure mode:
        // the firmware controller is always safe, never stalls, and needs no
        // client. Curve-mode fans are released too — they will be re-uploaded
        // and re-mapped on the next client connection (selectors 101/102), and
        // FanCurveController.handleWakeNotification() already forces that sync.
        //
        AMDRyzenCPUPowerManagement *provider = fProvider;
        if (provider && provider->superIOLock) {
            IOLockLock(provider->superIOLock);
            if (provider->superIO) {
                int fanCount = provider->superIO->getNumberOfFans();
                for (int i = 0; i < fanCount; i++) {
                    provider->fanToCurveMap[i] = -1;
                    provider->superIO->setDefaultFanControl(i);
                    provider->lastAppliedPWM[i] = 0;
                }
                IOLog("AMDRyzenCPUPMUserClient: clientClose released %d fan(s) to BIOS control\n", fanCount);
            }
            IOLockUnlock(provider->superIOLock);
        }

        terminate();
        return kIOReturnSuccess;
    }
    ```
- **Consideraciones de Seguridad & Edge Cases**:
  - `fProvider` puede ser `nullptr` si `stop()` corrió antes (`cpp:76-81` lo anula): el guard `if (provider && ...)` lo cubre y se degrada a solo `terminate()`.
  - Se toma `superIOLock` para no correr contra el timer de 500 ms de `evaluateFanCurves()`, que también lo toma. `clientClose()` corre en contexto de proceso, no de interrupción, así que bloquear es legal.
  - `fanToCurveMap` y `lastAppliedPWM` deben ser accesibles desde el UserClient. Ya lo son: el UserClient escribe `provider->fanToCurveMap[fanIdx]` en el caso 102 (`cpp:1587`), así que la visibilidad está establecida y no hace falta tocar el header.
  - Coste: al cerrar la app los ventiladores vuelven a BIOS y luego la app los recupera al arrancar — exactamente lo que ya hace la ruta limpia.
  - Efecto secundario deseable: cierra también el escenario "el usuario mata la app desde Monitor de Actividad mientras hay una curva agresiva cargada".
- **Comando de Verificación**:
  ```sh
  cd SMCAMDProcessor_Source && xcodebuild -project AMDRyzenCPUPowerManagement.xcodeproj \
    -target AMDRyzenCPUPowerManagement -configuration Release build 2>&1 | grep -E "error|BUILD"
  # Probe en hardware: fija un ventilador en manual bajo, mata la app, verifica retorno a auto.
  # sudo pkill -9 RyzenStatus && sleep 2 && sudo dmesg | grep "clientClose released"
  ```

---

### [KRN-04] `getPackageTemp()` no distingue un fallo de lectura de un genuino 0 °C

- **Severidad**: Alta
- **Archivos Afectados**: `SMCAMDProcessor_Source/AMDRyzenCPUPowerManagement/AMDRyzenCPUPowerManagement.cpp:1183-1213`
- **Diagnóstico & Causa Raíz**: La función usa `0.0f` como valor de error en tres rutas distintas (sin dispositivo PCI, sin lock, valor fuera de rango). Una lectura SMN de todo-unos da `(0xFFFFFFFF >> 21) * 125 = 255875` → 255.875 °C → cae en `t > 135.0f` → devuelve `0.0f`, **indistinguible de 0 °C real**. Además el rango de rechazo `t < -20.0f` deja pasar el intervalo `-20 … -0.001 °C`, y `(int)(smoothed + 0.5f)` trunca hacia cero para negativos (redondeo roto) antes de clampear a 0. `KRN-01`/`KRN-02` ya blindan el consumidor principal; este ticket corrige la fuente para que el resto de consumidores (`tempSamples[]`, `PACKAGE_TEMPERATURE_perPackage[0]` usado por el guard del selector 95, SMC keys) también puedan distinguir el fallo.
- **Instrucción de Reemplazo para Gemini 3.8 Flash**:
  - Acción: REPLACE
  - Buscar bloque:
    ```cpp
inline float AMDRyzenCPUPowerManagement::getPackageTemp() {
    if (!fIOPCIDevice || !pciConfigLock) return 0.0f;
    ```
  - Sustituir por:
    ```cpp
    // S10 KRN-04: returns kTEMP_INVALID (not 0.0f) when the reading cannot be
    // trusted. 0.0f was ambiguous with a genuine 0 °C, and 0 °C is the single
    // most dangerous value in this driver: it selects lut[0] (slowest duty) and
    // simultaneously makes every ">= 85 °C" guard test false. Callers must use
    // isTempValid() rather than "> 0.0f".
    inline float AMDRyzenCPUPowerManagement::getPackageTemp() {
        if (!fIOPCIDevice || !pciConfigLock) return kTEMP_INVALID;
    ```
  - Acción: REPLACE (segundo bloque, misma función)
  - Buscar bloque:
    ```cpp
    if (t < -20.0f || t > 135.0f) {
        return 0.0f;
    }
    
    return t;
}
    ```
  - Sustituir por:
    ```cpp
        // Reject NaN, infinities and anything outside the plausible Zen window.
        // (t == t) is the NaN test; -ffast-math is not enabled for this target.
        if (!(t == t) || t < -20.0f || t > 135.0f) {
            return kTEMP_INVALID;
        }

        return t;
    }
    ```
- **Consideraciones de Seguridad & Edge Cases**: **Este ticket cambia un contrato compartido.** Tras aplicarlo hay que revisar todo consumidor que compare contra `> 0.0f`. Auditoría de llamantes:
  - `evaluateFanCurves()` — ya cubierto por `KRN-01`/`KRN-02` vía `isTempValid()`. ✅
  - `updatePackageTemp()` → `PACKAGE_TEMPERATURE_perPackage[0]`: **debe filtrar** para no publicar `-1000` a las SMC keys ni al guard del selector 95. Verificación obligatoria:
    ```sh
    grep -n "getPackageTemp()" SMCAMDProcessor_Source/AMDRyzenCPUPowerManagement/*.cpp
    ```
    En cada sitio que asigne a `PACKAGE_TEMPERATURE_perPackage` o a `tempSamples`, envolver con `if (isTempValid(t)) { ... }` y dejar el último valor bueno en caso contrario. Nota importante: el guard del selector 95 usa `>= kTHERMAL_GUARD_TEMP_C`, y `-1000 >= 85` es falso, así que **un valor inválido no dispara falsos positivos**, pero tampoco protege — exactamente el mismo hueco que ya existía con `0.0f`, sin regresión.
  - Si el proyecto prefiere no tocar el contrato en esta oleada, `KRN-01`+`KRN-02` ya son suficientes para la seguridad del lazo de ventiladores; `KRN-04` puede diferirse. **No aplicar `KRN-04` a medias.**
- **Comando de Verificación**:
  ```sh
  grep -n "getPackageTemp()\|PACKAGE_TEMPERATURE_perPackage" \
    SMCAMDProcessor_Source/AMDRyzenCPUPowerManagement/AMDRyzenCPUPowerManagement.cpp
  cd SMCAMDProcessor_Source && xcodebuild -project AMDRyzenCPUPowerManagement.xcodeproj \
    -target AMDRyzenCPUPowerManagement -configuration Release build 2>&1 | grep -E "error|BUILD"
  ```

---

### [KRN-05] Selectores 96 y 102(-1) permiten liberar a BIOS un ventilador por encima de 85 °C sin guard

- **Severidad**: Media
- **Archivos Afectados**: `SMCAMDProcessor_Source/AMDRyzenCPUPowerManagement/AMDRyzenCPUPMUserClient.cpp:1398-1419` (caso 96), `:1560-1593` (caso 102)
- **Diagnóstico & Causa Raíz**: El caso 95 (escritura manual de PWM) sí aplica el guard térmico (`:1370-1380`, marcador `S2-T4b`). Los casos 96 (`setDefaultFanControl`) y 102 con `curveIdx == -1` no lo hacen: cualquier cliente privilegiado puede devolver a BIOS un ventilador con el paquete a 95 °C. En la práctica el riesgo es **bajo** — el controlador del firmware es competente y subirá el ventilador — pero es una asimetría de política: `evaluateFanCurves()` fue endurecido explícitamente (`KRN-02`) para *no* liberar un ventilador caliente, y estos dos selectores contradicen esa invariante. También es el mecanismo exacto que usa `resetFansToAutoSync()` en la salida, así que corresponde documentar la excepción antes que bloquearla.
- **Instrucción de Reemplazo para Gemini 3.8 Flash**:
  - Acción: INSERT (justo antes de `provider->superIO->setDefaultFanControl(fanSel);` en el caso 96)
  - Buscar bloque:
    ```cpp
            if (fanSel < 0 || fanSel >= provider->superIO->getNumberOfFans()) {
                IOLockUnlock(provider->superIOLock);
                return kIOReturnBadArgument;
            }
            provider->superIO->setDefaultFanControl(fanSel);
            IOLockUnlock(provider->superIOLock);
            
            break;
        }
        
        //SMC Secret Undocumented feature
    ```
  - Sustituir por:
    ```cpp
            if (fanSel < 0 || fanSel >= provider->superIO->getNumberOfFans()) {
                IOLockUnlock(provider->superIOLock);
                return kIOReturnBadArgument;
            }

            // S10 KRN-05: releasing a fan to BIOS/SmartFan is normally the safe
            // direction, and it is the mechanism the app uses on quit
            // (resetFansToAutoSync). But handing back a fan while the package is
            // already in the emergency band creates a window where neither this
            // driver nor a not-yet-ramped firmware controller is holding the
            // fan up. Keep the fan pinned at the guard duty instead; the next
            // request below 85 °C will release it normally.
            if (provider->PACKAGE_TEMPERATURE_perPackage[0] >= kTHERMAL_GUARD_TEMP_C) {
                provider->superIO->overrideFanControl(fanSel, kTHERMAL_GUARD_PWM);
                IOLockUnlock(provider->superIOLock);
                IOLog("AMDRyzenCPUPMUserClient: selector 96 deferred on fan %d (package >= %d C)\n",
                      fanSel, (int)kTHERMAL_GUARD_TEMP_C);
                return kIOReturnBusy;
            }

            provider->superIO->setDefaultFanControl(fanSel);
            IOLockUnlock(provider->superIOLock);
            
            break;
        }
        
        //SMC Secret Undocumented feature
    ```
- **Consideraciones de Seguridad & Edge Cases**: Devolver `kIOReturnBusy` es informativo, no fatal. Revisar el llamante: `FanCurveController.resetFansToAutoSync()` descarta el retorno (`_ = ProcessorModel.shared.setFanMode(...)`), así que apagar la app a 95 °C dejará los ventiladores al 78 % en vez de en BIOS — **comportamiento deliberado y más seguro**, pero `KRN-03` los libera después vía `clientClose()`, que corre cuando el proceso ya murió y el silicio se está enfriando. Nótese la interacción: `clientClose()` (KRN-03) **sí** libera sin comprobar temperatura, y eso es correcto — en ese punto no hay ningún cliente que pueda mantener el lazo, así que BIOS es la única opción viable.
- **Comando de Verificación**:
  ```sh
  cd SMCAMDProcessor_Source && xcodebuild -project AMDRyzenCPUPowerManagement.xcodeproj \
    -target AMDRyzenCPUPowerManagement -configuration Release build 2>&1 | grep -E "error|BUILD"
  ```


---

# MÓDULO 2 — Capa IOKit y ciclo de vida de Mach Ports

## 2.0 Veredicto sobre fugas de puertos: **limpio**

Auditados todos los sitios de `IOServiceGetMatchingService` / `IOServiceOpen` / `IOServiceClose` / `IOObjectRelease`:

| Sitio | Patrón | Veredicto |
|---|---|---|
| `ProcessorModel.swift:435-450` (`init`) | `IOObjectRelease(serviceObject)` en ambas ramas de `IOServiceOpen` | ✅ sin fuga |
| `ProcessorModel.swift:459-489` (watchdog) | `IOObjectRelease` en la única rama donde es no-cero | ✅ sin fuga |
| `ProcessorModel.swift:498-512` (`attemptReconnect`) | `defer { IOObjectRelease(serviceObject) }` | ✅ sin fuga |
| `ProcessorModel.swift:23-47` (`ConnectBox`) | `install()` cierra el anterior; `closeIfOpen()` cierra y pone a 0 | ✅ sin fuga |
| `SMCClient.swift:33-42` | `defer` + `deinit { if connection != 0 { IOServiceClose(...) } }` | ✅ |
| `PowerSampler.swift:37-41,59-62,144-148,200-202` | libera en sonda, cachea y libera en `deinit`, pone a 0 al fallar | ✅ |
| `DiskSampler.swift:365-389`, `ProcessUsageService.swift:698-720` | iteradores con `defer` por nivel | ✅ |

**No hay ni un solo `io_service_t` ni `io_connect_t` filtrado.** Los ~60 puntos de llamada pasan todos por el único embudo `safeIOConnectCallMethod` (`:69-83`); ningún `IOConnectCallMethod` escapa al wrapper. Lo que sí existe es una **carrera de ciclo de vida** (`IOK-01`) y dos fallos de recuperación (`IOK-02`, `IOK-03`).

## 2.1 Correspondencia de selectores: **sin desalineamientos numéricos**

Comparada la tabla Swift (`Core/AMDKextSelectors.swift`, enum + constantes estáticas para los raw values duplicados) contra el `switch (selector)` del kext (`AMDRyzenCPUPMUserClient.cpp:150`). **Todo selector invocado desde Swift tiene su `case` en el kext.** Selectores solo-kext nunca invocados: 2, 3, 6, 9, 97, 98, 99. Sin huecos en el otro sentido.

Tamaños de estructura verificados en ambos lados:

| Sel | `requiredSize` kext | Buffer Swift | ¿Coincide? |
|---|---|---|---|
| 0 / 1 | 64 / 32 | 64 / 32 | ✅ |
| 4 | `(min(numPhyCores, MaxCpus) + 3) * 4` | `4 * 67` = 268 | ✅ *si* `MaxCpus == 64` (ver S-1) |
| 7 / 11 / 13 / 16 | 64 / 16 / 8 / 128 | 64 / 16 / 16 / 128 | ✅ |
| 20 / 21 | `ccdCount*4` / `numLogicalCores` | 32 / 64 | ✅ |
| 26 / 28 / 29 / 30 | 24 / 32 / 64 / 128 | 24 / 32 / 64 / 128 | ✅ |
| **100** | `sizeof(CPUSensorPacket)` = **304** | `CPUSensorPacket.byteSize` = **304** | ✅ |
| **101** | `sizeof(FanCurveInput)` = **272** (exacto, `!=`) | `AMDFanCurveInput.packedData()` = **272** | ✅ |
| **103** | escalar, `scalarInputCount != 1` | escalar, 1 | ✅ |
| 110 | `CPUInfo::MaxCpus` | 64 | ✅ *si* `MaxCpus == 64` |

### Selector 103 (bridging térmico dGPU) — presente y correcto en ambos lados

Kext `:1601-1618`: exige `scalarInputCount == 1`, `hasPrivilege(103)`, y clampea `[0, 120] °C`. Swift `ProcessorModel.swift:1774-1778`: clampea `[0, 120]` y convierte **por valor** (`UInt64(clamped)`), coherente con `float t = (float)scalarInput[0]` del kext. El comentario `AUDIT B-01` documenta el bug histórico (enviar el patrón de bits IEEE-754 hacía que todo decodificara como ~1e9 y clampeara a 120, fijando las curvas GPU al PWM máximo). **Es escalar puro: no hay struct que desalinear.** Dos observaciones:
- `UInt64(clamped)` **trapea con negativos**; sobrevive solo por el `max(0.0, ...)`. Si alguien amplía el clamp, es un crash.
- No existe cliente `SMCRadeonGPU`/`RadeonSensor` en `Sources/` (0 hits). La temperatura GPU viene de `ProcessorModel.lastKextGPUTemperature` (selectores 27-30) o `SystemMonitor.snapshot.gpuTemperature`.
- El fallo de privilegio se descarta en silencio → ticket `IOK-04`.

### Nota S-1 (informativa, sin acción obligatoria)
`CPUInfo::MaxCpus` proviene del submódulo VirtualSMC/CPUInfo, **cuyo contenido no está en este repositorio** (`.gitmodules` presente, árbol ausente). Los selectores 4 y 110 asumen `MaxCpus == 64` con literales hardcodeados (`ProcessorModel.swift:773-774`, `:1667`). Si el submódulo lo sube, el chequeo `if (maxLen < requiredSize) return kIOReturnBadArgument;` hace que **fallen en cerrado** (sin corrupción), pero core metrics y Curve Optimizer se apagarían con solo un `NSLog`. Recomendación: derivar ambos de una constante compartida y afirmarla en tests.

### Nota M-1 (informativa): `MemoryLayout.size` vs `.stride`
Los 15 usos de `MemoryLayout` en `ProcessorModel.swift` son todos `.size`, nunca `.stride`. Para `UInt8/16/32/64`, `Float`, `Int64` se cumple `size == stride`, así que **hoy no hay bug**. El idioma es incorrecto por defecto y sub-dimensionaría el buffer para cualquier tipo compuesto. Los cuatro helpers `kernelGet*` sí validan el tamaño devuelto y clampean con `min(count, outputSize / MemoryLayout<T>.size)` — ése es el patrón seguro y debe conservarse.

---

### [IOK-01] TOCTOU / use-after-close sobre `io_connect_t`, y ausencia total de serialización de llamadas IOKit

- **Severidad**: Alta
- **Archivos Afectados**: `Sources/RyzenStatus/Services/AMD/ProcessorModel.swift:69-83` (embudo), `:17` (lock muerto)
- **Diagnóstico & Causa Raíz**: Dos defectos acoplados en el mismo bloque de 15 líneas.
  1. **Use-after-close.** `safeIOConnectCallMethod` copia `connectBox.handle` *bajo el lock* (`:80`) y luego llama `IOConnectCallMethod` *fuera del lock* (`:82`). Concurrentemente, el watchdog (`:461-490`) puede ejecutar `install()` o `closeIfOpen()`, ambos de los cuales liberan el lock **antes** de `IOServiceClose(old)` (`:34`, `:44`). La llamada en vuelo invoca entonces un selector sobre un mach port ya cerrado. Normalmente devuelve `MACH_SEND_INVALID_DEST`, pero **los nombres de mach port se reciclan dentro de la misma task**, así que el selector podría entregarse a un user client no relacionado. El comentario "defensive; normally 0 here" en `:34` es inexacto: en la ruta de `attemptReconnect` cierra un handle vivo.
  2. **Cero serialización.** No existe ninguna cola serie de IOKit en el repo — el símbolo `IOKitSerialQueue` no aparece en ninguna parte, y `ProcessorModel.swift` no contiene ni una referencia a `DispatchQueue`. Llamantes concurrentes reales **hoy**: el MainActor (vía `FanCurveController`), la cola `.utility` de `SystemMonitor` (`:922`), el watchdog `.background`, el bucle de `AutoEppService`, el de `C6ResidencyService`, y dos `Task.detached` de `FanCurveController`. El `NSLock` de `ConnectBox` protege *solo la lectura del handle*, nunca la llamada. Y `iokitLock` (`:17`), declarado precisamente para esto, **nunca se bloquea**: `grep` devuelve solo la declaración y dos comentarios obsoletos (`:21`, `:497`).
- **Instrucción de Reemplazo para Gemini 3.8 Flash**:
  - Acción: REPLACE
  - Buscar bloque:
    ```swift
    nonisolated func safeIOConnectCallMethod(
        _ selector: UInt32,
        _ scalarInput: UnsafePointer<UInt64>!,
        _ scalarInputCount: UInt32,
        _ structureInput: UnsafeRawPointer!,
        _ structureInputSize: Int,
        _ scalarOutput: UnsafeMutablePointer<UInt64>!,
        _ scalarOutputCount: UnsafeMutablePointer<UInt32>!,
        _ structureOutput: UnsafeMutableRawPointer!,
        _ structureOutputSize: UnsafeMutablePointer<Int>!
    ) -> kern_return_t {
        let handle = connectBox.handle
        if handle == 0 { return kIOReturnNoDevice }
        return IOConnectCallMethod(handle, selector, scalarInput, scalarInputCount, structureInput, structureInputSize, scalarOutput, scalarOutputCount, structureOutput, structureOutputSize)
    }
    ```
  - Sustituir por:
    ```swift
    /// Single funnel for every AMD kext call.
    ///
    /// S10 IOK-01: the call now happens *while holding the handle lock*, which
    /// fixes two defects at once:
    ///
    ///  1. Use-after-close. The handle used to be copied out under the lock and
    ///     then used outside it, so a concurrent watchdog reconnect/teardown
    ///     (ConnectBox.install / closeIfOpen, both of which IOServiceClose after
    ///     releasing the lock) could close the port mid-flight. Mach port names
    ///     are recycled within a task, so the in-flight selector could in
    ///     principle land on an unrelated user client.
    ///
    ///  2. No serialization. There was no IOKit queue anywhere; the MainActor,
    ///     SystemMonitor's utility queue, the 5 s watchdog, AutoEppService,
    ///     C6ResidencyService and two detached fan readers all called in
    ///     concurrently. The kext's externalMethod is command-gate serialized on
    ///     its side, but userspace was free to pile up, and shared out-params
    ///     (scalarOutputCount, structureOutputSize) were unprotected.
    ///
    /// Holding one lock for the whole call makes this a serial channel, which is
    /// exactly the semantics the kext already assumes. The calls are short
    /// register/SMN reads; the previous behaviour of blocking the *main thread*
    /// on them is a separate defect handled by CON-01.
    nonisolated func safeIOConnectCallMethod(
        _ selector: UInt32,
        _ scalarInput: UnsafePointer<UInt64>!,
        _ scalarInputCount: UInt32,
        _ structureInput: UnsafeRawPointer!,
        _ structureInputSize: Int,
        _ scalarOutput: UnsafeMutablePointer<UInt64>!,
        _ scalarOutputCount: UnsafeMutablePointer<UInt32>!,
        _ structureOutput: UnsafeMutableRawPointer!,
        _ structureOutputSize: UnsafeMutablePointer<Int>!
    ) -> kern_return_t {
        return connectBox.withHandle { handle in
            if handle == 0 { return kIOReturnNoDevice }
            let kr = IOConnectCallMethod(handle, selector, scalarInput, scalarInputCount, structureInput, structureInputSize, scalarOutput, scalarOutputCount, structureOutput, structureOutputSize)
            // S10 IOK-03: track consecutive transport-level failures so a
            // stale-but-non-zero handle can be recovered by the watchdog.
            if kr == KERN_SUCCESS {
                connectBox.noteSuccess()
            } else if kr == kIOReturnNoDevice || kr == kIOReturnNotResponding
                        || kr == kIOReturnNotAttached || kr == kIOReturnBadArgument {
                // kIOReturnBadArgument is intentionally NOT counted: it is the
                // kext's normal answer to a size/privilege mismatch and says
                // nothing about port health.
                if kr != kIOReturnBadArgument { connectBox.noteFailure() }
            }
            return kr
        }
    }
    ```
  - Acción: REPLACE (segundo bloque: `ConnectBox` gana el método serializado y los contadores)
  - Buscar bloque:
    ```swift
    final class ConnectBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _handle: io_connect_t = 0
        var handle: io_connect_t {
            lock.lock(); defer { lock.unlock() }; return _handle
        }
        /// Atomic swap: closes the previous handle if any, installs the new one.
        func install(_ new: io_connect_t) {
            lock.lock()
            let old = _handle
            _handle = new
            lock.unlock()
            if old != 0 { IOServiceClose(old) }  // defensive; normally 0 here
        }
        /// Atomic close-and-zero; returns whether a handle was open.
        @discardableResult
        func closeIfOpen() -> Bool {
            lock.lock()
            let was = _handle != 0
            let old = _handle
            _handle = 0
            lock.unlock()
            if old != 0 { IOServiceClose(old) }
            return was
        }
    }
    ```
  - Sustituir por:
    ```swift
    final class ConnectBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _handle: io_connect_t = 0
        /// S10 IOK-03: consecutive transport failures on a non-zero handle.
        private var _consecutiveFailures: Int = 0

        var handle: io_connect_t {
            lock.lock(); defer { lock.unlock() }; return _handle
        }

        /// S10 IOK-01: runs `body` with the handle while holding the lock, so the
        /// handle cannot be closed underneath an in-flight IOConnectCallMethod.
        /// This also makes the kext channel serial, matching what the kext's
        /// command gate already assumes.
        func withHandle<T>(_ body: (io_connect_t) -> T) -> T {
            lock.lock(); defer { lock.unlock() }
            return body(_handle)
        }

        /// Atomic swap: closes the previous handle if any, installs the new one.
        /// The close happens under the lock so it cannot race an in-flight call.
        func install(_ new: io_connect_t) {
            lock.lock()
            let old = _handle
            _handle = new
            _consecutiveFailures = 0
            if old != 0 { IOServiceClose(old) }
            lock.unlock()
        }

        /// Atomic close-and-zero; returns whether a handle was open.
        @discardableResult
        func closeIfOpen() -> Bool {
            lock.lock()
            let was = _handle != 0
            let old = _handle
            _handle = 0
            _consecutiveFailures = 0
            if old != 0 { IOServiceClose(old) }
            lock.unlock()
            return was
        }

        // MARK: - S10 IOK-03 health tracking
        // Called from inside withHandle (lock already held) — must not re-lock.
        fileprivate func noteSuccess() { _consecutiveFailures = 0 }
        fileprivate func noteFailure() {
            if _consecutiveFailures < Int.max { _consecutiveFailures += 1 }
        }
        /// True when the handle looks alive-but-dead: non-zero yet failing every
        /// call. The watchdog uses this to force a reopen.
        var isLikelyStale: Bool {
            lock.lock(); defer { lock.unlock() }
            return _handle != 0 && _consecutiveFailures >= 5
        }
    }
    ```
  - Acción: DELETE (lock muerto y su comentario obsoleto, `ProcessorModel.swift:17`)
  - Buscar bloque:
    ```swift
    nonisolated let iokitLock = NSLock()
    ```
  - Sustituir por:
    ```swift
    // S10 IOK-01: `iokitLock` removed. It was declared for exactly this purpose
    // but never locked anywhere in the codebase (only two stale comments
    // referenced it). Serialization now lives in ConnectBox.withHandle.
    ```
- **Consideraciones de Seguridad & Edge Cases**:
  - `noteSuccess`/`noteFailure` se llaman **desde dentro** de `withHandle`, con el lock ya tomado: por eso son `fileprivate` y no vuelven a bloquear. `NSLock` **no es reentrante**; volver a bloquear sería un deadlock inmediato. Esta es la restricción crítica de este parche — no mover esas llamadas fuera.
  - Serializar significa que un llamante lento bloquea a los demás. Las llamadas son lecturas cortas de registro/SMN (µs). Combinar obligatoriamente con `CON-01`, que saca las escrituras del hilo principal; si no, se serializa *sobre* el main thread y se nota.
  - `kIOReturnBadArgument` se excluye del contador a propósito: es la respuesta normal del kext ante un desajuste de tamaño o falta de privilegios y no dice nada sobre la salud del puerto. Contarlo provocaría reconexiones espurias en cada arranque sin privilegios.
  - Si el kext no está cargado, `_handle == 0` y `withHandle` devuelve `kIOReturnNoDevice` sin tocar IOKit — mismo comportamiento que antes.
- **Comando de Verificación**:
  ```sh
  ./build.sh 2>&1 | grep -E "error|warning" ; ./build/RyzenStatus --selftest
  # Debe imprimir "SELFTEST OK". Confirma que el lock muerto ya no existe:
  grep -rn "iokitLock" Sources/   # solo debe quedar el comentario S10
  ```

---

### [IOK-02] El selector 8 aborta toda la inicialización, dejando `isKextAvailable = true` sin ningún dato cargado

- **Severidad**: Alta
- **Archivos Afectados**: `Sources/RyzenStatus/Services/AMD/ProcessorModel.swift:529-541`
- **Diagnóstico & Causa Raíz**: El kext exige `maxLen >= sizeof(xStringify(MODULE_VERSION))` (`AMDRyzenCPUPMUserClient.cpp:421`), es decir la longitud del literal en tiempo de compilación **incluyendo el NUL**. Swift suministra solo 16 bytes (`maxStrLength = 16`). Una versión de kext de ≥16 caracteres (p. ej. `"1.31.0-beta.12"` con sufijo, o cualquier build con metadata) hace que el kext devuelva `kIOReturnBadArgument`, y entonces `_finishInit()` **aborta todo lo que viene después** con un `return` seco: `loadCPUID`, `loadMetric`, `loadPStateDef` nunca corren. Mientras tanto `isKextAvailable` ya se puso a `true` en `:528`. Resultado: la UI cree que el kext está disponible y muestra ceros en todo, sin ningún error accionable. Un dato cosmético (la cadena de versión) es una **compuerta dura sobre toda la telemetría**.
- **Instrucción de Reemplazo para Gemini 3.8 Flash**:
  - Acción: REPLACE
  - Buscar bloque:
    ```swift
        guard versionResult == KERN_SUCCESS, outputStrCount > 0 else {
            NSLog("ProcessorModel: failed to read kext version, kr=0x%08x", versionResult)
            identityCache.set(version: "")
            return
        }
    ```
  - Sustituir por:
    ```swift
        // S10 IOK-02: the version string is diagnostic metadata, NOT a
        // capability gate. This used to `return`, which skipped loadCPUID(),
        // loadMetric() and loadPStateDef() entirely while isKextAvailable had
        // already been set to true — so the UI reported a healthy kext and
        // displayed zeroes everywhere, with no actionable error.
        //
        // The failure is also self-inflicted: the kext requires
        // maxLen >= sizeof(xStringify(MODULE_VERSION)) (including the NUL), and
        // this side only ever offered 16 bytes. Any kext version string of 16+
        // characters (a pre-release suffix, build metadata) bricked the whole
        // init path. The buffer is widened in the declaration above; here we
        // simply stop treating an unreadable version as fatal.
        if versionResult != KERN_SUCCESS || outputStrCount <= 0 {
            NSLog("ProcessorModel: kext version unreadable, kr=0x%08x — continuing init", versionResult)
            identityCache.set(version: "")
            // Deliberate fall-through: telemetry does not depend on this string.
        }
    ```
  - Acción: REPLACE (ampliar el buffer; `ProcessorModel.swift:529-531`)
  - Buscar bloque:
    ```swift
        let maxStrLength = 16
    ```
  - Sustituir por:
    ```swift
        // S10 IOK-02: 64 bytes comfortably covers any semver plus pre-release and
        // build metadata. The kext copies exactly `requiredSize` bytes (NUL
        // included) and rejects maxLen < requiredSize, so over-provisioning is
        // free and fails open instead of closed.
        let maxStrLength = 64
    ```
- **Consideraciones de Seguridad & Edge Cases**: La construcción de la `String` en `:541` usa `String(cString: Array(outputStr[0...min(outputStrCount - 1, outputStr.count - 1)]))` y es segura solo porque el caso 8 del kext copia `requiredSize` bytes (que incluye el NUL). Con el buffer ampliado sigue siendo cierto. **Importante**: en el camino de fallo, `outputStrCount` puede ser 0, así que hay que verificar que la construcción de la `String` esté dentro de la rama de éxito o protegida por `outputStrCount > 0`; tras este parche el flujo continúa, así que Gemini debe confirmar que la línea que construye la string está guardada. Verificación obligatoria:
  ```sh
  sed -n '525,555p' Sources/RyzenStatus/Services/AMD/ProcessorModel.swift
  ```
  Si `String(cString:)` queda fuera de un `if outputStrCount > 0`, envolverla. Un `outputStrCount == 0` con `Array(outputStr[0...(-1)])` sería un **crash por rango inválido**.
- **Comando de Verificación**:
  ```sh
  ./build.sh 2>&1 | grep -E "error|warning" ; ./build/RyzenStatus --selftest ; ./build/RyzenStatus --sensors | head -20
  # --sensors debe mostrar lecturas reales aunque la versión del kext salga vacía.
  ```

---

### [IOK-03] Un handle obsoleto pero no-cero jamás se recupera; no hay reconexión tras sleep

- **Severidad**: Alta
- **Archivos Afectados**: `Sources/RyzenStatus/Services/AMD/ProcessorModel.swift:475-490`
- **Diagnóstico & Causa Raíz**: La rama de reconexión del watchdog está condicionada a `if !self.isConnected, self.attemptReconnect()` (`:481`), e `isConnected` es simplemente `connectBox.handle != 0`. Si el user client queda inutilizable tras un ciclo de suspensión pero el servicio IOKit **sigue haciendo match** (caso habitual: el kext vive, el user client murió), entonces `handle != 0` permanece cierto, `isConnected` sigue `true`, `attemptReconnect()` **nunca se llama**, y todos los selectores devuelven error indefinidamente. No existe heurística de "N fallos consecutivos ⇒ reabrir", y no hay ningún observador de `didWake` que revalide la conexión (el único `didWake` relevante, en `FanCurveController:110-119`, re-sube curvas pero no toca el handle). La app queda muerta hasta un reinicio manual.
- **Instrucción de Reemplazo para Gemini 3.8 Flash**:
  - Acción: REPLACE
  - Buscar bloque:
    ```swift
                } else {
                    IOObjectRelease(serviceObject)
    ```
  - Sustituir por:
    ```swift
                } else {
                    IOObjectRelease(serviceObject)
                    // S10 IOK-03: recover an "alive but dead" handle. The old
                    // gate was `if !isConnected`, i.e. handle == 0. When the
                    // user client died across sleep while the service still
                    // matched, the handle stayed non-zero, isConnected stayed
                    // true, attemptReconnect() was never reached, and every
                    // selector failed forever with no recovery path.
                    // ConnectBox now counts consecutive transport failures
                    // (see IOK-01) and reports isLikelyStale after 5 of them.
                    if self.connectBox.isLikelyStale {
                        NSLog("ProcessorModel: handle appears stale (5+ consecutive failures); forcing reopen")
                        self.connectBox.closeIfOpen()
                        if self.attemptReconnect() {
                            NSLog("ProcessorModel: stale-handle reconnect succeeded")
                        }
                    }
    ```
- **Consideraciones de Seguridad & Edge Cases**:
  - Depende de `IOK-01` (los contadores `noteFailure`/`isLikelyStale` viven en `ConnectBox`). **Aplicar `IOK-01` primero.**
  - El umbral de 5 con el watchdog a 5 s implica que un fallo transitorio no dispara reconexión, y una muerte real se recupera en ≤5 s tras la quinta llamada fallida. Como `SystemMonitor` sondea cada 2 s, en la práctica son unos ~10-15 s de recuperación.
  - `closeIfOpen()` antes de `attemptReconnect()` es necesario: `install()` cerraría el viejo de todos modos, pero cerrarlo explícitamente hace que un `attemptReconnect()` fallido deje el estado en "desconectado" honesto en lugar de mantener un handle zombi.
  - Sin privilegios, muchos selectores devuelven `kIOReturnNotPrivileged`, que **no** se cuenta como fallo de transporte (ver IOK-01) — no habrá bucles de reconexión en máquinas sin `-amdpnopchk`.
- **Comando de Verificación**:
  ```sh
  ./build.sh 2>&1 | grep -E "error|warning" ; ./build/RyzenStatus --selftest
  # Probe en hardware: suspender/despertar y observar el log.
  # log stream --predicate 'process == "RyzenStatus"' | grep -i "stale\|reconnect"
  ```

---

### [IOK-04] El fallo de privilegio del selector 103 se descarta en silencio: las curvas GPU se congelan sin aviso

- **Severidad**: Media
- **Archivos Afectados**: `Sources/RyzenStatus/Services/AMD/FanCurveController.swift:243-256`
- **Diagnóstico & Causa Raíz**: `pushGPUTempIfNeeded()` es el **único** llamante del selector 103 y descarta el retorno con `_ = ProcessorModel.shared.setKextGPUTemp(...)`. El selector está protegido por `hasPrivilege(103)` (root o boot-arg `-amdpnopchk`). Si falla con `kIOReturnNotPrivileged`, la app no se enterará: el kext se queda con su `gpuTempC` obsoleto y las curvas con fuente GPU siguen evaluando contra un valor congelado — con `KRN-02` aplicado eso ahora degrada a la fuente CPU o al failsafe, lo cual es correcto, pero **el usuario no ve nada**. Los selectores 101/102 sí exponen `privilegeError` (`:228-230`); el 103 es la excepción incoherente. Además la condición `tempToSend > 0 && tempToSend <= 120.0` descarta silenciosamente el valor sin registrar el motivo.
- **Instrucción de Reemplazo para Gemini 3.8 Flash**:
  - Acción: REPLACE
  - Buscar bloque:
    ```swift
        let kextGPUTemp = ProcessorModel.shared.lastKextGPUTemperature
        let monitorGPUTemp = SystemMonitor.shared.snapshot.gpuTemperature ?? 0.0
        let tempToSend = kextGPUTemp > 0 ? kextGPUTemp : monitorGPUTemp
        if tempToSend > 0 && tempToSend <= 120.0 {
            _ = ProcessorModel.shared.setKextGPUTemp(Float(tempToSend))
        }
    }
    ```
  - Sustituir por:
    ```swift
        let kextGPUTemp = ProcessorModel.shared.lastKextGPUTemperature
        let monitorGPUTemp = SystemMonitor.shared.snapshot.gpuTemperature ?? 0.0
        let tempToSend = kextGPUTemp > 0 ? kextGPUTemp : monitorGPUTemp

        guard tempToSend > 0, tempToSend <= 120.0, tempToSend.isFinite else {
            // S10 IOK-04: no trustworthy GPU reading. Say so once instead of
            // failing silently — the kext keeps its previous gpuTempC, and a
            // GPU-sourced curve would otherwise evaluate against a frozen value
            // with no user-visible explanation.
            if gpuBridgeWarned == false {
                gpuBridgeWarned = true
                os_log("GPU-sourced fan curve active but no valid GPU temperature available (kext=%{public}.1f monitor=%{public}.1f)",
                       log: logger, type: .error, kextGPUTemp, monitorGPUTemp)
            }
            return
        }

        // S10 IOK-04: selector 103 is privilege-gated (root or -amdpnopchk).
        // It used to be called with `_ =`, so a kIOReturnNotPrivileged silently
        // froze every GPU-sourced curve. Selectors 101/102 already surface
        // privilegeError; 103 was the inconsistent one.
        let kr = ProcessorModel.shared.setKextGPUTemp(Float(tempToSend))
        if kr == KERN_SUCCESS {
            gpuBridgeWarned = false
            if privilegeError != nil, kextMissing == false {
                // A previously reported privilege failure has cleared.
                privilegeError = nil
            }
        } else if kr == kIOReturnNotPrivileged {
            if gpuBridgeWarned == false {
                gpuBridgeWarned = true
                privilegeError = FanControlStrings.privilegeRequired
                os_log("selector 103 (GPU temp bridge) denied: root or -amdpnopchk required; GPU-sourced curves will fall back to CPU temperature",
                       log: logger, type: .error)
            }
        } else if gpuBridgeWarned == false {
            gpuBridgeWarned = true
            os_log("selector 103 (GPU temp bridge) failed kr=0x%08x", log: logger, type: .error, kr)
        }
    }
    ```
  - Acción: INSERT (nueva propiedad de estado, junto a las demás banderas privadas en `FanCurveController.swift:31-37`)
  - **⚠ Anclar por archivo:** esta línea existe también en `Sources/RyzenStatus/Services/AMD/C6ResidencyService.swift`. Aplicar **solo** en `Sources/RyzenStatus/Services/AMD/FanCurveController.swift`.
  - Buscar bloque:
    ```swift
    private var wakeObserver: Any?
    ```
  - Sustituir por:
    ```swift
        private var wakeObserver: Any?
        /// S10 IOK-04: one-shot latch so the GPU-bridge diagnostic is logged once
        /// per failure episode instead of every 1.5 s poll tick.
        private var gpuBridgeWarned = false
    ```
- **Consideraciones de Seguridad & Edge Cases**:
  - `FanControlStrings.privilegeRequired` debe existir. Verificar con `grep -n "privilegeRequired" Sources/RyzenStatus/Core/FanControlStrings.swift`. Si no existe, **hay que añadir la clave en las 12 localizaciones** (`Sources/RyzenStatus/Core/Localizations/Strings+*.swift`) porque `CONTRIBUTING.md:107-108` dice que la build no compila si falta un idioma. Alternativa sin tocar localizaciones: reutilizar el mensaje que ya emplean los selectores 101/102 en `:190` / `:228-230` — **preferible**, y es la opción recomendada.
  - El latch `gpuBridgeWarned` evita inundar el log a 1.5 s. Se limpia al primer éxito.
  - No cambia el comportamiento térmico: con `KRN-02` aplicado, una GPU sin lectura ya degrada a CPU o a failsafe en el kernel.
- **Comando de Verificación**:
  ```sh
  grep -n "privilegeRequired" Sources/RyzenStatus/Core/FanControlStrings.swift
  sed -n '185,235p' Sources/RyzenStatus/Services/AMD/FanCurveController.swift   # reutilizar el mismo string
  ./build.sh 2>&1 | grep -E "error|warning" ; ./build/RyzenStatus --selftest
  ```

---

### [IOK-05] Ausencia de `IOExternalMethodDispatch`: toda validación de tamaño y conteo es artesanal

- **Severidad**: Media (arquitectónica — deuda estructural, no bug explotable hoy)
- **Archivos Afectados**: `SMCAMDProcessor_Source/AMDRyzenCPUPowerManagement/AMDRyzenCPUPMUserClient.cpp:123-150` (+ los 70 `case` del switch)
- **Diagnóstico & Causa Raíz**: `externalMethod()` recibe el parámetro `IOExternalMethodDispatch *dispatch` y **lo ignora por completo**, despachando con un `switch (selector)` escrito a mano en `:150`. Consecuencia: `checkScalarInputCount`, `checkStructureInputSize`, `checkScalarOutputCount` y `checkStructureOutputSize` — las validaciones que el framework aplica *antes* de entrar a tu código — **no se usan en ninguna parte del kext**. Los parámetros `dispatch`, `target` y `reference` están muertos.

  **La auditoría confirma que los ~70 casos existentes sí validan a mano y correctamente** (`arguments->scalarInputCount != N`, `maxLen < requiredSize`, y en el 101 una comparación de tamaño **exacta**). No hay hoy ninguna ruta de corrupción de memoria ni de kernel panic por tamaños. El riesgo es de **mantenimiento**: cada nuevo selector depende de que su autor recuerde escribir el `if`, y la revisión no tiene una tabla única donde verificarlo. Con 70 casos y una cadencia de "wave S9a/S9b/S9c" añadiendo selectores, es cuestión de tiempo.
- **Instrucción de Reemplazo para Gemini 3.8 Flash**:
  - Acción: INSERT (verja de validación centralizada, inmediatamente antes del `switch`)
  - Buscar bloque (**anclaje de una sola línea, única en el archivo — línea 148**; entre esta línea y `switch (selector) {` hay una línea de solo espacios, así que un anclaje multilínea sería frágil):
    ```cpp
    provider->registerRequest();
    ```
  - Sustituir por:
    ```cpp
        provider->registerRequest();

        //
        // S10 IOK-05: centralized pre-switch validation gate.
        //
        // This driver overrides externalMethod() directly and ignores the
        // `dispatch` argument, so IOUserClient's own checkScalarInputCount /
        // checkStructureInputSize / checkScalarOutputCount /
        // checkStructureOutputSize are never applied. Every one of the ~70 cases
        // below validates its own sizes by hand, and they are all currently
        // correct — but there is no single place a reviewer can check, and each
        // new selector re-litigates the question.
        //
        // This gate enforces the invariants that hold for EVERY selector, so an
        // omission in a future case cannot reach a memcpy:
        //   - a struct-input selector must actually carry a struct pointer
        //   - a struct-output selector must carry an output buffer
        //   - scalar counts must be within the IOKit ABI maximum (16)
        //
        // Per-selector exact sizes stay in their cases (they are selector
        // specific), but nothing can now dereference a null structureInput.
        //
        if (arguments->structureInputSize > 0 && !arguments->structureInput) {
            IOLog("AMDRyzenCPUPMUserClient: selector %u declared %u input bytes with a null pointer\n",
                  selector, (unsigned)arguments->structureInputSize);
            return kIOReturnBadArgument;
        }
        if (arguments->structureOutputSize > 0 && !arguments->structureOutput) {
            IOLog("AMDRyzenCPUPMUserClient: selector %u declared %u output bytes with a null pointer\n",
                  selector, (unsigned)arguments->structureOutputSize);
            return kIOReturnBadArgument;
        }
        if (arguments->scalarInputCount > kIOUCVariableStructureSize
            || arguments->scalarOutputCount > kIOUCVariableStructureSize) {
            // Defensive: IOKit caps these at 16, but the switch below indexes
            // scalarInput[0..1] after only checking the count for equality.
            return kIOReturnBadArgument;
        }
    ```
    > **Nota para Gemini:** el bloque sustituido **no** debe re-emitir `switch (selector) {`. El anclaje es solo la línea `provider->registerRequest();`; la línea del `switch` que le sigue en el archivo se conserva intacta. Re-emitirla duplicaría el `switch` y la compilación fallaría.
- **Consideraciones de Seguridad & Edge Cases**:
  - Este parche es **puramente aditivo y conservador**: solo rechaza combinaciones que ya eran inválidas. Ningún selector legítimo declara bytes con puntero nulo.
  - Verificar que `kIOUCVariableStructureSize` esté disponible en este contexto de headers; si no, sustituir el literal por `16`. Comprobación: `grep -rn "kIOUCVariableStructureSize" SMCAMDProcessor_Source/`.
  - La refactorización completa a una tabla `IOExternalMethodDispatch sMethods[]` con enrutado por `IOUserClient::externalMethod(selector, arguments, &sMethods[i], this, nullptr)` es el destino correcto, pero toca 70 casos y **no es un cambio quirúrgico** — debe ser su propio PR con pruebas por selector. Este ticket entrega el 80 % del beneficio de seguridad con un bloque de 25 líneas.
- **Comando de Verificación**:
  ```sh
  grep -rn "kIOUCVariableStructureSize" SMCAMDProcessor_Source/ | head -3
  cd SMCAMDProcessor_Source && xcodebuild -project AMDRyzenCPUPowerManagement.xcodeproj \
    -target AMDRyzenCPUPowerManagement -configuration Release build 2>&1 | grep -E "error|BUILD"
  ```

## 2.2 Tolerancia a fallos sin kext / en Intel / en Apple Silicon: **correcta**

Ruta verificada: `init()` deja `conn = 0` si no hay match → `isConnected == false` → `safeIOConnectCallMethod` corta con `kIOReturnNoDevice` sin tocar IOKit. `getTelemetry()` devuelve `nil`; los helpers `kernelGet*` devuelven `[]`; `getFans()` devuelve lista vacía. `FanCurveController` fija `kextMissing = true` (`:451`, `:172`) y la UI lo muestra. **No hay force-unwrap de `nil` en ninguna ruta de degradación** y `CPUSensorPacket.parse` revalida `bytes.count >= byteSize` antes de leer offsets. En Apple Silicon el servicio jamás hace match, así que es el mismo camino que "kext no cargado". Sin acción requerida.


---

# MÓDULO 3 — Telemetría SuperIO y tacómetros

## 3.0 Estado de la conversión PWM: **correcta, sin bug**

Contradiciendo la sospecha habitual, las conversiones raw↔porcentaje están bien:
- raw→% (display): `(Double(throttlePWM) / 255.0) * 100.0` — `FanCurveModels.swift:57-59`, `:84-86`. ✅
- %→raw (subida de LUT): `Int((pt.pwm * 2.55).rounded())` con clamp `[0,255]` — `FanCurveModels.swift:143-153`. ✅ `0 %→0`, `1 %→3`, `50 %→128`, `100 %→255`.
- **No hay confusión `/255` vs `/2.55`, y `.rounded()` precede al cast `Int()` en ambas rutas** — no hay truncamiento.
- El kernel trabaja exclusivamente en 0-255 (`lut[256]` es `uint8_t`); no hay conversión de porcentaje en el kext.

Residual menor: la UI almacena porcentaje entero, así que solo ~101 de los 256 pasos de hardware son alcanzables. No es un defecto de corrección.

`rampRate` usa el mismo factor 2.55 aunque el campo se documente como "%/s" → "PWM/s" (`FanCurveModels.swift:198-210`); el kext lo re-clampea a `1…100` y lo guarda en `uint8_t`, así que es consistente — la etiqueta acierta por construcción, no por diseño. Sin acción.

## 3.1 Detección de chip y unlock: correcta, con una nota

Orden de sondeo (`AMDRyzenCPUPowerManagement.cpp:2230-2236`): NCT668X → NCT67XX → IT86XXE, todo bajo `superIOLock`. Puertos LPC 0x4E/0x2E con sus secuencias de entrada correctas (`0x87 0x87` para Nuvoton, `0x87 0x01 0x55 0xAA/0x55` para ITE), BAR verificado tras `IODelay(10)`, y el unlock de I/O-space gateado por `allowUnlock`.

**Nota (baja):** `ISSuperIOIT86XXEFamily::getDevice` es la única familia que **no recibe `allowUnlock`**, y su constructor muta hardware antes de cualquier chequeo de privilegio (`ISSuperIOIT86XXEFamily.cpp:28-29`): `writeByte(0x0c, readByte(0x0c) | 0x3f)` para habilitar tacómetros de 16 bits en los 6 ventiladores. Es benigno (habilitar modo 16-bit es lo que quiere el driver) pero rompe la simetría de la política de unlock. También hay un guard muerto en `:51-54` (`if (regport != 0x2E && regport != 0x4E) break;` nunca puede dispararse dado `kREGISTER_PORTS`).

---

### [SIO-01] Tacómetro sin validar: `0xFFFF` se publica como 65535 RPM y envenena `fanPeakRPMs` de forma permanente

- **Severidad**: Alta
- **Archivos Afectados**: `SMCAMDProcessor_Source/AMDRyzenCPUPowerManagement/SuperIO/ISSuperIONCT67XXFamily.cpp:189-202` (idéntico en `ISSuperIONCT668X.cpp:152-164`)
- **Diagnóstico & Causa Raíz**: Las dos familias Nuvoton no validan **nada**. Una lectura desgarrada o de cabecera sin conectar devuelve `0xFFFF`, que se publica como **65535 RPM** y —lo grave— se latchea en `fanPeakRPMs[i]`, que es una marca de agua que **solo sube y nunca decae** (`ISSuperIONCT67XXFamily.hpp:68`). Ese pico envenenado es el denominador de la estimación de PWM cuando el registro de duty lee 0 (`:206-210`):
  ```cpp
  uint32_t est = (uint32_t)((uint64_t)fanRPMs[i] * 255 / fanPeakRPMs[i]);
  ```
  Con el denominador fijado en 65535, **toda estimación posterior es ≈0 %** para el resto de la sesión. Y ese valor fabricado no es cosmético: viaja por el selector 94 hasta `FanState.throttlePWM`, y `refreshFansInitial()` lo copia a `manualPWM` para ventiladores en modo `.manual` (`manualPWM: (mode == .manual) ? snap.throttle : nil`) — es decir, **un valor inventado se convierte en el set-point manual autoritativo de la app**. La familia ITE sí filtra (`value > 0x3f` y `< 0xffff`), así que el arreglo es alinear Nuvoton con ella.
- **Instrucción de Reemplazo para Gemini 3.8 Flash**:
  - Acción: REPLACE
  - Buscar bloque:
    ```cpp
void ISSuperIONCT67XXFamily::updateFanRPMS(){
   
    for (int i = 0; i < activeFansOnSystem; i++) {
        int v = (int)readWord(kFAN_RPM_REGS[i]);
        fanRPMs[i] = v;
        
        // Track peak RPM for PWM estimation in Auto mode
        if ((uint32_t)v > fanPeakRPMs[i]) {
            fanPeakRPMs[i] = (uint16_t)v;
        }
        //IOLog("fan %d: %d\n", i, (int)v);
    }
}
    ```
  - Sustituir por:
    ```cpp
    void ISSuperIONCT67XXFamily::updateFanRPMS(){

        //
        // S10 SIO-01: validate every tachometer word before publishing it.
        //
        // readWord() issues two independent bank/index sequences, so the high and
        // low bytes can tear across a tach update. An unpopulated header, a torn
        // read or a chip in reset all yield 0xFFFF, which used to be published
        // verbatim as 65535 RPM AND latched into fanPeakRPMs — a high-water mark
        // that only ever rises. Since fanPeakRPMs is the denominator of the
        // Auto-mode PWM estimator below, one bad read permanently pinned every
        // later estimate to ~0 %, and that fabricated duty propagates through
        // selector 94 into the app's manual set-point.
        //
        // kMAX_PLAUSIBLE_RPM matches the ITE family's existing sanity ceiling.
        //
        static const int kMAX_PLAUSIBLE_RPM = 10500;

        for (int i = 0; i < activeFansOnSystem; i++) {
            int v = (int)readWord(kFAN_RPM_REGS[i]);

            if (v == 0xFFFF || v < 0 || v > kMAX_PLAUSIBLE_RPM) {
                // Implausible: hold the previous good reading rather than
                // publishing garbage, and mark the sample untrusted so the
                // estimator below refuses to use it.
                fanRPMValid[i] = false;
                continue;
            }

            fanRPMs[i] = v;
            fanRPMValid[i] = true;

            // Track peak RPM for PWM estimation in Auto mode. Only trusted
            // samples may raise the high-water mark.
            if ((uint32_t)v > fanPeakRPMs[i]) {
                fanPeakRPMs[i] = (uint16_t)v;
            }
        }
    }
    ```
  - Acción: REPLACE (blindar el estimador para que no use muestras no confiables)
  - Buscar bloque:
    ```cpp
        // Fallback: if the register reports 0 but fan is spinning,
        // estimate throttle from RPM/peakRPM ratio.
        if (fanThrottles[i] == 0 && fanRPMs[i] > 100 && fanPeakRPMs[i] > 200) {
            uint32_t est = (uint32_t)((uint64_t)fanRPMs[i] * 255 / fanPeakRPMs[i]);
    ```
  - Sustituir por:
    ```cpp
            // Fallback: if the register reports 0 but fan is spinning,
            // estimate throttle from RPM/peakRPM ratio.
            // S10 SIO-01: only estimate from a validated tach sample.
            if (fanThrottles[i] == 0 && fanRPMValid[i] && fanRPMs[i] > 100 && fanPeakRPMs[i] > 200) {
                uint32_t est = (uint32_t)((uint64_t)fanRPMs[i] * 255 / fanPeakRPMs[i]);
    ```
  - Acción: INSERT (declarar el array de validez en el header)
  - Archivo: `SMCAMDProcessor_Source/AMDRyzenCPUPowerManagement/SuperIO/ISSuperIONCT67XXFamily.hpp` (junto a `fanPeakRPMs`, ~línea 68)
  - **⚠ Anclar por archivo:** `uint16_t fanPeakRPMs[` aparece en **tres** headers (`ISSuperIONCT67XXFamily.hpp`, `ISSuperIONCT668X.hpp`, `ISSuperIOIT86XXEFamily.hpp`). Aplicar en el de NCT67XX y, como indica el apartado siguiente, replicar en el de NCT668X. **No** tocar el de IT86XXE (esa familia ya valida sus tacómetros).
  - Buscar bloque:
    ```cpp
    uint16_t fanPeakRPMs[
    ```
  - Sustituir por (conservar la dimensión exacta que ya tenga el array; añadir la línea nueva con la MISMA dimensión):
    ```cpp
        // S10 SIO-01: per-fan trust flag for the last tachometer read. False means
        // the last word was implausible (0xFFFF / torn / out of range) and
        // fanRPMs[i] holds a stale-but-good value instead.
        bool fanRPMValid[/* same dimension as fanPeakRPMs */] {};
        uint16_t fanPeakRPMs[
    ```
- **Consideraciones de Seguridad & Edge Cases**:
  - Gemini debe leer la dimensión real de `fanPeakRPMs` (probablemente `kMAX_FANS` o un literal) y usar **exactamente la misma** para `fanRPMValid`. No inventar la constante. Comando: `grep -n "fanPeakRPMs\|fanRPMs\[" ISSuperIONCT67XXFamily.hpp`.
  - **Aplicar el mismo parche a `ISSuperIONCT668X.cpp:152-164` + `.hpp`** — es código idéntico con registros distintos (`FAN_RPM_REGS(x) = 0x140 + x*2`).
  - `10500 RPM` es un techo generoso: cubre ventiladores de 40 mm de alto régimen. Los servidores con ventiladores de >10 500 RPM son fuera de alcance para un Hackintosh de escritorio; si el proyecto quiere soportarlos, subir a 30000 y mantener solo el rechazo de `0xFFFF`.
  - Un ventilador legítimamente detenido (0 RPM) **sigue pasando** la validación (`0` no es `0xFFFF` ni `> 10500`), así que el modo 0-RPM no se rompe. Distinguir "detenido" de "sensor muerto" es `SIO-03`.
- **Comando de Verificación**:
  ```sh
  grep -n "fanPeakRPMs\|fanRPMs\[" SMCAMDProcessor_Source/AMDRyzenCPUPowerManagement/SuperIO/ISSuperIONCT67XXFamily.hpp
  cd SMCAMDProcessor_Source && xcodebuild -project AMDRyzenCPUPowerManagement.xcodeproj \
    -target AMDRyzenCPUPowerManagement -configuration Release build 2>&1 | grep -E "error|BUILD"
  ```

---

### [SIO-02] `readWord()` no atómico: desgarro de bytes alto/bajo en cada lectura de 16 bits

- **Severidad**: Media
- **Archivos Afectados**: `SuperIO/ISSuperIONCT67XXFamily.cpp:145-160`, `ISSuperIONCT668X.cpp:111-127`
- **Diagnóstico & Causa Raíz**: Cada `readWord()` son **dos secuencias index/bank independientes**:
  ```cpp
  uint16_t ISSuperIONCT67XXFamily::readWord(uint16_t addr){
      return (readByte(addr) << 8) | readByte(addr + 1);  // 2 bank selects distintos
  }
  ```
  Entre las dos lecturas el chip puede actualizar el contador del tacómetro, produciendo un valor compuesto de mitades de dos muestras. Es la fuente física de los valores absurdos que `SIO-01` filtra. Además, `superIOLock` serializa contra otros llamantes del kext pero **no contra el BIOS/SMM**, que puede acceder al mismo espacio LPC.
- **Instrucción de Reemplazo para Gemini 3.8 Flash**:
  - Acción: REPLACE
  - Buscar bloque:
    ```cpp
uint16_t ISSuperIONCT67XXFamily::readWord(uint16_t addr){
    return (readByte(addr) << 8) | readByte(addr + 1);
}
    ```
  - Sustituir por:
    ```cpp
    uint16_t ISSuperIONCT67XXFamily::readWord(uint16_t addr){
        //
        // S10 SIO-02: tear-resistant 16-bit read.
        //
        // Each readByte() is its own bank-select + index + data sequence, so the
        // chip can update the tachometer counter between the high and low byte
        // and hand back a value stitched from two different samples. That is the
        // physical origin of the implausible words SIO-01 filters.
        //
        // Re-read the high byte after the low byte: if it changed, the counter
        // rolled between our accesses and the pair is inconsistent, so retry.
        // Two attempts are enough in practice (the counter updates at ~1 Hz
        // while this sequence takes microseconds); after that, return the last
        // consistent pair and let the caller's validation decide.
        //
        for (int attempt = 0; attempt < 3; attempt++) {
            uint8_t hi  = readByte(addr);
            uint8_t lo  = readByte(addr + 1);
            uint8_t hi2 = readByte(addr);
            if (hi == hi2) {
                return (uint16_t)((hi << 8) | lo);
            }
        }
        // Persistent disagreement: report the sentinel so the caller's
        // plausibility check (SIO-01) rejects this sample.
        return 0xFFFF;
    }
    ```
- **Consideraciones de Seguridad & Edge Cases**:
  - Triplica el número de accesos I/O port por lectura en el peor caso. Con 6 ventiladores a 500 ms el coste sigue siendo despreciable (los accesos LPC son ~1 µs), pero corre bajo `superIOLock` en el workloop: aceptable y ya era el patrón de coste existente.
  - Devolver `0xFFFF` como sentinel **requiere que `SIO-01` esté aplicado**; si no, se publicaría 65535 RPM. **Aplicar `SIO-01` primero o simultáneamente.** Dependencia estricta.
  - Aplicar el mismo cambio en `ISSuperIONCT668X.cpp:111-127`. La familia ITE lee dos registros separados (base + ext) en lugar de un par de bancos, así que **no aplica** allí.
- **Comando de Verificación**:
  ```sh
  cd SMCAMDProcessor_Source && xcodebuild -project AMDRyzenCPUPowerManagement.xcodeproj \
    -target AMDRyzenCPUPowerManagement -configuration Release build 2>&1 | grep -E "error|BUILD"
  # En hardware: comparar RPM contra el BIOS/otra utilidad durante 60 s.
  ```

---

### [SIO-03] 0 RPM indistinguible de sensor muerto; sin detección de estancamiento de rotor

- **Severidad**: Media (Alta en combinación con la ausencia de piso de PWM, ya corregida por KRN-02)
- **Archivos Afectados**: `SuperIO/ISSuperIOSMCFamily.hpp:27-28` (interfaz), `ISSuperIOIT86XXEFamily.cpp:192-213`, `Sources/RyzenStatus/Services/AMD/ProcessorModel.swift:1701`, `FanCurveModels.swift:26-31`
- **Diagnóstico & Causa Raíz**: Tres semánticas distintas colapsan al mismo `0`:
  1. ventilador legítimamente detenido (modo 0-RPM intencional),
  2. cabecera sin ventilador conectado,
  3. sensor/lectura fallida.

  No existe ningún flag `isPresent`/`isValid` en `ISSuperIOSMCFamily`, y `getRPMForFan()` devuelve `uint32_t` sin canal de error. En Swift, `min(fanRpms[i], 9999)` (`ProcessorModel.swift:1701`) **enmascara** la basura convirtiendo 65535 en un plausible 9999 en lugar de marcarla, y `FanState.rpm == 0` se renderiza como "0 RPM" sin estado "sin sensor". **Nada en todo el subsistema usa RPM como realimentación**: el lazo es estrictamente open-loop, así que un ventilador que no arranca a duty bajo nunca se detecta. `KRN-02` mitiga la causa (piso de PWM), pero la *detección* sigue ausente.
- **Instrucción de Reemplazo para Gemini 3.8 Flash** (parte Swift, la de menor riesgo y mayor valor inmediato):
  - Acción: REPLACE
  - Buscar bloque:
    ```swift
            let rpm = (i < fanRpms.count) ? min(fanRpms[i], 9999) : 0
    ```
  - Sustituir por:
    ```swift
            // S10 SIO-03: do not launder implausible tach values into
            // plausible-looking ones. `min(rpm, 9999)` used to turn a garbage
            // 65535 into a believable 9999, hiding the fault from both the user
            // and any future stall detection. Report -1 for "not trustworthy"
            // and let the UI render it as "—" rather than a fake number.
            let rawRPM = (i < fanRpms.count) ? fanRpms[i] : 0
            let rpm: Int = (rawRPM < 0 || rawRPM > 10500) ? -1 : rawRPM
    ```
- **Consideraciones de Seguridad & Edge Cases**:
  - **Cambia el contrato de `FanSnapshot.rpm`.** Hay que auditar los consumidores: `FanCurveController.pollHardwareState()` (`:531`) asigna a `fans[i].rpm`, y la UI lo formatea. Verificación obligatoria:
    ```sh
    grep -rn "\.rpm" Sources/RyzenStatus/UI/ Sources/RyzenStatus/Services/AMD/ | grep -v "//"
    ```
    En cada punto de formateo, tratar `-1` como "—" / "sin sensor". Si el proyecto prefiere no cambiar el tipo, la alternativa es añadir `let rpmValid: Bool` a `FanSnapshot` y `FanState` y dejar `rpm` como está — **más invasivo pero sin romper llamantes existentes**; elegir según cuántos consumidores aparezcan en el grep.
  - La detección real de estancamiento (comparar RPM esperado vs medido tras N segundos a un duty dado y escalar a `kFAILSAFE_PWM`) pertenece al kext y es un **cambio de diseño, no quirúrgico**. Con `KRN-02` (piso de PWM) el escenario peligroso ya está cerrado por construcción; la detección es defensa en profundidad para una oleada posterior. No forzarla en este PR.
- **Comando de Verificación**:
  ```sh
  grep -rn "\.rpm\b" Sources/RyzenStatus/UI/ Sources/RyzenStatus/Services/AMD/
  ./build.sh 2>&1 | grep -E "error|warning" ; ./build/RyzenStatus --selftest
  ```

---

# MÓDULO 4 — Concurrencia, timers y sleep/wake

## 4.0 Veredicto: **no hay retain cycles reales**, pero el aislamiento de hilos es incorrecto

Inventario completo de timers y bucles infinitos:

| Componente | Mecanismo | `[weak self]` | Cancelación | Veredicto |
|---|---|---|---|---|
| `FanCurveController.startPolling` `:500-507` | `Timer.scheduledTimer` 1.5 s | ✅ (doble) | `stopPolling()` + `deinit` | sin ciclo; **fuga de trabajo** (`CON-03`) |
| `ProcessorModel` watchdog `:461-490` | `Task.detached` + `sleep` 5 s | ✅ + `break` | `closeDriver()` | sin ciclo; corre durante sleep (`CON-02`) |
| `AutoEppService.start` `:54-63` | `Task.detached` 1.5 s | ✅ | `stop()`/`suspend()` | **falta `break` con `self == nil`** |
| `C6ResidencyService.start` `:57-66` | `Task.detached` 1.5 s | ✅ | `stop()` | ídem; `Task.detached` anidado por tick |
| `SystemMonitor.startTimer` `:652-660` | `Timer` modo `.common` | ✅ | auto-para si nada requiere muestreo | ✅ correcto |

**Los `deinit` son código muerto**: tanto `ProcessorModel` como `FanCurveController` son `static let shared`, así que `deinit` nunca se ejecuta. `ProcessorModel` no tiene `deinit` en absoluto. `FanCurveController.deinit` (`:51-56`) libera el observador de wake y el timer, pero **no cancela** `readTask`, `persistCurvesTask` ni `persistMappingsTask`.

---

### [CON-01] IOKit sincrónico en `@MainActor` disparado desde `didSet` de `@Published`

- **Severidad**: Alta
- **Archivos Afectados**: `Sources/RyzenStatus/Services/AMD/FanCurveController.swift:16-27`
- **Diagnóstico & Causa Raíz**: `FanCurveController` es `@MainActor`, y llama directamente a las funciones `nonisolated` (por tanto **sincrónicas, sin salto de actor**) de `ProcessorModel`. Dos problemas superpuestos:
  1. **Bloqueo del hilo principal.** `syncCurvesToKext()` hace hasta 4 escrituras de LUT de 272 B en main; `syncMappingsToKext()` hace N; `setAllAuto()` hace **2 llamadas al kext por ventilador en un bucle en main** (`:380-381`); `resetFansToAutoSync()` hace **32 llamadas sincrónicas** (`:434-436`); `handleWakeNotification()` hace 4+N escrituras bloqueantes **en el instante del despertar**, el peor momento posible. Y `currentCPUOrPackageTemp` (`:356-361`) es una **propiedad computada que hace IPC al kernel** y la lee la UI vía `isThermalGuardActive`.
  2. **Publicación re-entrante.** Ambos `didSet` disparan IPC dentro de un ciclo de publicación de SwiftUI, y las funciones invocadas **escriben de vuelta estado `@Published`** (`self.kextMissing = true` en `:172`, `self.privilegeError = ...` en `:190`) → el clásico "Publishing changes from within view updates". Con `IOK-01` aplicado (llamadas serializadas) el bloqueo se agrava, así que **este ticket es obligatorio si se aplica IOK-01**.
- **Instrucción de Reemplazo para Gemini 3.8 Flash**:
  - Acción: REPLACE
  - Buscar bloque:
    ```swift
    @Published var customCurves: [FanCurveDefinition] = [] {
        didSet {
            persistCurves()
            syncCurvesToKext()
        }
    }
    @Published var fanMappings: [Int: Int] = [:] {
        didSet {
            persistMappings()
            syncMappingsToKext()
        }
    }
    ```
  - Sustituir por:
    ```swift
    // S10 CON-01: kext I/O no longer happens inside a `didSet`.
    //
    // Two defects were stacked here. First, syncCurvesToKext() /
    // syncMappingsToKext() issue synchronous IOConnectCallMethod calls, and this
    // class is @MainActor, so every assignment blocked the main thread on kernel
    // IPC (up to 4 LUT writes of 272 B each, plus one call per fan). Second,
    // those functions write @Published state back (kextMissing, privilegeError),
    // so running them from a didSet mutated observable state *during* a SwiftUI
    // publish cycle — the "Publishing changes from within view updates" hazard.
    //
    // The upload is now hopped off the main actor and coalesced: rapid successive
    // edits (a slider drag, a preset switch) collapse into one upload instead of
    // one per assignment. Correctness is preserved because syncCurvesToKext
    // already de-duplicates against lastUploadedCurvesFingerprint, and the wake
    // handler still forces an unconditional re-upload.
    @Published var customCurves: [FanCurveDefinition] = [] {
        didSet {
            persistCurves()
            scheduleCurveUpload()
        }
    }
    @Published var fanMappings: [Int: Int] = [:] {
        didSet {
            persistMappings()
            scheduleMappingUpload()
        }
    }
    ```
  - Acción: INSERT (los dos coalescedores, junto a `startPolling()`; añadir antes de `func startPolling() {`)
  - Buscar bloque:
    ```swift
    func startPolling() {
        guard pollTimer == nil else { return }
    ```
  - Sustituir por:
    ```swift
    // MARK: - S10 CON-01 coalesced, off-main kext upload

    /// Debounced curve upload. Replaces the direct `syncCurvesToKext()` call that
    /// used to run inside `customCurves.didSet` on the main thread.
    private func scheduleCurveUpload(force: Bool = false) {
        curveUploadTask?.cancel()
        curveUploadTask = Task { [weak self] in
            // Coalesce a burst of edits into one upload. Cancellation during the
            // window is the normal path, not an error.
            try? await Task.sleep(nanoseconds: 120_000_000)   // 120 ms
            guard !Task.isCancelled, let self else { return }
            // Snapshot the state on the main actor, then leave it.
            let snapshot = self.customCurves
            let outcome = await Task.detached(priority: .userInitiated) {
                FanCurveController.uploadCurves(snapshot, force: force)
            }.value
            guard !Task.isCancelled else { return }
            self.applyUploadOutcome(outcome)
        }
    }

    /// Debounced fan→curve mapping upload. Same rationale as above.
    private func scheduleMappingUpload(force: Bool = false) {
        mappingUploadTask?.cancel()
        mappingUploadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, let self else { return }
            let snapshot = self.fanMappings
            let outcome = await Task.detached(priority: .userInitiated) {
                FanCurveController.uploadMappings(snapshot, force: force)
            }.value
            guard !Task.isCancelled else { return }
            self.applyUploadOutcome(outcome)
        }
    }

    /// Result of an off-main upload, applied back on the main actor.
    struct UploadOutcome: Sendable {
        var kextMissing: Bool = false
        var privilegeDenied: Bool = false
    }

    private func applyUploadOutcome(_ outcome: UploadOutcome) {
        if kextMissing != outcome.kextMissing { kextMissing = outcome.kextMissing }
        if outcome.privilegeDenied {
            privilegeError = FanControlStrings.privilegeRequired
        } else if privilegeError != nil && !outcome.kextMissing {
            privilegeError = nil
        }
    }

    func startPolling() {
        guard pollTimer == nil else { return }
    ```
  - Acción: INSERT (declarar las dos tareas nuevas junto a las existentes)
  - Buscar bloque:
    ```swift
    private var persistMappingsTask: Task<Void, Never>?
    ```
  - Sustituir por:
    ```swift
        private var persistMappingsTask: Task<Void, Never>?
        /// S10 CON-01: coalescing upload tasks that keep kext IPC off the main actor.
        private var curveUploadTask: Task<Void, Never>?
        private var mappingUploadTask: Task<Void, Never>?
    ```
- **Consideraciones de Seguridad & Edge Cases**:
  - **Este ticket requiere refactorizar `syncCurvesToKext`/`syncMappingsToKext` en dos mitades**: una parte `static nonisolated` pura (que hable con `ProcessorModel` y devuelva `UploadOutcome`, llamada arriba `uploadCurves`/`uploadMappings`) y la aplicación de estado en el main actor. Gemini debe leer `FanCurveController.swift:169-241` completo y hacer esa división, moviendo los fingerprints (`lastUploadedCurvesFingerprint`, `lastUploadedMappingsFingerprint`) a almacenamiento protegido por `stateLock` porque ahora se leen fuera del main actor. **No dejar los fingerprints como propiedades `@MainActor` accedidas desde `Task.detached`.**
  - `handleWakeNotification()` debe pasar a `scheduleCurveUpload(force: true)` / `scheduleMappingUpload(force: true)`.
  - `resetFansToAutoSync()` **debe seguir siendo sincrónica**: corre en `applicationWillTerminate`, donde no hay tiempo para tareas asíncronas. Es la excepción correcta y `KRN-03` ahora la respalda con un dead-man switch en el kernel.
  - El debounce de 120 ms es imperceptible para el usuario y colapsa un arrastre de slider en una sola subida.
  - Riesgo de regresión: si el refactor deja `privilegeError` sin limpiar tras un éxito, la UI mostrará un error obsoleto. `applyUploadOutcome` lo cubre.
- **Comando de Verificación**:
  ```sh
  sed -n '160,245p' Sources/RyzenStatus/Services/AMD/FanCurveController.swift  # leer antes de dividir
  ./build.sh 2>&1 | grep -E "error|warning" ; ./build/RyzenStatus --selftest
  ```

---

### [CON-02] Ningún observador de `willSleepNotification`: cuatro sondeos siguen corriendo durante la suspensión

- **Severidad**: Alta
- **Archivos Afectados**: `Sources/RyzenStatus/Services/AMD/FanCurveController.swift:108-127`
- **Diagnóstico & Causa Raíz**: `NSWorkspace.willSleepNotification` **no se observa en ningún punto del repositorio** (`grep` → 0 hits; el único observador del lado sleep es `ExtraBrightnessService.swift:184-187` con `screensDidSleepNotification`). En consecuencia, durante la suspensión siguen armados: `FanCurveController.pollTimer` (1.5 s), `AutoEppService.pollTask` (1.5 s), `C6ResidencyService.pollTask` (1.5 s) y el watchdog del kext (5 s, haciendo `IOServiceGetMatchingService`). Los `Timer` se fusionan pero disparan inmediatamente al despertar; los bucles `Task.sleep` **se reanudan en dark wake y golpean IOKit**. Efecto: consumo en batería durante dark wake y una avalancha de IPC sincrónico en el instante del despertar. `didWakeNotification` sí se observa (`:110-119`) y hace `force: true` correctamente — la mitad de la solución existe.
- **Instrucción de Reemplazo para Gemini 3.8 Flash**:
  - Acción: REPLACE
  - Buscar bloque:
    ```swift
    private func setupWakeObserver() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleWakeNotification()
            }
        }
    }

    private func handleWakeNotification() {
        os_log("System did wake; re-syncing fan curves and mappings to kernel", log: logger, type: .info)
        // AUDIT B-30: force on wake — the kext may have lost its slots across
        // sleep even though our persisted state is unchanged.
        syncCurvesToKext(force: true)
        syncMappingsToKext(force: true)
    }
    ```
  - Sustituir por:
    ```swift
    private func setupWakeObserver() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleWakeNotification()
            }
        }

        // S10 CON-02: nothing in this app observed willSleepNotification, so the
        // 1.5 s fan poll (plus AutoEppService, C6ResidencyService and the 5 s kext
        // watchdog) stayed armed across suspend. Timers coalesce but fire
        // immediately on wake, and the Task.sleep loops genuinely resume during
        // dark wake and hit IOKit — battery drain for telemetry nobody is
        // reading, and an IPC stampede at the moment of wake.
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSleepNotification()
            }
        }
    }

    private func handleSleepNotification() {
        os_log("System will sleep; suspending fan telemetry", log: logger, type: .info)
        // Remember whether we were polling so wake can restore exactly this
        // state rather than unconditionally starting a timer the UI never asked
        // for (startPolling is driven by FansSettingsView's lifecycle).
        wasPollingBeforeSleep = (pollTimer != nil)
        stopPolling()
    }

    private func handleWakeNotification() {
        os_log("System did wake; re-syncing fan curves and mappings to kernel", log: logger, type: .info)
        // AUDIT B-30: force on wake — the kext may have lost its slots across
        // sleep even though our persisted state is unchanged.
        // S10 CON-01: these are now coalesced and run off the main actor, so the
        // wake path no longer performs 4+N blocking kernel writes on main.
        scheduleCurveUpload(force: true)
        scheduleMappingUpload(force: true)
        if wasPollingBeforeSleep {
            wasPollingBeforeSleep = false
            startPolling()
        }
    }
    ```
  - Acción: REPLACE (declarar el observador y la bandera; y liberar el observador en `deinit`)
  - Buscar bloque:
    ```swift
    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        pollTimer?.invalidate()
    }
    ```
  - Sustituir por:
    ```swift
    deinit {
        // NOTE: this class is a `static let shared` singleton, so deinit never
        // actually runs. It is kept correct as defensive code and because Swift 6
        // language mode (BLD-01) will type-check it. Real teardown happens in
        // AppDelegate.applicationWillTerminate via resetFansToAutoSync(), and in
        // the kernel via clientClose() (KRN-03).
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        }
        pollTimer?.invalidate()
        // S10 CON-04: these were previously leaked on teardown.
        readTask?.cancel()
        persistCurvesTask?.cancel()
        persistMappingsTask?.cancel()
        curveUploadTask?.cancel()
        mappingUploadTask?.cancel()
    }
    ```
  - Acción: INSERT (declaraciones)
  - **⚠ Anclaje secuenciado:** incluye el comentario que introduce `IOK-04`, así que **solo coincide si `IOK-04` ya fue aplicado** — garantizado por el orden de ejecución (`IOK-04` precede a `CON-02`). Si no coincide, aplicar `IOK-04` primero; no reescribir el anclaje.
  - Buscar bloque:
    ```swift
        private var wakeObserver: Any?
        /// S10 IOK-04: one-shot latch so the GPU-bridge diagnostic is logged once
    ```
  - Sustituir por:
    ```swift
        private var wakeObserver: Any?
        /// S10 CON-02: sleep-side observer, previously absent entirely.
        private var sleepObserver: Any?
        private var wasPollingBeforeSleep = false
        /// S10 IOK-04: one-shot latch so the GPU-bridge diagnostic is logged once
    ```
- **Consideraciones de Seguridad & Edge Cases**:
  - **Crítico:** detener el sondeo durante la suspensión también detiene `enforceManualThermalGuard()`. Es seguro **solo porque** el guard existe también en el kernel: en el camino de escritura del selector 95 (`:1370-1380`) y, tras `KRN-02`, en el lazo de curvas. Durante la suspensión el SoC no genera calor apreciable. **No aplicar `CON-02` sin `KRN-02`/`KRN-03`.**
  - Restaurar el sondeo solo si estaba activo evita arrancar un timer que la UI no pidió (`startPolling()` lo dirige el ciclo de vida de `FansSettingsView`).
  - `AutoEppService` y `C6ResidencyService` merecen el mismo tratamiento; `AutoEppService` además tiene un bug propio: su centinela `lastWrittenEPP` solo se resetea en `suspend()` (`:80`), así que si el SMU perdió el EPP durante la suspensión y el valor objetivo no cambió, **el EPP nunca se restaura**. Arreglo quirúrgico: en el handler de `didWake`, `lastWrittenEPP = 0xFF`.
  - `SystemMonitor` tampoco observa wake: sus bases de delta (`previousCPUTicks`, `previousCoreTicks`, `:167-168`) no se invalidan, así que la primera muestra post-wake se computa sobre todo el intervalo dormido y produce un pico falso de CPU. Arreglo: invalidar bases en `didWake`.
- **Comando de Verificación**:
  ```sh
  grep -rn "willSleepNotification" Sources/    # debe aparecer ahora
  ./build.sh 2>&1 | grep -E "error|warning" ; ./build/RyzenStatus --selftest
  ```

---

### [CON-03] `pollTimer` en modo `.default`: el guard térmico manual se suspende al abrir cualquier menú

- **Severidad**: Alta (seguridad térmica)
- **Archivos Afectados**: `Sources/RyzenStatus/Services/AMD/FanCurveController.swift:500-507`
- **Diagnóstico & Causa Raíz**: `Timer.scheduledTimer(withTimeInterval:repeats:)` instala el timer en `RunLoop.main` en modo **`.default`**. Cuando macOS entra en un run loop de *tracking* —menú abierto, arrastre de slider, popover con tracking activo— los timers en modo `.default` **no disparan**. Y ese timer es lo que ejecuta `enforceManualThermalGuard()` (`:541-550`). Consecuencia concreta: **mientras el usuario mantiene abierto un menú de la barra o arrastra un punto de la curva, el guard térmico de modo manual deja de aplicarse**. Es precisamente el momento en que el usuario está interactuando con controles de ventiladores. Comparar con `SystemMonitor.startTimer()`, que sí hace lo correcto: `RunLoop.main.add(t, forMode: .common)` (`SystemMonitor.swift:658`).

  Segundo defecto en el mismo bloque: `stopPolling()` tiene **un único llamante** (`FansSettingsView.swift:230`). Cualquier ruta que destruya la vista sin invocarlo deja el timer de 1.5 s golpeando IOKit desde el hilo principal indefinidamente.
- **Instrucción de Reemplazo para Gemini 3.8 Flash**:
  - Acción: REPLACE
  - Buscar bloque:
    ```swift
    func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollHardwareState()
            }
        }
    }
    ```
  - Sustituir por:
    ```swift
    func startPolling() {
        guard pollTimer == nil else { return }
        //
        // S10 CON-03: schedule in `.common` mode, not `.default`.
        //
        // Timer.scheduledTimer installs into RunLoop.main in .default mode, which
        // does NOT fire while a tracking run loop is up — an open menu bar menu,
        // a slider drag, a tracking popover. This timer is what drives
        // enforceManualThermalGuard(), so the manual-mode thermal guard silently
        // stopped being applied exactly while the user was interacting with fan
        // controls. SystemMonitor already gets this right (SystemMonitor.swift:658).
        //
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollHardwareState()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }
    ```
- **Consideraciones de Seguridad & Edge Cases**:
  - `Timer(timeInterval:repeats:)` **no se auto-programa**; olvidar `RunLoop.main.add` deja el sondeo muerto por completo. Verificar que la línea esté presente.
  - El `[weak self]` interno redundante se conserva a propósito: es inocuo y sobrevivirá al modo Swift 6.
  - Con `CON-02` aplicado, este timer ya no corre durante la suspensión, así que el modo `.common` no implica coste extra en batería.
  - La defensa real del guard térmico no debe depender de un timer de UI: tras `KRN-02` y el guard del selector 95, el kernel lo aplica de forma autónoma. Este ticket cierra el hueco de la capa de app, pero el kernel es la autoridad.
- **Comando de Verificación**:
  ```sh
  ./build.sh 2>&1 | grep -E "error|warning" ; ./build/RyzenStatus --selftest
  # Probe manual: abrir el menú de la barra durante 10 s con un ventilador en
  # manual y el paquete >85 °C; el guard debe seguir aplicándose.
  ```

---

### [CON-04] `iokitLock` muerto, bucles que no rompen con `self == nil`, tareas sin cancelar

- **Severidad**: Baja (limpieza; ninguno es una fuga de memoria real)
- **Archivos Afectados**: `Sources/RyzenStatus/Services/AMD/AutoEppService.swift:56-62`, `C6ResidencyService.swift:57-66`
- **Diagnóstico & Causa Raíz**: Ambos servicios tienen el mismo patrón:
  ```swift
  pollTask = Task.detached(priority: .background) { [weak self] in
      await self?.poll()
      while !Task.isCancelled {
          try? await Task.sleep(...)
          await self?.poll()      // ← sin break si self == nil
      }
  }
  ```
  Si `self` se libera, el bucle **sigue girando cada 1.5 s haciendo nada** hasta que alguien cancele la tarea — y el cancelador es un método del objeto ya liberado. En singletons es inalcanzable, pero es una bomba de relojería si alguna vez se desingletoniza. `iokitLock` ya se elimina en `IOK-01`; las cancelaciones de tareas de `FanCurveController` ya se añaden en `CON-02`.
- **Instrucción de Reemplazo para Gemini 3.8 Flash**:
  - Acción: REPLACE
  - **⚠ Este bloque aparece DOS veces, byte a byte idéntico**: en `AutoEppService.swift:56-62` y en `C6ResidencyService.swift:57-66`. Eso es **intencional** — hay que aplicar el mismo reemplazo en **ambos** archivos. Anclar por archivo y aplicarlo dos veces.
  - Buscar bloque:
    ```swift
        pollTask = Task.detached(priority: .background) { [weak self] in
            await self?.poll()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
                await self?.poll()
            }
        }
    ```
  - Sustituir por:
    ```swift
        pollTask = Task.detached(priority: .background) { [weak self] in
            // S10 CON-04: exit the loop when the owner is gone. Previously the
            // `await self?.poll()` simply no-op'd and the loop kept waking every
            // 1.5 s forever, because the only thing that cancels it is a method
            // on the object that just went away.
            guard let strong = self else { return }
            await strong.poll()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
                guard !Task.isCancelled, let strong = self else { break }
                await strong.poll()
            }
        }
    ```
- **Consideraciones de Seguridad & Edge Cases**: `let strong = self` dentro del bucle mantiene una referencia fuerte **solo durante ese tick**, no durante el `sleep` — que es el comportamiento correcto (no prolonga la vida del objeto mientras duerme). Aplicar el patrón idéntico en `C6ResidencyService.swift:57-66`. `C6ResidencyService.poll()` además lanza un `Task.detached` **anidado por tick** con tres lecturas bloqueantes al kext (`:80-85`); vale la pena colapsarlo, pero no es necesario para la corrección.
- **Comando de Verificación**:
  ```sh
  ./build.sh 2>&1 | grep -E "error|warning" ; ./build/RyzenStatus --selftest
  ```


---

# MÓDULO 5 — UI / AppKit / SwiftUI, Now Playing y modularidad

## 5.0 Lo que ya está bien hecho (no tocar)

Antes de los hallazgos, conviene registrar las decisiones correctas para que Gemini no las "optimice":

- **`MenuBarRenderer` tiene tres `NSCache`** (bitmap / symbol / color) con claves sufijadas por apariencia, lo que acota el churn de memoria de la barra. Correcto.
- **`StatusItemController.updateIconAppearance` memoiza con `stateKey`** para no recomponer la misma imagen cada 2 s. Correcto en concepto (defectuoso en cobertura, ver `UI-01`).
- **El popover baja la cadencia al cerrarse.** `popoverDidClose` (`AppDelegate.swift:1028-1052`) hace `setMenuPanelNeeds(.none)`, `ProcessUsageService.stopNetworkMonitoring()`, `clearCachedRows()`, `ResponsibleProcess.clearIconCache()`. `MenuPanelView.monitorNeeds` (`:147-158`) estrecha el muestreo a la sección visible. **El renderizado NO continúa a cadencia de foreground con el popover cerrado.** Correcto y bien pensado.
- **`SystemMonitor` se auto-detiene** cuando nada requiere muestreo (`ensureTimer()` / `stopTimerIfIdle()`, `:608-619`). Correcto.
- **`NowPlayingService.stop()` es exhaustivo** (`:120-144`): invalida timer, para marquesina, incrementa la generación de epoch, quita el status item, resetea snapshot/artwork/identidad, desregistra ambos hotkeys Carbon (ids 25/26) y elimina el observador de workspace. **No hay fuga de observadores al cambiar o cerrar el reproductor** — porque no hay observador por reproductor (el precio es el sondeo).
- **El bridge MediaRemote degrada por símbolo**, sin fatal: `fetchNowPlaying` completa con `.empty` si el símbolo es nil (`NowPlayingSupport.swift:262-266`), y `clientGetBundleID` usa correctamente `takeUnretainedValue()` según la regla CF "Get".
- **La fuga de token de observador al re-desacoplar el dashboard ya está corregida** (marcador `AUDIT A-06`, `AppDelegate.swift:1000-1002`).

---

### [UI-01] `stateKey` sin token de apariencia: composites Dark/Light obsoletos persisten toda la sesión

- **Severidad**: Media
- **Archivos Afectados**: `Sources/RyzenStatus/App/StatusItemController.swift:278-283`
- **Diagnóstico & Causa Raíz**: Dos huecos que se refuerzan:
  1. `stateKey` incluye `hidden`, `mainItemHidden`, `updateAvailable`, `keepAwakeActive`, tintes y `micBadgeActive` — pero **ningún token de apariencia**. Los composites que **no** son template (`BlackHoleGlyph.attentionImage()`, `tintedImage`, `micMutedImage(over:)`) se generan una vez y, al no cambiar la clave, **nunca se recomponen al cambiar de tema**. Un glifo azul de "actualización disponible" compuesto en modo oscuro persiste sin cambios en modo claro durante el resto de la sesión.
  2. **No existe ningún observador de `AppleInterfaceThemeChangedNotification`** en todo el repositorio (`grep` → 0 hits; el único observador distribuido es de layout de teclado en `AppSwitcher.swift:181`). Nada fuerza un redibujado en el instante del cambio de tema. El único observador de apariencia es del lado SwiftUI (`MixerSection.swift:59`). Resultado: aunque se arregle la clave, el refresco espera al siguiente tick — hasta ~2 s con métricas fijadas, y hasta **30 s** cuando solo se muestra el contador de keep-awake.

  `NowPlayingService` **sí lo hace bien**: su clave de render incluye `button.effectiveAppearance.name.rawValue` (`NowPlayingService.swift:482-483`). Ese es el patrón a replicar.
- **Instrucción de Reemplazo para Gemini 3.8 Flash**:
  - Acción: REPLACE
  - Buscar bloque:
    ```swift
        let stateKey = [String(hidden), String(mainItemHidden), String(updateAvailable),
                        String(keepAwakeActive), KeepAwakeIconTint.current.rawValue,
                        KeepAwakeActiveIcon.current.rawValue,
                        String(micBadgeActive)].joined(separator: "|")
    ```
  - Sustituir por:
    ```swift
        // S10 UI-01: the appearance name is part of the cache key.
        //
        // Without it, the non-template composites (attentionImage, tintedImage,
        // micMutedImage) were generated once and never regenerated on a theme
        // flip, because the key did not change. A blue "update available" glyph
        // composed under Dark mode persisted unchanged into Light mode for the
        // rest of the session. NowPlayingService already keys on appearance
        // (NowPlayingService.swift:482-483); this brings the main item in line.
        let appearanceToken = (statusItem.button?.effectiveAppearance
                               ?? NSApp.effectiveAppearance).name.rawValue
        let stateKey = [String(hidden), String(mainItemHidden), String(updateAvailable),
                        String(keepAwakeActive), KeepAwakeIconTint.current.rawValue,
                        KeepAwakeActiveIcon.current.rawValue,
                        String(micBadgeActive), appearanceToken].joined(separator: "|")
    ```
  - Acción: INSERT (observador de cambio de tema; añadir al final de `bind()`)
  - Buscar bloque:
    ```swift
        let keepAwakeActive = KeepAwakeManager.shared.isActive
    ```
  - Sustituir por:
    ```swift
        let keepAwakeActive = KeepAwakeManager.shared.isActive
        // (see themeObserver installed in bind() — S10 UI-01)
    ```
  - **Bloque adicional obligatorio.** Gemini debe localizar `func bind()` (`StatusItemController.swift:149-190`) e insertar, al final del cuerpo:
    ```swift
        // S10 UI-01: force an immediate re-render when the user flips the system
        // theme. Nothing in the app observed this, so the menu bar item kept its
        // previously composed image until the next monitor tick — up to ~2 s with
        // metrics pinned, and up to 30 s when only the keep-awake glyph is shown.
        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The notification can arrive marginally before NSApp.effectiveAppearance
            // has settled, so re-render on the next main-loop turn.
            DispatchQueue.main.async { self?.refresh() }
        }
    ```
    y declarar `private var themeObserver: Any?` junto a las demás propiedades, liberándolo en `deinit` con `DistributedNotificationCenter.default().removeObserver(themeObserver)`.
- **Consideraciones de Seguridad & Edge Cases**:
  - `AppleInterfaceThemeChangedNotification` es una notificación distribuida **no documentada**. Es estable desde macOS 10.14 y ampliamente usada, pero si desaparece el fallo es benigno: se vuelve al comportamiento actual (refresco en el siguiente tick), nunca un crash. No es una API privada enlazada, solo un nombre de notificación.
  - El `DispatchQueue.main.async` de un turno es deliberado: la notificación puede llegar antes de que `effectiveAppearance` se estabilice, y sin él la primera recomposición podría usar el tema antiguo.
  - Añadir el token de apariencia **aumenta** ligeramente las recomposiciones (una extra por cambio de tema). Eso es exactamente lo deseado.
  - Verificar que `refresh()` sea accesible desde ese contexto y que no sea `private` a otro ámbito.
- **Comando de Verificación**:
  ```sh
  grep -n "func refresh" Sources/RyzenStatus/App/StatusItemController.swift
  ./build.sh 2>&1 | grep -E "error|warning" ; ./build/RyzenStatus --selftest
  # Probe manual: alternar Apariencia en Ajustes del Sistema y observar el ícono.
  ```

---

### [UI-02] La marquesina de Now Playing compone un `NSImage` sin caché a 20 Hz

- **Severidad**: Media (energía)
- **Archivos Afectados**: `Sources/RyzenStatus/Services/NowPlaying/NowPlayingService.swift:479-484`, `:568-663`
- **Diagnóstico & Causa Raíz**: `renderMenuBar()` mete el desplazamiento de la marquesina en su clave de deduplicación **precisamente para que cada paso repinte** (`:479-484`), y luego llama `composeMenuBarImage(...)` (`:568-663`), que asigna un `NSImage` **completamente nuevo** con un drawing handler, mide la cadena vía `menuBarTextWidth` **hasta 3 veces por fotograma** (`:640`, `:643`) y, si la barra de progreso está activa, crea dos `NSBezierPath`. **No hay caché de imagen en esta ruta** —a diferencia de `MenuBarRenderer.blockImageCache`—. Esto corre **20 veces por segundo, indefinidamente**, mientras el título del track supere 260 pt (`NowPlayingMarqueeEngine.maxTextWidth`, `NowPlayingSupport.swift:334`), lo cual es lo normal para títulos largos.

  Mitigaciones existentes: el timer solo existe si el texto realmente desborda (`:520-539`) y las fases de retención paran el timer a favor de un solo `asyncAfter` (`:530-538`). Pero esos closures `asyncAfter` **no son cancelables**, así que cambios rápidos de ajustes pueden encolar renders solapados (inocuo, protegido por clave).
- **Instrucción de Reemplazo para Gemini 3.8 Flash**:
  - Acción: REPLACE (memoizar la medición del texto, que es el coste dominante y es invariante durante todo el recorrido de la marquesina)
  - Buscar bloque (**firma real verificada en `:561-563`**: es `static`, recibe solo el texto, y usa la fuente estática `menuBarTextFont`):
    ```swift
    private static func menuBarTextWidth(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: menuBarTextFont]).width)
    }
    ```
  - Sustituir por:
    ```swift
    // S10 UI-02: memoized text measurement.
    //
    // menuBarTextWidth is called up to 3x per composed frame (call sites ~:519,
    // ~:622, ~:625), and the marquee drives that at 20 Hz for as long as the
    // title overflows — i.e. indefinitely for long track titles. Each call runs a
    // full NSString layout pass. The measured width depends only on the string
    // and the font; neither changes while the marquee scrolls, only the draw
    // offset does. Memoizing removes ~60 layout passes per second at zero
    // behavioural cost.
    //
    // The cache is static because the measuring function is static. It is keyed
    // on the font as well as the text so that a font-size preference change
    // cannot serve a stale width (which would clip or overflow the title).
    private struct MenuBarTextWidthKey: Hashable {
        let text: String
        let fontName: String
        let fontSize: Double
    }
    private static var menuBarTextWidthCache: [MenuBarTextWidthKey: CGFloat] = [:]

    private static func menuBarTextWidth(_ text: String) -> CGFloat {
        let font = menuBarTextFont
        let key = MenuBarTextWidthKey(text: text,
                                      fontName: font.fontName,
                                      fontSize: Double(font.pointSize))
        if let hit = menuBarTextWidthCache[key] { return hit }
        let width = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        // Bound the cache: track titles churn over a long listening session and
        // an unbounded dictionary here would be a slow leak.
        if menuBarTextWidthCache.count > 64 {
            menuBarTextWidthCache.removeAll(keepingCapacity: true)
        }
        menuBarTextWidthCache[key] = width
        return width
    }
    ```
- **Consideraciones de Seguridad & Edge Cases**:
  - Este parche es **drop-in**: conserva exactamente el nombre, la firma y el tipo de retorno (`private static func menuBarTextWidth(_ text: String) -> CGFloat`), así que **los tres puntos de llamada no requieren ningún cambio**. La implementación original es una única expresión `ceil(...size(withAttributes:).width)`, verificada en `:561-563`.
  - `menuBarTextWidthCache` es estado estático mutable. `NowPlayingService` es `@MainActor` y todos los llamantes están en el camino de render en el hilo principal, así que **hoy no hay carrera**. Bajo modo Swift 6 (`BLD-01`) una `static var` mutable sin aislamiento **es un error de compilación**: la corrección es anotarla `@MainActor private static var`. Si `BLD-01` ya está aplicado, añadir `@MainActor`.
  - La clave incluye nombre y tamaño de fuente. Si `menuBarTextFont` dependiera además de la apariencia, hay que incorporar ese factor o el texto se recortará al cambiar de tema.
  - El límite de 64 entradas evita una fuga lenta a lo largo de una sesión larga de escucha.
  - Mejora estructural mayor (fuera de alcance quirúrgico): bajar la marquesina de 20 Hz a 12-15 Hz —imperceptible— y cachear la imagen compuesta indexada por desplazamiento entero. Reduce el coste a ~1/20 tras el primer ciclo completo. Recomendado para una oleada posterior.
- **Comando de Verificación**:
  ```sh
  grep -n "menuBarTextWidth" Sources/RyzenStatus/Services/NowPlaying/NowPlayingService.swift
  ./build.sh 2>&1 | grep -E "error|warning" ; ./build/RyzenStatus --selftest
  # Medir energía: abrir Monitor de Actividad con un título largo reproduciéndose,
  # comparar "Impacto energético" antes/después.
  ```

### 5.1 Nota sobre MediaRemote en macOS 15.4+ (informativa, decisión de producto)

`NowPlayingSupport.swift:233-240` implementa `readsBlockedBySystem` como una **conjetura por versión de OS hardcodeada**, no como una sonda de error en tiempo de ejecución:

- Cuando es `true`, las lecturas se enrutan a AppleScript (`NowPlayingAutomation.fetchSnapshot`) y se pre-disparan los prompts TCC para Music/Spotify vía `AEDeterminePermissionToAutomateTarget`.
- **Problema (a):** al ser `majorVersion > 15`, fuerza permanentemente la ruta lenta de AppleScript incluso si las lecturas volvieran a funcionar.
- **Problema (b):** las *escrituras* siguen yendo por `MRMediaRemoteSendCommand` para cualquier sesión que no sea Music/Spotify, con un fallback de `NSEvent` de teclas auxiliares.
- **Problema (c):** con la ruta AppleScript, **solo Music y Spotify son visibles** — navegadores y reproductores de vídeo desaparecen silenciosamente en 15.4+.

Recomendación: convertir la compuerta en una sonda real (intentar `MRMediaRemoteGetNowPlayingInfo` una vez, y solo caer a AppleScript si devuelve vacío/error), cacheando el resultado por sesión. Eso recupera navegadores en las versiones donde el símbolo aún funciona. **No es un parche quirúrgico** — requiere decidir el comportamiento de producto y probar en 15.4/15.5/26.x, así que se documenta sin bloque de reemplazo.

---

### [UI-03] El dashboard desacoplado mantiene cadencia de foreground estando ocluido o en otro Space

- **Severidad**: Media (energía)
- **Archivos Afectados**: `Sources/RyzenStatus/App/AppDelegate.swift:990-1020`
- **Diagnóstico & Causa Raíz**: `grep` de `occlusionState` / `NSWindowDidChangeOcclusionState` en todo el repo → **0 hits**. La ventana desacoplada registra `SystemMonitor.shared.panelDidAppear()` al mostrarse y `panelDidDisappear()` **solo** desde `NSWindow.willCloseNotification` (`:1000-1017`). Y se crea con `window.level = .floating` + `collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]` (`:994-996`). Consecuencia: un dashboard totalmente **cubierto por otra ventana**, o en **otro Space**, sigue muestreando y re-renderizando a cadencia de **foreground**. macOS ya calcula esta información y la ofrece gratis vía `occlusionState`.
- **Instrucción de Reemplazo para Gemini 3.8 Flash**:
  - Acción: INSERT (junto al observador de `willCloseNotification` existente, dentro del mismo bloque de creación de ventana)
  - **⚠ Este ticket NO tiene anclaje literal.** No hay un bloque único que buscar: Gemini debe **localizar** el registro existente de `NSWindow.willCloseNotification` y añadir el nuevo observador de forma adyacente, reutilizando el mismo mecanismo de almacenamiento de token que introdujo `AUDIT A-06` (de lo contrario se reintroduce esa misma fuga). Localización:
    ```sh
    grep -n "willCloseNotification" Sources/RyzenStatus/App/AppDelegate.swift
    sed -n '985,1025p' Sources/RyzenStatus/App/AppDelegate.swift
    ```
  - Insertar (adaptando el nombre de la variable de token al que ya use el archivo):
    ```swift
        // S10 UI-03: stand down when the detached dashboard is not actually
        // visible. The window is .floating + .canJoinAllSpaces, so it stays
        // "open" while fully covered by another window or sitting on another
        // Space — and panelDidDisappear() was only wired to willCloseNotification,
        // so it kept sampling and re-rendering at full foreground cadence.
        // AppKit computes occlusion for us; this just listens.
        dashboardOcclusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] note in
            guard let win = note.object as? NSWindow else { return }
            if win.occlusionState.contains(.visible) {
                SystemMonitor.shared.panelDidAppear()
            } else {
                SystemMonitor.shared.panelDidDisappear()
            }
        }
    ```
- **Consideraciones de Seguridad & Edge Cases**:
  - `panelDidAppear()` / `panelDidDisappear()` deben ser **idempotentes o balanceados por contador**. `didChangeOcclusionStateNotification` puede dispararse varias veces seguidas. Verificación obligatoria: `grep -n "func panelDidAppear\|func panelDidDisappear" Sources/RyzenStatus/Services/SystemMonitor/SystemMonitor.swift` — si usan un contador de referencias, hay que evitar el doble decremento cuando llegue *también* `willCloseNotification`. La forma segura es que la oclusión fije un booleano `panelVisible` en lugar de incrementar/decrementar.
  - El token del observador debe almacenarse y liberarse en el mismo sitio donde ya se maneja el de `willCloseNotification` (corregido en `AUDIT A-06`), o se reintroduce exactamente esa fuga.
  - `.visible` en `occlusionState` significa "al menos parcialmente visible": una ventana solapada al 90 % sigue contando como visible. Es el comportamiento correcto y conservador.
- **Comando de Verificación**:
  ```sh
  grep -n "willCloseNotification\|panelDidAppear\|panelDidDisappear" \
    Sources/RyzenStatus/App/AppDelegate.swift Sources/RyzenStatus/Services/SystemMonitor/SystemMonitor.swift
  ./build.sh 2>&1 | grep -E "error|warning" ; ./build/RyzenStatus --selftest
  ```

---

### [UI-04] `AppVolumeMixer` (y `AudioInputDeviceManager`) quedan residentes con listeners HAL globales estando "desactivados"

- **Severidad**: Media (el mayor coste energético "residente sin uso" de la app)
- **Archivos Afectados**: `Sources/RyzenStatus/Services/Audio/AppVolumeMixer.swift:99-105`, **y `Sources/RyzenStatus/Services/Audio/AudioInputDeviceManager.swift:45-51`**
- **⚠ El bloque a buscar aparece DOS veces en el repositorio, byte a byte idéntico.** `AudioInputDeviceManager.syncWithPreferences()` (`:45-51`) es una copia literal —misma compuerta `AppFeature.mixer.isAvailable`, mismo `start()`/`stop()`— así que **padece exactamente el mismo defecto** y también permanece residente. Gemini debe aplicar el parche **en los dos archivos**, adaptando en cada uno el nombre del método de apagado (`AppVolumeMixer` tiene `stopAll()` además de `stop()`; comprobar si `AudioInputDeviceManager` lo tiene antes de invocarlo). No confiar en una búsqueda global de un solo reemplazo: hay que anclar por archivo.
- **Diagnóstico & Causa Raíz**: La compuerta es:
  ```swift
  func syncWithPreferences() {
      if AppFeature.mixer.isAvailable { start() } else { stop() }
  }
  ```
  `isAvailable` significa **"instalado"**, no "activado por el usuario". Compárese con los servicios que lo hacen bien —`NowPlayingService.swift:83-90`, `ClipboardHistoryService.swift:77-86`, `DockPreviewService.swift:85-95`— que exigen **además** su `DefaultsKey.*Enabled`. Resultado: con el mixer meramente *instalado* (el estado por defecto) y jamás usado, `start()` (`:109-122`) instala **tres listeners HAL globales** —`kAudioHardwarePropertyDevices`, `kAudioHardwarePropertyDefaultOutputDevice`, `kAudioHardwarePropertyProcessObjectList`— más **un listener por proceso de audio** (`subscribeToRunningChanges`, `:170-179`). Cada evento de dispositivo o proceso dispara `scheduleListenerRefresh` → `refreshApps()` (`:445+`), que enumera dispositivos y procesos **en la cola principal**. Throttled, pero nunca silenciado.
- **Instrucción de Reemplazo para Gemini 3.8 Flash**:
  - Acción: REPLACE
  - **⚠ Este bloque aparece DOS veces, byte a byte idéntico** (`AppVolumeMixer.swift:99-105` y `AudioInputDeviceManager.swift:45-51`). Aplicar en **ambos**, anclando por archivo, y adaptar en cada uno los métodos de apagado disponibles (`AppVolumeMixer` tiene `stopAll()` **y** `stop()`; comprobar cuáles existen en `AudioInputDeviceManager` con `grep -n "func stop" Sources/RyzenStatus/Services/Audio/AudioInputDeviceManager.swift` antes de invocarlos).
  - Buscar bloque:
    ```swift
    func syncWithPreferences() {
        if AppFeature.mixer.isAvailable {
            start()
        } else {
            stop()
        }
    }
    ```
  - Sustituir por:
    ```swift
    func syncWithPreferences() {
        // S10 UI-04: `isAvailable` means "installed", not "switched on".
        //
        // Because this only checked availability, a merely-installed-and-never-used
        // mixer installed three global HAL property listeners plus one per audio
        // process, and every device/process event ran refreshApps() on the main
        // queue. That was the app's largest resident-while-unused energy cost.
        //
        // Every well-behaved service here gates on BOTH availability and its own
        // enabled key (see NowPlayingService.swift:83-90,
        // ClipboardHistoryService.swift:77-86, DockPreviewService.swift:85-95).
        // This brings the mixer in line.
        let enabled = Defaults[.mixerEnabled]
        if AppFeature.mixer.isAvailable && enabled {
            start()
        } else {
            stopAll()
            stop()
        }
    }
    ```
- **Consideraciones de Seguridad & Edge Cases**:
  - **`Defaults[.mixerEnabled]` puede no existir.** Verificar con `grep -rn "mixerEnabled" Sources/RyzenStatus/Core/`. Si falta, hay que declararla en `DefaultsKey+App.swift` **con valor por defecto `true`** para no cambiar el comportamiento de usuarios existentes que ya usan el mixer — el ahorro llega de quienes nunca lo activaron, no de romper a quienes sí. Si el proyecto prefiere que el valor por defecto sea `false`, es un cambio de comportamiento que debe ir en las notas de versión.
  - Se llama `stopAll()` **antes** de `stop()`: `stopAll()` (`:124-130`) desmonta los engines por app y devuelve el audio al output del sistema sin tocar; `stop()` quita los listeners. Invertir el orden dejaría engines huérfanos.
  - Hay que asegurar que la UI de ajustes del mixer llame a `syncWithPreferences()` al conmutar el toggle, o el cambio no tendrá efecto hasta el siguiente arranque.
- **Comando de Verificación**:
  ```sh
  grep -rn "mixerEnabled" Sources/RyzenStatus/Core/ Sources/RyzenStatus/UI/
  grep -n "func stopAll\|func stop\b" Sources/RyzenStatus/Services/Audio/AppVolumeMixer.swift
  ./build.sh 2>&1 | grep -E "error|warning" ; ./build/RyzenStatus --selftest
  ```

---

### [UI-05] `.screenRecorder` declarado en el catálogo pero sin entrada en `FeatureRuntime.bindings`

- **Severidad**: Baja
- **Archivos Afectados**: `Sources/RyzenStatus/App/FeatureRuntime.swift:117-179`, `Core/FeatureCatalog.swift:29`
- **Diagnóstico & Causa Raíz**: `FeatureCatalog.swift:29` declara `.screenRecorder`, pero el mapa `bindings` de `FeatureRuntime` cubre de `.switcher` a `.appUpdates` y **lo omite**. El servicio *sí tiene* un teardown correcto, pero solo lo invoca la UI de Ajustes: desactivar la función desde cualquier otra ruta (preset, import de backup, restablecimiento) **no lo apaga**.
- **Instrucción de Reemplazo para Gemini 3.8 Flash**:
  - Acción: INSERT (añadir la entrada ausente al mapa `bindings`; Gemini debe localizar la entrada `.appUpdates` y añadir la nueva **adyacente**, respetando el formato exacto de las entradas vecinas)
  - Insertar en `bindings`:
    ```swift
        // S10 UI-05: .screenRecorder was declared in FeatureCatalog but had no
        // binding here, so only the Settings UI ever tore it down. Disabling the
        // feature through a preset, a settings backup import or a reset left the
        // service running.
        .screenRecorder: { ScreenRecorderService.shared.syncWithPreferences() },
    ```
- **Consideraciones de Seguridad & Edge Cases**: Verificar el nombre exacto del método de sincronización (`grep -n "func syncWithPreferences" Sources/RyzenStatus/Services/**/ScreenRecorderService.swift`) y el formato exacto de las entradas vecinas del diccionario — algunas usan closures con parámetros. Copiar el estilo del vecino, no el de este ejemplo. Nótese que añadir el binding **instancia el singleton** al primer flip de disponibilidad, lo cual es el comportamiento correcto y coherente con los otros 39.
- **Comando de Verificación**:
  ```sh
  grep -n "screenRecorder" Sources/RyzenStatus/Core/FeatureCatalog.swift Sources/RyzenStatus/App/FeatureRuntime.swift
  ./build.sh 2>&1 | grep -E "error|warning" ; ./build/RyzenStatus --selftest
  ```

### 5.2 Hallazgo estructural: la premisa de `FeatureRuntime` está roto por la capa de UI

`FeatureRuntime` documenta en `:8-10` que "mencionar una función nunca instancia su servicio". **Los 39 destinos del mapa `bindings` son `static let shared`**, así que un servicio, una vez instanciado, **nunca abandona la memoria hasta el próximo arranque** — el propio archivo lo admite (`needsRestartToUnload` / `relaunchApp`). Eso es una decisión de diseño defendible: el `stop()` de cada servicio quita event taps, observadores y timers, así que el coste residual es una instancia inerte de unos pocos KB.

Sin embargo la premisa se rompe **antes** de cualquier flip de disponibilidad:
- `StatusItemController.bind()` (`:149-190`) toca incondicionalmente `KeepAwakeManager.shared`, `UpdateService.shared`, `MicMuteService.shared`, `L10n.shared` y `SystemMonitor.shared`. Así, `.keepAwake`, `.micMute`, `.appUpdates` y las seis funciones `monitor*` tienen singletons vivos **con sus suscripciones Combine** incluso desinstaladas.
- `MenuPanelView` mantiene `@ObservedObject` sobre `ScrollInverter.shared`, `AppSwitcher.shared`, `DockPreviewService.shared`, `FinderCutPaste.shared`, `AutoQuitService.shared`, `WindowMaximizer.shared` y `KeyboardDebounceService.shared` (`:1139-1145`). **Abrir el panel una sola vez instancia los siete**, con independencia de su disponibilidad.

Respuesta a la pregunta de auditoría "¿permanecen completamente descargados de memoria cuando el usuario los desactiva?": **no, y por diseño no pueden** — son singletons. Lo que sí se logra (y es lo que importa para CPU/energía en reposo) es que sus *recursos activos* se liberen. Los `stop()` verificados como correctos incluyen `AppSwitcher` (`:154-158`: `stopObservingKeyboardLayout` + `removeTap` + `stopWarming`), `AppActivationTracker.stop()` (`:42-46`), `ClipboardHistoryService`, `DockPreviewService`, `ScreenshotService`, `ScreenRecorderService`. **Las dos excepciones reales de energía son `UI-04` (mixer) y `UI-02` (marquesina)**; el resto cumple el objetivo de "cero impacto en reposo". Migrar a instancias opcionales (`private static var _shared: X?` con `teardown()` que la anule) es la solución correcta pero es una refactorización de 39 servicios: recomendada como oleada propia, no como parche quirúrgico.

---

### [BLD-01] Sin Swift 6 / strict concurrency: ninguna de estas invariantes está forzada por el compilador

- **Severidad**: Media (prevención de regresiones)
- **Archivos Afectados**: `Package.swift:11-14`
- **Diagnóstico & Causa Raíz**: El manifiesto completo son 16 líneas: `swift-tools-version:5.9`, `platforms: [.macOS(.v14)]`, un `.executableTarget`, y **ninguna cláusula `swiftSettings`**. Por tanto: sin `swiftLanguageMode(.v6)`, sin `.enableUpcomingFeature("StrictConcurrency")`, sin `-strict-concurrency=complete`, y sin ningún `unsafeFlags` (verificado también en `.github/workflows/*.yml`: CI no añade banderas). El target compila en **modo de lenguaje Swift 5**.

  Consecuencia directa: las violaciones de aislamiento halladas en este módulo **no las diagnostica el compilador**. En particular quedarían como errores duros bajo Swift 6: `FanCurveController.deinit` tocando estado del main actor (el `deinit` de una clase `@MainActor` es `nonisolated`), las `Task.detached` capturando `self` fuertemente y mutando estado `@Published`, y los boxes `@unchecked Sendable`. Nótese que `Package.swift` es **solo para indexado**: la build real es una invocación directa de `swiftc` en `build.sh` (`CONTRIBUTING.md:22-24`), así que **el cambio hay que hacerlo en los dos sitios** o no tendrá efecto.
- **Instrucción de Reemplazo para Gemini 3.8 Flash**:
  - Acción: REPLACE
  - Buscar bloque:
    ```swift
        .executableTarget(
            name: "RyzenStatus",
            path: "Sources/RyzenStatus"
        )
    ```
  - Sustituir por:
    ```swift
        .executableTarget(
            name: "RyzenStatus",
            path: "Sources/RyzenStatus",
            swiftSettings: [
                // S10 BLD-01: staging step toward Swift 6 language mode.
                //
                // The target compiled in Swift 5 mode with no concurrency
                // checking, so none of the isolation invariants this audit relies
                // on were enforced: kext IPC on the main actor (CON-01), a
                // @MainActor deinit touching main-actor state (CON-02), and
                // Task.detached closures mutating @Published state.
                //
                // "StrictConcurrency" as an upcoming feature surfaces these as
                // WARNINGS first, which is the right sequencing: CONTRIBUTING.md
                // requires a warning-free build, so flip to
                // .swiftLanguageMode(.v6) only once the warning count is zero.
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ```
- **Consideraciones de Seguridad & Edge Cases**:
  - **Aplicar este ticket ÚLTIMO.** Habilitar la comprobación antes de arreglar `CON-01`/`CON-02` producirá una avalancha de avisos que enmascara el trabajo real y viola `CONTRIBUTING.md:107` ("`./build.sh` debe terminar sin avisos").
  - `Package.swift` **no dirige la build de release**. Para que la comprobación se aplique de verdad hay que añadir la bandera equivalente a `build.sh`: `-enable-upcoming-feature StrictConcurrency` en la invocación de `swiftc`. Verificar cómo `build.sh` construye su lista de banderas antes de editar.
  - No pasar a `.swiftLanguageMode(.v6)` en el mismo PR. La ruta es: avisos → cero avisos → modo v6.
- **Comando de Verificación**:
  ```sh
  grep -n "swiftc\|-swift-version\|-enable-upcoming" build.sh
  ./build.sh 2>&1 | grep -cE "warning"     # objetivo: 0 antes de pasar a v6
  ./build/RyzenStatus --selftest
  ```

---

# Plan de ejecución para Gemini 3.8 Flash

## Orden obligatorio (las dependencias son estrictas)

**Oleada 1 — Seguridad térmica del kernel. No se puede diferir.**
```
KRN-00  →  KRN-01  →  KRN-02  →  KRN-03
```
`KRN-00` aporta las constantes que `KRN-01`/`KRN-02` consumen. `KRN-01` publica `curveSmoothedValid[]`/`curveRawSourceTemp[]` que `KRN-02` lee. `KRN-03` es independiente pero pertenece a la misma compilación del kext.
Opcionales en la misma oleada: `KRN-04` (**todo o nada** — cambia un contrato compartido), `KRN-05`.

**Oleada 2 — SuperIO.** `SIO-01` → `SIO-02` (estricto: `SIO-02` devuelve `0xFFFF` como sentinel y depende del filtro de `SIO-01`). `SIO-03` aparte, y **auditar sus consumidores antes de aplicar**.

**Oleada 3 — IOKit + concurrencia. `IOK-01` y `CON-01` son un par indivisible.**
```
IOK-01  →  CON-01  →  IOK-03  →  CON-02  →  CON-03  →  IOK-02, IOK-04, CON-04
```
`IOK-01` serializa las llamadas al kext; si se aplica **sin** `CON-01`, se serializa *sobre el hilo principal* y la UI se vuelve perceptiblemente peor. `IOK-03` necesita los contadores que `IOK-01` añade a `ConnectBox`. `CON-02` no debe aplicarse sin `KRN-02`/`KRN-03` (detiene el guard térmico del lado app durante la suspensión).

**Oleada 4 — UI y energía.** `UI-01`, `UI-02`, `UI-03`, `UI-04`, `UI-05`, `IOK-05`. Mutuamente independientes.

**Oleada 5 — `BLD-01`, en último lugar y solo con cero avisos.**

## Tickets que exigen lectura previa, no aplicación mecánica

Gemini **debe leer el archivo y adaptar** en estos casos, en lugar de pegar el bloque tal cual:

| Ticket | Qué hay que resolver antes |
|---|---|
| `CON-01` | Dividir `syncCurvesToKext`/`syncMappingsToKext` (`:169-241`) en mitad pura + aplicación en main actor; **mover los fingerprints a `stateLock`** |
| `IOK-02` | Confirmar que `String(cString:)` esté protegido por `outputStrCount > 0` — si no, es un crash por rango |
| `IOK-04` | Reutilizar el string de privilegios existente de los selectores 101/102; **no** crear una clave nueva (obligaría a 12 localizaciones) |
| `SIO-01` | Leer la dimensión real de `fanPeakRPMs` y usar la misma para `fanRPMValid`; replicar en `NCT668X` |
| `SIO-03` | Auditar todos los consumidores de `FanSnapshot.rpm` antes de introducir `-1` |
| `UI-01` | Localizar `bind()` y `refresh()`; añadir `themeObserver` y liberarlo en `deinit` |
| `UI-02` | Adaptar la firma del wrapper a la real de `menuBarTextWidth`; incluir en la clave **todo** atributo que afecte la medición |
| `UI-03` | Confirmar que `panelDidAppear`/`panelDidDisappear` sean idempotentes; almacenar el token como en `AUDIT A-06` |
| `UI-04` | Verificar/crear `DefaultsKey.mixerEnabled` con default `true` |
| `UI-05` | Copiar el formato exacto de las entradas vecinas del diccionario `bindings` |
| `BLD-01` | Añadir la bandera equivalente en `build.sh`, no solo en `Package.swift` |

## Verificación por oleada

**App (Swift)** — según `CONTRIBUTING.md:106-108`:
```sh
./build.sh                      # debe terminar SIN avisos
./build/RyzenStatus --selftest  # debe imprimir "SELFTEST OK"
./build/RyzenStatus --sensors   # las lecturas deben ser plausibles, no ceros
```

**Kext (C++)**:
```sh
cd SMCAMDProcessor_Source && xcodebuild -project AMDRyzenCPUPowerManagement.xcodeproj \
  -target AMDRyzenCPUPowerManagement -configuration Release build 2>&1 | grep -E "error|warning|BUILD"
```

**Probes en hardware (imprescindibles para la Oleada 1; el kext controla ventiladores reales):**
1. **Piso de PWM (`KRN-02`):** cargar una curva con ancla al 1 % a temperatura idle. Verificar que el ventilador gira a ≈15 %, no calado.
2. **Dead-man switch (`KRN-03`):** fijar un ventilador en manual bajo, `sudo pkill -9 RyzenStatus`, confirmar `dmesg | grep "clientClose released"` y que el ventilador vuelva a control BIOS.
3. **Guard con fuente GPU (`KRN-02`):** curva con fuente GPU, cargar la CPU hasta >85 °C con la dGPU en idle. El ventilador **debe** subir a ≥200 PWM.
4. **Failsafe (`KRN-01`/`KRN-02`):** difícil de forzar sin instrumentar; validar por inspección de código y confirmando que un `getPackageTemp()` inválido produce `kFAILSAFE_PWM` y no `lut[0]`.
5. **Guard bajo tracking (`CON-03`):** ventilador en manual, paquete >85 °C, mantener un menú de la barra abierto 10 s. El guard debe seguir activo.

## Lo que esta auditoría NO encontró (registrado para no volver a buscarlo)

- **Ninguna fuga de `io_service_t` ni `io_connect_t`.** Los 8 sitios de ciclo de vida son correctos.
- **Ningún desalineamiento numérico de selectores** entre Swift y el kext, incluido el 103.
- **Ninguna ruta de corrupción de memoria ni kernel panic por tamaños de buffer.** `CPUSensorPacket` (304 B) y `AMDFanCurveInput` (272 B) están validados en ambos lados; la serialización explícita evita el error clásico de `MemoryLayout` sobre structs con arrays Swift. **Este patrón no debe "simplificarse"**: `withUnsafeBytes(of: input)` sobre `AMDFanCurveInput` enviaría 24 bytes (¡un puntero!) al kernel.
- **Ningún retain cycle real.** Todos los timers y bucles usan `[weak self]`.
- **Ningún bug de conversión PWM** (`/255` vs `/2.55`) ni truncamiento por `Int()`.
- **Ningún `DispatchQueue.main.sync` en la ruta AMD/IOKit.** Los 4 que existen están en servicios no relacionados (`FinderCutPaste:228`, `ShellSupport:94`, `SuperKeyService:724`, `AppSwitcher:347`) y sí se auto-bloquearían si se invocasen desde el hilo principal — fuera del alcance de esta auditoría, pero conviene anotarlo.
- **Ninguna fuga de observadores en Now Playing** al cambiar o cerrar el reproductor.
- **Sin tests unitarios de la matemática de seguridad de la LUT.** No se encontró target de tests para `FanCurveDefinition` ni `AMDFanSafety`. Tras la Oleada 1, los invariantes que merecen un test son: `kCURVE_MIN_ACTIVE_PWM` respetado para toda LUT no-cero, `CPUSensorPacket.byteSize == 304`, `AMDFanCurveInput.packedData().count == 272`, y `effectiveManualPWM(userPWM: 3, currentTemp: 90) == 200`.
