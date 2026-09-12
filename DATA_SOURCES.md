# DATA_SOURCES

Procedencia de los datos que MitzuMPlus empaqueta. Nada aquí se genera a mano:
todo sale de una herramienta reproducible y se puede regenerar.

---

## Rutas nativas de la temporada 2

| dataset | 8 rutas de Mythic+, temporada 2 de Midnight |
|---|---|
| ficheros | `data/Routes/Season2/*.lua` |
| formato | MitzuRoute v1 (`modules/RouteSchema.lua`) |
| origen | rutas públicas de **Mythic Dungeon Tools**, importadas por el usuario y normalizadas |
| licencia del origen | MDT se publica bajo **GPL-2.0** |
| transformación | `notas/_tools/export_native_routes.py` → `RouteSchema.FromLegacyProfile` |
| comprobado | 2026-09-09 |
| dependencia en ejecución | **ninguna**. MDT no hace falta para cargar ni jugar estas rutas |

| dungeonKey | mazmorra | ruta original | pulls | clones | válidos |
|---|---|---|---|---|---|
| 249 | Kings' Rest | `KR - Pug Friendly` | 15 | 96 | 87 |
| 250 | Temple of Sethraliss | `elitzur_temple_1` | 11 | 114 | 83 |
| 399 | Ruby Life Pools | `elitzur_rlp_1` | 11 | 86 | 77 |
| 584 | The Blinding Vale | `Peon BV` | 14 | 130 | 124 |
| 585 | Voidscar Arena | `elitzur_voidscar_1` | 11 | 107 | 102 |
| 586 | Den of Nalorakk | `Tactyks PUG Friendly` | 17 | 103 | 99 |
| 587 | Murder Row | `Peon MR` | 13 | 160 | 155 |
| 588 | Altar of Fangs | `elitzur_altar_1` | 12 | 111 | 103 |
| | **total** | | **104** | **907** | **830** |

Los 77 clones "sin resolver" tienen un `cloneIdx` mayor que el número de clones
que declara `data/MDTEnemyData.lua` para ese enemigo. Es la fotografía de datos
la que se quedó corta, no las rutas: se marcan como `UNRESOLVED_CLONE_INDEX`
(WARNING) y la ruta sigue siendo utilizable. Se corrigen regenerando la foto,
nunca alterando los índices de la ruta para que encajen.

---

## Datos de enemigos

| dataset | npcID, tropas y número de clones por enemigo |
|---|---|
| fichero | `data/MDTEnemyData.lua` |
| origen | ficheros de datos de **Mythic Dungeon Tools** 6.2.15 (GPL-2.0) |
| motivo | `MDT.dungeonEnemies` no es accesible en ejecución; ver la cabecera del fichero |
| contraste | `MythicDungeonToolsAPI:GetEnemyForces()` cuando MDT está instalado |
| dependencia en ejecución | **ninguna**; MDT solo sirve para contrastar |

---

## Metadatos físicos por clon

| dataset | `g`, `sublevel`, `x`, `y` y `patrol` por `enemyIdx + cloneIdx` |
|---|---|
| fichero | `data/MDTPhysicalGroupData.lua` |
| origen | ficheros de datos de **Mythic Dungeon Tools** (GPL-2.0) |
| transformación | `tools/generate_physical_group_data.py` |
| alcance | universo completo de clones de las 8 mazmorras con ruta nativa |
| dependencia en ejecución | **ninguna**; la fotografía viaja con MitzuMPlus |

El campo `g` conserva la agrupación visual/física declarada por MDT. No se
interpreta como grupo de combate, identidad de ruta ni `MATCH`. El universo
completo se empaqueta para poder demostrar cuándo un pull selecciona solo una
parte de un grupo (`PARTIAL_GROUP`).

---

## Rotación de la temporada

| dataset | las 8 mazmorras de Midnight temporada 2 |
|---|---|
| origen | Blizzard — *Midnight Season 2 is Now Live!* |
| resolución | en ejecución vía `C_ChallengeMode.GetMapTable()`, no escrita a mano |

---

## Nota de licencia

Los datos de rutas y de enemigos proceden de Mythic Dungeon Tools, publicado
bajo **GPL-2.0**. La procedencia se conserva en cada ruta empaquetada
(`source.dataOrigin` y `source.originalRouteID`) y en las cabeceras generadas.
No se ha relicenciado nada en silencio.

Si vas a distribuir MitzuMPlus públicamente, revisa con el mantenedor el
alcance de la GPL sobre estos datos derivados antes de publicar.

**`dataOrigin = "MDT"` no significa `runtimeDependency = "MDT"`.** La primera
dice de dónde salieron los datos; la segunda, si hace falta el addon ahora.
`mdtRuntimeRequired` es `false`.
