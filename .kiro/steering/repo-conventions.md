# Convenciones del repo

## Verificación

- `./build.sh` debe terminar SIN warnings (exigencia de `CONTRIBUTING.md`).
- `./build.sh --test` — suite actual: 6274 checks.
- `./build/RyzenStatus --selftest` debe imprimir `SELFTEST OK`
  (`Sources/RyzenStatus/Support/SelfTest.swift:98`). En hardware AMD emite dos
  warnings esperados (`no SMC temperature keys`, `no power metrics`) porque
  VirtualSMC no publica esas claves.
- `./build/RyzenStatus --sensors` volca la telemetría del kext AMD.

## Build de la app

- `Package.swift` es SOLO para indexado del editor. La build real es `swiftc`
  directo en `build.sh`, con DOS invocaciones. Los puntos donde se editan las
  flags son `build.sh:94` (primer `swiftc`, inline) y `build.sh:210` (definición
  de `SWIFT_FLAGS`, consumida por el `swiftc` de `build.sh:214`). Cualquier flag
  va en AMBOS o no tiene efecto.
- Texto nuevo de usuario debe entrar en TODOS los idiomas o la build no compila.

## Build del kext

```sh
xcodebuild -project SMCAMDProcessor_Source/SMCAMDProcessor.xcodeproj \
  -target AMDRyzenCPUPowerManagement -configuration Release build
```

El proyecto se llama `SMCAMDProcessor.xcodeproj` (contiene los targets
`AMDRyzenCPUPowerManagement` y `SMCAMDProcessor`), y está **fuera de control de
versiones**: `.gitignore:40` ignora `*.xcodeproj`. O sea existe en la máquina del
mantenedor pero un clon limpio NO puede compilar el kext. Los fuentes sí están
versionados (`SMCAMDProcessor_Source/AMDRyzenCPUPowerManagement/`,
`SMCAMDProcessor/`, `Config/`).

**Corolario — el CI nunca compila el kext.** Por eso `.github/workflows/ci.yml`
tiene solo dos jobs: `Build & selftest` (macos-26 / Xcode 26, `ci.yml:10-11`) y
`SDK 15 fallback build` (macos-15 / Xcode 16, `ci.yml:53-55`). No hay ningún
`xcodebuild` de kext en el workflow, y no puede haberlo: el `.xcodeproj` no está
en el repo. Todo lo que sea kernel se valida a mano en el hardware del
mantenedor, nunca en CI.

La salida cae en `SMCAMDProcessor_Source/build/`, que `Tools/make-dmg.sh` prefiere
sobre el zip con SHA fijado. Ver la sección "TRAMPA de empaquetado" en
`hardware-safety.md` antes de empaquetar.

## Git y GitHub

- Staging explícito archivo por archivo. Nunca `git add -A`.
- Nunca commitear directo a `main`.
- `gh pr` / `gh issue` FUNCIONAN en este entorno — verificado con
  `gh pr list` (gh 2.100.0, devuelve el PR 43, exit 0). Un handoff anterior
  afirmaba que fallaban por ser GraphQL-backed; era una limitación del entorno de
  quien lo escribió, no de esta máquina. `gh api repos/{owner}/{repo}/pulls`
  sigue siendo válido si algún subcomando falla, pero no es obligatorio.

## Contratos que NO deben "simplificarse"

- `CPUSensorPacket` (304 B, selector 100) y `AMDFanCurveInput` (272 B, selector
  101) se serializan byte a byte de forma explícita. Dónde viven los tamaños:
  - `Sources/RyzenStatus/Services/AMD/CPUSensorPacket.swift:27` —
    `static let byteSize = 304`
  - `Sources/RyzenStatus/Services/AMD/AMDFanCurvePresets.swift:103` —
    `static let byteSize = 272`
  - Tests que los fijan: `Tests/MetricsTests.swift:6806` (304),
    `Tests/MetricsTests.swift:6862` y `:6916` (272).
  - Lado kernel, la comparación exacta:
    `SMCAMDProcessor_Source/AMDRyzenCPUPowerManagement/AMDRyzenCPUPMUserClient.cpp:1596`
    rechaza con `kIOReturnBadArgument` si `structureInputSize != sizeof(FanCurveInput)`.

  `AMDFanCurveInput.lut` es un array de Swift, así que
  `MemoryLayout<AMDFanCurveInput>.size` es 24, NO 272. Reemplazar la
  serialización por `withUnsafeBytes(of: input)` enviaría 24 bytes —un puntero—
  al kernel, y el kext lo rechazaría en `:1596`. Está verificado como correcto:
  no lo toques.
- Los helpers `kernelGet*` validan el tamaño devuelto y clampean con
  `min(count, outputSize / MemoryLayout<T>.size)`. Ése es el patrón seguro.

## Áreas ya auditadas — no re-descubrir

Tratar como correctas salvo evidencia nueva: cero fugas de mach port en los 8
sitios de ciclo de vida IOKit; correspondencia completa de selectores entre
`Core/AMDKextSelectors.swift` y el `switch` del kext (incluido el 103, bridging
térmico de dGPU); sin retain cycles (timers y bucles usan `[weak self]`);
conversión PWM raw→% `/255` y %→raw `*2.55` con `.rounded()` antes del cast.

La ausencia de notarización es política permanente y deliberada
(`.github/workflows/release.yml`), no un defecto.
