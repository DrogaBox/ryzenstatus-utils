# Changelog

## [1.0.2]

- Agregada detección dinámica de CPUs: ahora diferencia correctamente entre procesadores antiguos (Legacy P-States en Zen/Zen+) y modernos (CPPC en Zen 2+).
- Solucionado un crash crítico (Actor isolation) al acceder a la configuración de P-States en arquitecturas recientes.
- Eliminados rastros de la marca antigua (Vorssaint) en la ventana de actualizaciones.

## [1.0.1]

- Fixed an issue where CPU core frequencies were displaying as 0 MHz.
- Added CCD temperature readings to the main monitoring dashboard.
- Updated the update checker repository to point to DrogaBox/ryzenstatus-utils.
- Added high-resolution application icons.

## 1.0.0

- Initial release of RyzenStatus
