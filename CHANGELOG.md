# Changelog

Dos addons, dos historiales. Las versiones marcan la diferencia de estabilidad:
MitzuMPlus es un candidato a release; MitzuRouteArrows es desarrollo (`-dev`).

El historial anterior a la separación está en `docs/history/CHANGELOG_legacy.txt`.

## MitzuMPlus

### 7.14.0-rc1 — Coach HUD V2, Bug Report V2 e icono

Release candidate **pendiente de prueba en vivo**. Construida sobre la baseline
`05a4d77` (7.13.0-rc1) validada en WoW real. **Publicación bloqueada** por la
licencia de los datos derivados de MDT (`docs/RELEASE.md` §6).

**Nuevo**
- **Coach HUD V2** (`modules/CoachHUD.lua`): vista principal durante la llave, con
  mazmorra y nivel, reloj del servidor, `PULL x / N`, % planificado de ruta, pull
  actual, siguiente pull y recomendación del Coach solo cuando hay evidencia.
  Visibilidad por ciclo de vida (oculto / preparación / completo / resumen).
  Se reconstruye solo tras `/reload`, sin volver a pull 1 mientras se recupera.
  Vista previa `/emp hud test` con datos de ejemplo marcados PREVIEW.
  Ajustes: activar, bloquear, escala, opacidad, compacto, posición (también en la
  pestaña Coach). Sustituye al PullHUD y, por defecto, al overlay clásico del Coach.
- **Bug Report V2** (`/emp bugreport`): un informe copiable con build, contexto,
  jugador, grupo anonimizado, ruta, sesión, HUD, Coach, capacidades, invariantes
  PASS/WARN/FAIL, caja negra y errores. Cada sección es independiente y el informe
  nunca lanza. `status` y `clear` como sub-comandos.
- **Caja negra de QA** (`modules/QA/FlightRecorder.lua`): anillo de 200 hechos de
  alto nivel que sobrevive al `/reload`.
- **Saneado copy-safe** (`modules/QA/SafeValue.lua`): valores secretos → `SECRET`,
  sin rutas locales, BattleTags, GUIDs ni el escape `|`.
- **Icono nuevo** `Media/Icons/logo_64.tga` (lista de addons, minimapa, ventana, HUD);
  conversión reproducible `tools/convert_logo.py`. Retirados `1_addon.tga` y `10_minimap.tga`.

**Cambiado**
- Las teclas de siguiente/anterior pull mueven RouteProgress (como `/emp pull`);
  antes movían solo PullNavigator.
- La regla de prioridad del Coach vive en `modules/CoachAdvice.lua`, compartida por el
  overlay clásico (mismo texto) y el HUD (exige base de proyección).
- La caja de copia de `Export` acepta título, ayuda, fuente monoespaciada, botón de
  limpiar y desactivar el auto-cierre; un cierre programado ya no cierra una ventana
  abierta después.

**Corregido**
- Diagnóstico de recuperación: `recoveryPull` mostraba el pull ACTUAL tras avanzar.
  Ahora `recoveryOriginalPull` (restaurado) y `currentPull` (actual). Solo diagnóstico.

**Analizado sin cambios**
- `PRE_KEY -> RESET -> RUNNING` al insertar la piedra: secuencia real de Blizzard
  (`CHALLENGE_MODE_RESET` antes de `CHALLENGE_MODE_START`), resultado correcto.

**Pruebas**
- 240 tests, 2823 aserciones, 1601 comprobaciones estáticas, 134 ficheros Lua, 0 fallos
  (baseline: 204 / 2399 / 1416 / 125).
- Nuevos bancos: `CoachHUD`, `BugReport`, `BaselineRegression` (regresión obligatoria
  de la secuencia validada en vivo). Cliente simulado con cronómetro del servidor,
  tickers reales y `/reload` con SavedVariables.

### 7.13.0-rc1 — separación del core

**Validada en WoW real** (Retail 12.1.0, build 69814): baseline `05a4d77`. Ver
`docs/RELEASE.md` §1.

Release candidate. Sin funciones nuevas: esta versión separa, limpia y prueba.

**Cambios que afectan a quien actualiza**
- La carpeta y el `.toc` pasan de `MitzuMPlus_Historial` a `MitzuMPlus`. Las SavedVariables
  (`MitzuMPlusDB`, `MPlusAdaptiveRouteDB`) conservan sus nombres, pero el fichero de WoW
  cambia de nombre: hay que copiarlo una vez (ver `docs/RELEASE.md`).
- La tecla de la pestaña de historial se renombra a `MitzuMPlus_HistoryTabBinding`.
- Salen del core, al addon experimental MitzuRouteArrows: flechas de ruta, anclaje a placas
  (Threat Plates, Plater, ElvUI), resolutores de unidades, Guidance, Evidence Layer,
  Alignment, ArrowDemo y sus 23 comandos `/emp`, y la tecla de marcar objetivo.

**Interno**
- Nueva API pública de solo lectura `MitzuMPlusAPI` (`API/PublicAPI.lua`, contrato v1):
  getters, copias profundas, eventos saneados después del core, proxy no escribible.
- Eliminado `_G.MitzuMPlusEventBus`, que dejaba el bus interno escribible desde cualquier addon.
- `RuntimeCapabilities`, `RouteManager`, `Keybindings`, `AdaptiveRoute/Bootstrap`,
  `ProfileManager` y `DataStructure` ya no conocen módulos experimentales.
- Rutas de texturas y metadatos del `.toc` corregidos para la carpeta nueva.
- `.toc` preparado para CurseForge: `Title`, `Notes` (EN/ES), `Author`, `IconTexture`,
  `OptionalDeps: MythicDungeonTools, LibSharedMedia-3.0`.

**Pruebas**
- Cliente de WoW simulado que carga el addon por su `.toc` real y juega una llave.
- Bancos de core standalone, contrato de la API y datos de ruta; comprobaciones estáticas
  de dependencias; script de empaquetado con validación (`tools/package_mitzumplus.py`).

## MitzuRouteArrows

### 0.1.0-dev — primer corte como addon aparte

EXPERIMENTAL / IN DEVELOPMENT / NOT READY FOR CURSEFORGE.

- Todo el trabajo experimental de guía visual, movido desde MitzuMPlus sin cambiar su lógica.
- Lee MitzuMPlus solo por `MitzuMPlusAPI`, mediante la fachada de solo lectura `Core/Host.lua`.
- Base de datos propia `MitzuRouteArrowsDB` (ajustes de flechas y telemetría de ArrowDemo,
  con valores por defecto: no se migran desde `MPlusAdaptiveRouteDB`).
- Comandos propios `/mra` (`/mitzuroutearrows`), con `status` y `debug` nuevos para
  diagnosticar la conexión con MitzuMPlus.
- Sin MitzuMPlus: carga, avisa una vez y queda inerte. Con una API de contrato distinto: se niega a operar.
- Incluye el alignment pasivo (`/mra alignmentdetail`) de la rama `fix/alignmentdetail-diagnostics-clean`.
