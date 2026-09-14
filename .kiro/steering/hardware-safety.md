# Reglas de seguridad de hardware — NO negociables

Este proyecto controla ventiladores físicos vía un kext. El lazo de control es
open-loop: no hay realimentación por RPM. Un PWM por debajo del umbral de
arranque del rotor cala el ventilador de forma silenciosa y sin detección.

Un error acá no se manifiesta como excepción ni como test rojo. Se manifiesta
como silicio sobrecalentado.

## El hardware de referencia es ITE, no Nuvoton

La máquina del mantenedor es una **ASUS ROG Crosshair VII Hero (X470)** y su Super
I/O es de la familia **ITE IT86XXE**, no Nuvoton. Está verificado: los seis nombres
que imprime `--sensors` coinciden exactos con `kFAN_READABLE_STRS` en
`ISSuperIOIT86XXEFamily.hpp`, y ninguno de los dos drivers NCT tiene tabla de
nombres.

Esto invierte una conclusión de la auditoría previa, que dio los huecos de ITE por no
testeables "porque la placa es Nuvoton". Es al revés: los huecos de ITE —
tacómetros sin validación, `activeFansOnSystem` fijo en 6, el constructor que muta
el registro `0x0c` sin compuerta de privilegio, la ausencia de manejo de bancos —
corren en el hardware de referencia en cada arranque. Los drivers Nuvoton son los
que no se pueden probar acá.

El detalle técnico completo está en `docs/SUPERIO.md`.

## Un canal de ventilador puede ser una BOMBA

En la placa de referencia uno de los seis canales es `AIO_PUMP`. Los nombres del
driver (`CPU Fan`, `System 3 Fan`, …) están hardcodeados y **no** se leen de la
placa, así que nada en la UI distingue una bomba de un ventilador.

Una bomba va al 100 %. Estrangularla baja el caudal y sube la temperatura bajo
carga, o sea el efecto opuesto al de una curva. Y el piso que existe no la protege:
`kCURVE_MIN_ACTIVE_PWM = 40` (15.7 %) es sensato para un ventilador y demasiado
bajo para una bomba, y el guard de emergencia solo actúa a ≥85 °C, cuando el daño
térmico ya empezó.

El Super I/O no puede distinguirlas: las dos son una salida PWM con tacómetro. O
sea **no se arregla en el driver**, tiene que saberlo quien configura la curva.
Regla: identificar el canal de la bomba y dejarlo en control de BIOS.

Y un tacómetro mal leído lo empeora: una bomba que reporta 40 RPM parece calada
para toda heurística basada en RPM —el piso de arranque de rotor del selector 95, y
cualquier detector de ventilador congelado— así que una bomba sana dispara todos
los falsos positivos a la vez.

## Herramientas: esto es macOS, no Linux

Errores que ya se cometieron en esta sesión y no hay que repetir:

- `dmesg` **no sirve**. En macOS moderno el logging del kernel se fue a `os_log` y
  devuelve vacío. Los `IOLog` del kext se leen con
  `log show --last boot --predicate 'eventMessage CONTAINS "chip identified"'`.
- `log show` está **bloqueado para el agente** (`Cannot run while sandboxed`). Es
  un comando del mantenedor, no algo que se pueda automatizar desde acá.
- `timeout` no existe (es de coreutils). Usar `perl -e 'alarm N; exec @ARGV' …`.
- El kext **no publica** el chip Super I/O en el IORegistry, así que `ioreg`
  tampoco lo dice. Si hace falta el ID sin el log, se infiere del comportamiento —
  el método está en `docs/SUPERIO.md`.

## Instalar un kext: la EFI viva no es la única

La máquina de referencia tiene **dos** particiones EFI (`disk0s3` y `disk1s1`) y
ninguna se monta sola. Además hay copias de respaldo de árboles EFI en discos de
datos que parecen la real. Copiar a la equivocada produce el peor síntoma posible:
todo parece haber salido bien y el kext viejo sigue cargado.

Procedimiento verificado:

