# Protocolo de ejecución y reporte

- Los bloques de anclaje se aplican con coincidencia BYTE A BYTE. Si un anclaje
  no coincide, DETENERSE y reportar. No reindentar, no normalizar comillas, no
  "arreglar" el anclaje.
- Verificar que cada anclaje sea ÚNICO en el árbol antes de aplicarlo. Varios
  archivos de este repo comparten bloques idénticos (p. ej. los bucles de poll de
  `AutoEppService` y `C6ResidencyService`, o `syncWithPreferences` en
  `AppVolumeMixer` y `AudioInputDeviceManager`).
- Un ítem a la vez, con build limpio entre cada uno.
- No inventar identificadores: todo lo referenciado existe o se crea en el mismo
  parche.
- Si un ítem no se hace, o se hace distinto, DECIRLO explícitamente con la razón.
  Un ítem omitido y declarado es trivial de manejar; uno omitido y reportado como
  hecho cuesta una ronda entera de revisión.

## Formato de reporte obligatorio

- SHA completo del commit y la rama.
- Por cada cambio: `archivo:línea`. No prosa descriptiva.
- Salida CRUDA de los comandos de verificación, no un resumen. "build limpio" es
  una afirmación; `grep -E "error|warning"` con salida vacía es evidencia.
- Distinguir siempre lo verificado de lo supuesto. Nunca afirmar que algo compila
  o corre sin haberlo ejecutado.
