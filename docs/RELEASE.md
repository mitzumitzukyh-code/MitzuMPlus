# Release de MitzuMPlus

Solo **MitzuMPlus** se empaqueta. **MitzuRouteArrows es EXPERIMENTAL y no se
empaqueta ni se sube a CurseForge** en ningún caso.

> ## ⛔ BLOQUEO DE PUBLICACIÓN: LICENCIA
> MitzuMPlus **no se puede publicar en CurseForge** hasta resolver la licencia de
> los datos derivados de Mythic Dungeon Tools (**GPL-2.0**) frente a la licencia
> **MIT** del repositorio. Ver la [sección 6](#6-bloqueo-de-licencia). No se ha
> cambiado ninguna licencia para ocultar el problema.

---

## 1. Baseline validada en WoW real: `05a4d77`

| | |
|---|---|
| Commit | `05a4d77ea405a0c5918c2efd40e807ebd0f15886` (rama `refactor/split-core-routearrows`) |
| Versión | MitzuMPlus `7.13.0-rc1` · MitzuRouteArrows `0.1.0-dev` (ausente en la prueba) |
| Cliente | World of Warcraft Retail 12.1.0, build 69814, Interface 120100 |
| Estado | **CORE_LIVE_VALIDATED_BASELINE** |

Comprobado a mano en el cliente real, con MitzuRouteArrows ausente y MDT desactivado:

- Instalación limpia de `MitzuMPlus`; cero errores de Lua.
- Historial migrado desde `MitzuMPlus_Historial`: 38 runs conservadas. UI principal funcional.
- `OUTSIDE` correcto fuera de instancia.
- Estanques de Vida Rubí **sin piedra**: `dungeonKey=399`, `state=PRE_KEY`,
  `challengeActive=false`, `challengeMapID=nil`. No reaparece el falso inicio de M+.
- Ruta nativa `mitzu_399_standard` sin MDT: `routeLoadSource=BUNDLED_NATIVE`,
  `mdtRuntimeRequired=false`, `savedRouteDataRequired=false`; RouteProgress `PREPARED`.
- Al iniciar +2: `state=RUNNING`, `challengeActive=true`, `challengeMapID=399`,
  `keystoneLevel=2`, `identitySource=ACTIVE_CHALLENGE`, `routeState=ACTIVE`.
- RunSession crea el snapshot; `matchState=SESSION_MATCH`; `/emp next` y `/emp prev`
  funcionan; RouteProgress y snapshot sincronizados.
- `/reload` dentro de la M+: `state=RUNNING`, pull restaurado, `recovered=true`,
  `recoveryReason=SESSION_MATCH`, `restoreState=RESTORED`, `restoreReason=SESSION_MATCH`.
  Después, `/emp next` sigue funcionando y el snapshot se sigue actualizando.
- `/emp bugreport`: cero errores.

La secuencia es ahora la **prueba de regresión obligatoria**
`tests/core/BaselineRegression.spec.lua`. Para volver a esta baseline en el cliente,
reinstalar el zip de `05a4d77` (ver sección 7).

### Detalles observados en la baseline (analizados en 7.14.0-rc1)

| | Observado | Diagnóstico | Acción |
|---|---|---|---|
| A | `PRE_KEY` y luego `RESET -> RUNNING (CHALLENGE_MODE_START)` | Al insertar la piedra, el cliente dispara `CHALLENGE_MODE_RESET` (reinicio de instancia) antes de `CHALLENGE_MODE_START`. Solo lo escuchan `RunSession:Clear("RESET")` y un teardown vacío del Core; no hay run ni snapshot que perder. El estado final es correcto. | **Ninguna en DungeonContext/RunSession.** La secuencia real se reproduce en el test R1 y el invariante `CHALLENGE_IMPLIES_RUNNING` trata `RESET` como transitorio (WARN, no FAIL). |
| B | Tras restaurar el pull 2 y avanzar, `recoveryPull=4` | Solo diagnóstico: `RouteProgress:StatusLines` y `RouteManager:StatusLines` imprimían el pull ACTUAL con ese nombre. Nada histórico se sobrescribía; la autoridad no estaba afectada. | Corrección mínima: RouteProgress recuerda el pull restaurado (`GetRecoveryPull`) y los informes muestran `recoveryOriginalPull` + `currentPull`. Test R2. |

---

## 2. Qué trae `7.14.0-rc1`

**Por qué 7.14.0-rc1 y no sobrescribir 7.13.0-rc1:** hay funciones nuevas visibles
(Coach HUD V2, Bug Report V2, icono) con datos compatibles hacia atrás → sube la
versión menor. Es `rc1` porque aún no está validada en el cliente. `7.13.0-rc1`
queda intacta como baseline conocida.

- **Coach HUD V2** (`modules/CoachHUD.lua`): vista principal durante la llave. Lee a
  las autoridades; no guarda el pull. Sustituye al PullHUD (que queda como adaptador)
  y, por defecto, al overlay clásico del Coach en vivo (`hud.replaceClassic`).
- **Bug Report V2** (`modules/QA/*`): informe único copiable, caja negra de QA,
  invariantes PASS/WARN/FAIL, saneado de valores secretos y datos privados.
- **Icono nuevo** `Media/Icons/logo_64.tga` en la lista de addons, el botón del
  minimapa, la ventana principal y el HUD.
- Teclas de siguiente/anterior pull alineadas con `/emp pull`: mueven RouteProgress.
- Diagnóstico de recuperación corregido (detalle B).

---

## 3. Comprobaciones automáticas

```bash
python tests/run_lua_tests.py
```

```bash
python tests/run_static_checks.py
```

```bash
git diff --check
```

Las tres tienen que terminar con 0 fallos. Resultado en `7.14.0-rc1`: ver
`CHANGELOG.md` (tests, aserciones y comprobaciones).

## 4. Paquete

```bash
python tools/package_mitzumplus.py --check
```

Genera `dist/MitzuMPlus-<versión>.zip` (versión de `## Version` del `.toc`) y lo valida:

- una única carpeta raíz `MitzuMPlus/` con `MitzuMPlus.toc`;
- cada fichero que nombra el `.toc` está en el zip;
- incluye `LICENSE`, `DATA_SOURCES.md` y `Bindings.xml`;
- no incluye `tests/`, `docs/` (con el PNG fuente del logo), `tools/`, `.git`, CI,
  capturas, temporales ni nada de MitzuRouteArrows.

`dist/` está en `.gitignore`.

### Icono

Fuente: `docs/assets/logo/mitzu_logo_source.png` (1254×1254 RGBA, fuera del paquete).
Conversión reproducible:

```bash
python tools/convert_logo.py
```

Recorta un cuadrado centrado en el emblema (+7 % de margen), escala a 64×64 con
Lanczos y un enfoque suave, y escribe TGA sin compresión, 32 bpp, origen abajo-
izquierda (el mismo formato que las demás texturas del addon). Las texturas antiguas
`1_addon.tga` y `10_minimap.tga` se retiraron (siguen en el historial de git).

---

## 5. Prueba en vivo controlada de `7.14.0-rc1`

La instalación validada de `7.13.0-rc1` **no se sustituye automáticamente**. Migración
controlada, con WoW cerrado:

1. Backup de `Interface/AddOns/MitzuMPlus` y de `WTF/Account/<CUENTA>/SavedVariables/MitzuMPlus.lua`.
2. Borrar `Interface/AddOns/MitzuMPlus` e instalar el zip nuevo en una carpeta limpia.
3. **No hay que renombrar SavedVariables**: `7.14` usa los mismos ficheros y variables.
   Los ajustes nuevos (`profile.settings.hud`) se añaden con valores por defecto; no
   se borra ninguna configuración antigua.

### Secuencia mínima

Filosofía: **jugar normalmente → `/emp bugreport` → copiar un único informe.**

| Paso | Qué hacer | Qué debería verse |
|---|---|---|
| 1 | Entrar al juego | Icono nuevo en la lista de addons y el minimapa; sin errores |
| 2 | `/emp hud test` | HUD con **PREVIEW** y datos de ejemplo; arrastrarlo a su sitio |
| 3 | `/emp hud test off` | El HUD vuelve al estado real (oculto fuera de mazmorra) |
| 4 | Entrar a una mazmorra de la temporada | HUD en modo preparación: `PULL 1 / N`, `PREPARACIÓN` |
| 5 | Poner la piedra y jugar | HUD completo: reloj, pull, ruta, siguiente pull, Coach |
| 6 | Avanzar pulls con la tecla o `/emp next` | El HUD cambia al instante |
| 7 | `/reload` a mitad | El HUD vuelve **solo** al pull correcto (tras "recuperando la sesión") |
| 8 | Al terminar (o ante cualquier cosa rara) | `/emp bugreport` → Ctrl+A, Ctrl+C → pegar el informe entero |

`/emp bugreport status` da un resumen de una línea (invariantes y errores) si no se
quiere abrir la ventana.

### Pendiente de validar en vivo

- Aspecto y legibilidad del HUD en combate, con distintos UI scale y resoluciones.
- Anclaje/arrastre, bloqueo y escala del HUD en el cliente real.
- Que el overlay clásico no aparezca con `replaceClassic=true` y sí con `false`.
- Recomendación del Coach con una run real (en los bancos no se crea la run del Core).
- Copia del informe desde la caja de copia y ausencia del aviso de valores secretos.
- Icono en lista de addons, minimapa (máscara redonda) y barra de título.
- Teclas de siguiente/anterior pull asignadas en Key Bindings.

---

## 6. BLOQUEO DE LICENCIA

**Estado: SIN RESOLVER. Impide la publicación pública.**

El repositorio declara **MIT** (`LICENSE`). Estos ficheros **derivan de datos de
Mythic Dungeon Tools, publicado bajo GPL-2.0**:

| Addon | Fichero | Contenido derivado |
|---|---|---|
| MitzuMPlus (se empaqueta) | `data/Routes/Season2/KingsRest.lua` | ruta `KR - Pug Friendly` |
| | `data/Routes/Season2/TempleOfSethraliss.lua` | ruta `elitzur_temple_1` |
| | `data/Routes/Season2/RubyLifePools.lua` | ruta `elitzur_rlp_1` |
| | `data/Routes/Season2/BlindingVale.lua` | ruta `Peon BV` |
| | `data/Routes/Season2/VoidscarArena.lua` | ruta `elitzur_voidscar_1` |
| | `data/Routes/Season2/DenOfNalorakk.lua` | ruta `Tactyks PUG Friendly` |
| | `data/Routes/Season2/MurderRow.lua` | ruta `Peon MR` |
| | `data/Routes/Season2/AltarOfFangs.lua` | ruta `elitzur_altar_1` |
| | `data/MDTEnemyData.lua` | npcID, tropas y clones por enemigo (MDT 6.2.15) |
| MitzuRouteArrows (no se empaqueta) | `Data/MDTPhysicalGroupData.lua` | grupo, subnivel, x/y y patrulla por clon |

`data/Routes/Season2/Registry.lua` es código propio, no datos derivados.

La procedencia está anotada en cada fichero (`source.dataOrigin`,
`source.originalRouteID`) y en `DATA_SOURCES.md` de cada addon. Antes de publicar
hay que decidir **explícitamente** una de estas vías y documentarla: relicenciar el
proyecto de forma compatible, obtener permiso de los autores de los datos, o
sustituir esos datos por datos propios no derivados. Esta tarea no toma esa decisión.

---

## 7. Migración desde `MitzuMPlus_Historial` (solo si se viene de 7.12 o anterior)

| Qué | Efecto | Qué hacer |
|---|---|---|
| SavedVariables | WoW busca `SavedVariables/MitzuMPlus.lua`; el historial está en `MitzuMPlus_Historial.lua` | copiarlo con el nombre nuevo, con el juego cerrado; las variables no cambian |
| Carpeta antigua | quedarían dos addons cargados | retirar `Interface/AddOns/MitzuMPlus_Historial` |
| Tecla de la pestaña de historial | renombrada a `MitzuMPlus_HistoryTabBinding` | volver a asignarla |
| Tecla de marcar objetivo | es de MitzuRouteArrows (mismo nombre de binding) | nada si se usa MitzuRouteArrows |
| Ajustes de flechas | quedan sin uso en `MPlusAdaptiveRouteDB` | nada; no se borran |
| Posición del PullHUD (7.13) | el HUD V2 la copia una vez a `hud.point/x/y` | nada; el original no se borra |

---

## 8. Riesgos conocidos

### Funcionales
1. **Teclas de pull:** ahora mueven RouteProgress (antes solo PullNavigator). Es el
   comportamiento de `/emp pull`, pero es un cambio visible para quien las usaba.
2. **Overlay clásico sustituido por defecto** (`hud.replaceClassic=true`). Con él
   oculto, el tracker de Blizzard queda visible (el overlay clásico lo ocultaba).
   `overlayEnabled` no se toca; el overlay vuelve poniendo `replaceClassic=false`.
3. **Estado "recuperando la sesión":** tras un `/reload`, el HUD no muestra número hasta
   que RunSession decide (hasta ~20 s si el cronómetro del servidor tarda).
4. `PullNavigator` puede divergir de RouteProgress si algo lo mueve directamente; el
   invariante `NAVIGATOR_FOLLOWS_PROGRESS` lo marca como WARN.
5. `MitzuMPlus.INITIALIZED` nunca se pone a `true`; `IsReady()` usa la base de datos.
6. Con `replaceClassic=true`, la tecla `MITZUMPLUS_OVERLAY`, `/emp coach` y los botones
   del bloque "COACH EN VIVO" siguen controlando el overlay **clásico**, que durante la
   llave no se pinta (sí su vista previa). El HUD V2 se controla con `/emp hud` y su
   bloque en la pestaña Coach.

### UI
1. El HUD y el nuevo bloque del panel Coach solo se han probado en el cliente simulado.
2. El rediseño del Historial (desplegable, filtros, columnas) **no está en esta rama**:
   vive en `0fb32ba` (`chore: sync active addon state`) mezclado con ruido. No se
   cherry-pickeó; va en un PR propio.
3. Legibilidad del icono a tamaños muy pequeños (lista de addons) pendiente de ver.

### API de Midnight
1. Nombres de mobs: no hay API por npcID sin unidad. El HUD muestra conteos y tropas
   de la ruta, no nombres.
2. Fuerzas oficiales: el HUD solo las muestra con total conocido; si Blizzard las
   devuelve secretas o incompletas, la línea no aparece.
3. La recomendación del Coach exige `hasBasis` de PredictionEngine; al principio de
   la llave es normal que no haya ninguna.

### Valores secretos
1. El saneado depende de `issecretvalue`. Si Blizzard marca como secreto algo que hoy
   no lo es, sale `SECRET` en el informe y la línea desaparece del HUD (degradación
   deseada), pero no está probado en vivo.
2. El HUD no escanea placas ni mobs, lo que elimina la principal fuente de secretos.

### Licencia
1. **Bloqueo de publicación** (sección 6). Sin resolver.

### Pendiente de prueba en vivo
Todo lo listado en la sección 5 ("Pendiente de validar en vivo").

### MitzuRouteArrows (no se publica)
Sin cambios en esta versión. Sigue **EXPERIMENTAL_CONTINUE_LIVE_TESTING**; sus bancos
pasan contra `7.14.0-rc1` (el contrato `MitzuMPlusAPI` v1 no cambió).

## 9. Publicar

No automatizado y **bloqueado** mientras siga abierta la sección 6. Con la licencia
resuelta y la sección 5 completada, el zip se subiría a mano como *Beta*.