```sh
sudo diskutil mount disk1s1        # queda en /Volumes/NO NAME
# identificar cuál es la viva por la versión que ya tiene instalada:
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "/Volumes/NO NAME/EFI/OC/Kexts/AMDRyzenCPUPowerManagement.kext/Contents/Info.plist"
```

La EFI se monta con el usuario como dueño (`drwx------ droga staff`), así que
copiar **no** necesita `sudo`; montarla sí. Respaldar los kexts que están antes de
sobrescribir, y verificar cuatro cosas después: versión, presencia del binario,
hash idéntico al origen (una copia truncada en FAT es el modo de fallo real) y
`codesign --verify --deep --strict`. Después `sync` dos veces, porque una escritura
en FAT puede quedar en caché.

Revisar también que `config.plist` liste los dos kexts con `Enabled=true` y el
`ExecutablePath` correcto: un kext presente pero deshabilitado se ve idéntico a uno
bien instalado hasta que rebooteás.

## El bump de versión es una herramienta de depuración

Ya se cobró dos veces en una sola sesión. Dos binarios distintos con el mismo
número son indistinguibles para `kextstat`, y entonces un probe fallido no se puede
separar de "cargó el binario viejo". Bumpear **antes** de cada build de prueba, no
al publicar. Un `kextstat` que confirma la versión esperada es el paso 0 de
cualquier medición, y sin él todo lo que se mida después es ruido.

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
  binarios distintos con el mismo número —dos builds separados llegaron a compartir
  `3.34.13`— y entonces `kextstat` no puede distinguirlos: ahí no hay forma de saber
  qué está corriendo. Ése es el argumento fuerte para bumpear antes de probar, no
  después.

## `--sensors` NO es una herramienta de observación inocente

`clientClose()` (`AMDRyzenCPUPMUserClient.cpp:82-118`) libera **los seis**
ventiladores a BIOS en cuanto CUALQUIER cliente cierra — no solo los que ese
cliente seteó:

```cpp
for (int i = 0; i < fanCount; i++) {
    provider->fanToCurveMap[i] = -1;
    provider->superIO->setDefaultFanControl(i);
    provider->lastAppliedPWM[i] = 0;
}
IOLog("... clientClose released %d fan(s) to BIOS control\n", fanCount);
```

`./build/RyzenStatus --sensors` abre y cierra un cliente, así que cada corrida:

1. **Destruye el estado del probe**: un ventilador en manual vuelve a BIOS, y una
   curva activa se desmapea (se re-sube por los selectores 101/102 en la próxima
   conexión). El experimento se reinicia en silencio.
2. **Contamina la evidencia del probe 1**: escribe su propia línea
   `clientClose released` en el log del kernel, indistinguible de la que produce
   el `pkill -9`. Correr `--sensors` antes del SIGKILL fabrica un falso positivo.

Regla: durante los probes 1-3, el duty y el RPM se leen en la UI de la app, nunca
por CLI. `--sensors` sirve antes de empezar y después de cerrar, no en el medio.

## Probe 2 tenía DOS rutas al mismo falso positivo

La de privilegio sigue vigente y está en la lista de probes.

La segunda ya **no** aplica, y conviene saber por qué existía. Mientras el camino
del duty estaba roto, los seis ventiladores leían `pwm 0 (0.0%)` incluso en la UI,
así que no había ningún readout que confirmara que la curva se había aplicado. Si el
ralentí de BIOS de un ventilador se parecía al que produce el piso (PWM 40 =
15.7 %), entonces "curva aplicada al piso" y "curva que nunca se subió" eran
indistinguibles, y probe 2 había que partirlo en dos tramos para tener una señal.

Desde el kext 3.34.16 el duty se lee de verdad —confirmado en silicio, los seis
canales reportan el valor real del firmware— así que probe 2 vuelve a ser un solo
tramo con readout confiable. Si alguna vez el duty vuelve a leer `0` en todos los
canales a la vez, ése es el síntoma de que el camino se rompió otra vez, y hay que
sospechar primero de los contadores de los selectores 93 y 94.

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
prueba para la validación en hardware. El defecto era que fuera SILENCIOSO. Ahora
el script informa la procedencia y la versión de lo que realmente empaquetó:

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
