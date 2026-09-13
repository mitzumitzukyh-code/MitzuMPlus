# DATA_SOURCES · MitzuRouteArrows (EXPERIMENTAL)

Procedencia de los datos que empaqueta MitzuRouteArrows. Los datos de rutas y
de enemigos NO se duplican aquí: se leen de MitzuMPlus por `MitzuMPlusAPI`
(ver `MitzuMPlus/DATA_SOURCES.md`).

---

## Metadatos físicos por clon

| dataset | `g`, `sublevel`, `x`, `y` y `patrol` por `enemyIdx + cloneIdx` |
|---|---|
| fichero | `Data/MDTPhysicalGroupData.lua` |
| origen | ficheros de datos de **Mythic Dungeon Tools** (GPL-2.0) |
| transformación | `tools/generate_physical_group_data.py` |
| alcance | universo completo de clones de las 8 mazmorras con ruta nativa |
| dependencia en ejecución | **ninguna**; la fotografía viaja con MitzuRouteArrows |

El campo `g` conserva la agrupación visual/física declarada por MDT. No se
interpreta como grupo de combate, identidad de ruta ni `MATCH`. El universo
completo se empaqueta para poder demostrar cuándo un pull selecciona solo una
parte de un grupo (`PARTIAL_GROUP`).

---

## Nota de licencia

`Data/MDTPhysicalGroupData.lua` deriva de ficheros de datos de Mythic Dungeon
Tools, publicado bajo **GPL-2.0**, mientras que este repositorio declara MIT.
No se ha relicenciado nada en silencio: revisar el alcance de la GPL sobre estos
datos derivados antes de distribuir este addon.
