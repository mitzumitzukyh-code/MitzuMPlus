# Changelog

Dos addons, dos historiales. Las versiones marcan la diferencia de estabilidad:
MitzuMPlus es un candidato a release; MitzuRouteArrows es desarrollo (`-dev`).

El historial anterior a la separación está en `docs/history/CHANGELOG_legacy.txt`.

## MitzuMPlus

### 7.13.0-rc1 — separación del core

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
