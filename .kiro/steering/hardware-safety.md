# Reglas de seguridad de hardware — NO negociables

Este proyecto controla ventiladores físicos vía un kext. El lazo de control es
open-loop: no hay realimentación por RPM. Un PWM por debajo del umbral de
arranque del rotor cala el ventilador de forma silenciosa y sin detección.

Un error acá no se manifiesta como excepción ni como test rojo. Se manifiesta
como silicio sobrecalentado.

## Invariantes

- Cualquier cambio en `SMCAMDProcessor_Source/` invalida el kext empaquetado y
  obliga a revalidar en hardware. No se toca sin decisión explícita del
  mantenedor.
- El bump de versión del kext, el refresh de `ReleaseAssets/*.zip` y el repin del
  SHA ocurren SOLO después de que pasen los probes de hardware. Nunca antes. Un
  artefacto con hash fijado que nadie corrió en silicio es una trampa.
- PWM 0 significa "liberar el ventilador a la BIOS/SmartFan". Ese es el
  mecanismo correcto para 0-RPM real. Un duty ínfimo distinto de 0 NO lo es.
- Ningún duty distinto de 0 queda por debajo del umbral de arranque: piso
  `kCURVE_MIN_ACTIVE_PWM = 40` en modo curva (kernel) y
  `AMDFanSafety.minimumManualPWM = 40` en modo manual (Swift).
- El piso de duty se aplica donde el usuario comanda un valor, nunca a valores
  heredados del hardware: `AMDFanSafety.guardOnlyPWM` existe para eso y el lazo
  de enforcement debe usarlo. No lo "arregles" moviendo el piso ahí — subiría
  ventiladores que ya giran bien y haría la máquina más ruidosa sin ganancia.
- Una lectura de temperatura fallida NUNCA debe ser indistinguible de 0 °C. Un
  fallo que devuelve `0.0f` selecciona `lut[0]` (el duty más bajo) y a la vez
  hace falso todo test `>= 85`, o sea desarma el guard de emergencia en el mismo
  movimiento. El guard se arma desde el sensor más caliente del sistema, no desde
  la fuente de la curva.
- **El DMG puede llevar kexts locales sin verificar.** No es hipotético: es el
  comportamiento por defecto en la máquina del mantenedor. Antes de instalar o de
  publicar hay que confirmar con `kextstat | grep -i ryzen` QUÉ versión quedó
  realmente cargada, no cuál se creía empaquetar. Sin el bump de versión hay
  binarios distintos con el mismo número —S9d y S10 comparten `3.34.13`— y
  entonces `kextstat` no puede distinguirlos: ahí no hay forma de saber qué está
  corriendo. Ése es el argumento fuerte para bumpear antes de probar, no después.

## Dónde vive el estado de versión (verificado en este árbol)

- Versión del kext: `SMCAMDProcessor_Source/Config/Version.xcconfig` líneas 10-11
  (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`). Los `Info.plist` de los kexts
  usan `$(MARKETING_VERSION)`, no literales — bumpear el xcconfig, no los plist.
- SHA fijado del zip: `Tools/make-dmg.sh:58` (`EXPECTED_SHA`).
- Versión de la app: `Resources/Info.plist:40`.

## TRAMPA de empaquetado — leer antes de correr `make-dmg.sh`

El `EXPECTED_SHA` vive DENTRO del `if [[ ! -d "$KEXT_DRIVER" || ! -d
"$KEXT_PLUGIN" ]]` (`Tools/make-dmg.sh:57-69`, con el `EXPECTED_SHA` en `:58`),
así que la compuerta del SHA corre solo cuando
`SMCAMDProcessor_Source/build/dmg-kexts/` NO existe. `build/` está en
`.gitignore`, de modo que un build local de kext deja artefactos que **saltean por
completo la compuerta**: `git status` limpio, estado versionado en una versión, y
el DMG llevando otra.

Ese camino local es legítimo — es cómo un kext nuevo llega a la máquina de
prueba para la validación en hardware. El defecto era que fuera SILENCIOSO. Desde
S11 el script informa la procedencia y la versión de lo que realmente empaquetó:

```
  ✓ AMDRyzenCPUPowerManagement.kext 3.34.14 added to DMG
  ⚠ Source: LOCAL BUILD (SMCAMDProcessor_Source/build/dmg-kexts/) — SHA gate NOT applied.
```

frente al camino verificado:

```
  ✓ AMDRyzenCPUPowerManagement.kext 3.34.13 added to DMG
    Source: ReleaseAssets zip, SHA-256 verified.
```

LEER esas dos líneas es ahora parte del procedimiento. Un DMG que dice
`LOCAL BUILD` no se publica: sirve para probar en silicio, nada más.

En CI la compuerta sí actúa: `ci.yml` corre `Package DMG` sobre un clon limpio,
donde `build/` no existe, así que siempre toma el camino del zip fijado. La
trampa es exclusivamente local.

Si esos kexts locales no pasaron los probes y no querés empaquetarlos, mové el
build fuera del árbol antes de correr el script (no lo borres a ciegas: son los
artefactos que necesita la validación).

## Probes obligatorios tras instalar un kext nuevo, en este orden

0. `kextstat | grep -i ryzen` confirma la versión esperada.
1. **Dead-man**: ventilador en manual → `pkill -9 RyzenStatus` →
   `dmesg | grep "clientClose released"`, y el ventilador vuelve a BIOS.
   Sirve de canario: si la línea no aparece, PARAR — puede ser el kext viejo, y
   no se puede distinguir "dead-man roto" de "binario equivocado".
2. **Piso de PWM**: curva con ancla al 1 % en idle → el ventilador gira ≈15 %,
   nunca calado. Antes de medir, confirmar que la app no reporte
   `privilegeError`: sin privilegio (root o `-amdpnopchk`) la curva nunca sube,
   el ventilador queda en BIOS auto rondando el 15 % y ése es exactamente el
   número esperado — un falso positivo perfecto.
3. **Guard con fuente GPU**: curva con `sourceSensor = GPU` + CPU >85 °C con la
   dGPU en idle → el duty debe subir a >=200.

La revisión de código NO sustituye estos probes. Ninguna cantidad de análisis
estático convierte "código correcto" en "comportamiento seguro sobre silicio".
