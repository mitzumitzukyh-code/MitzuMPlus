# Release de MitzuMPlus

Solo **MitzuMPlus** se publica. **MitzuRouteArrows es EXPERIMENTAL y no se
empaqueta ni se sube a CurseForge** en ningún caso.

## 1. Comprobaciones automáticas

```bash
python tests/run_lua_tests.py
```

```bash
python tests/run_static_checks.py
```

```bash
git diff --check
```

Las tres tienen que terminar con 0 fallos.

## 2. Paquete

```bash
python tools/package_mitzumplus.py --check
```

Genera `dist/MitzuMPlus-<versión>.zip` (la versión sale de `## Version` del `.toc`)
y lo valida:

- una única carpeta raíz `MitzuMPlus/`, con `MitzuMPlus.toc` dentro (nombre de carpeta = nombre del `.toc`);
- cada fichero que nombra el `.toc` está en el zip;
- incluye `LICENSE`, `DATA_SOURCES.md` y `Bindings.xml`;
- no incluye `tests/`, `docs/`, `tools/`, `.git`, CI, capturas, ficheros temporales ni nada de MitzuRouteArrows.

`dist/` está en `.gitignore`: el zip no se versiona.

## 3. Validación en el cliente (manual, antes de publicar)

Con **solo MitzuMPlus** instalado (sin MitzuRouteArrows, sin MDT):

1. El addon aparece como `MitzuMPlus` en la lista de addons, con icono y versión.
2. Entrar al juego sin errores de Lua (BugSack/BugGrabber activos).
3. `/emp` abre la ventana; historial, estadísticas, Coach y configuración se ven bien.
4. `/emp version` muestra la versión del `.toc`.
5. Entrar a una mazmorra de la temporada: `/emp dungeon` → `PRE_KEY`; `/emp routes` lista la ruta nativa.
6. Arrancar una llave: `/emp route` → ruta `ACTIVE`, pull 1; `/emp next` / `/emp prev` mueven el pull; el HUD lo refleja.
7. `/reload` dentro de la llave: la sesión se recupera y el pull se conserva (`/emp session`).
8. Terminar la llave: el historial registra la run.
9. `/emp help` no lista ningún comando de flechas, evidencias ni alignment.

Repetir 1–4 **con MDT instalado** (importación opcional con `/emp rutamdt`) y **con
MitzuRouteArrows instalado**: el comportamiento del core no debe cambiar.

## 4. Migración desde `MitzuMPlus_Historial`

La carpeta pasó de `MitzuMPlus_Historial` a `MitzuMPlus`. Consecuencias para quien actualiza:

| Qué | Efecto | Qué hacer |
|---|---|---|
| SavedVariables | WoW busca `SavedVariables/MitzuMPlus.lua`; el historial está en `MitzuMPlus_Historial.lua` | copiar el fichero con el nombre nuevo, con el juego cerrado; los nombres de variables no cambian |
| Carpeta antigua | quedarían dos addons cargados | borrar `Interface/AddOns/MitzuMPlus_Historial` |
| Tecla de la pestaña de historial | el binding se renombró a `MitzuMPlus_HistoryTabBinding` | volver a asignarla |
| Tecla de marcar objetivo | ahora es de MitzuRouteArrows (mismo nombre de binding) | nada si se usa MitzuRouteArrows |
| Ajustes de flechas | quedan sin uso en `MPlusAdaptiveRouteDB`; MitzuRouteArrows usa `MitzuRouteArrowsDB` con valores por defecto | nada; no se borran |

Esto debe figurar en la descripción de CurseForge de la versión.

## 5. Riesgos conocidos

### MitzuMPlus

1. **Licencia de datos.** Las rutas nativas y `data/MDTEnemyData.lua` derivan de Mythic
   Dungeon Tools (GPL-2.0) y el addon es MIT. **Revisar antes de publicar** (ver `MitzuMPlus/DATA_SOURCES.md`).
2. **Sin validar en el cliente real tras la separación.** Todo lo anterior está probado en un
   cliente simulado que carga el `.toc` real; falta la sección 3.
3. **Migración manual de SavedVariables** (sección 4). Quien no la haga verá el historial vacío.
4. **Arreglos de UI pendientes.** El rediseño del Historial y sus ajustes (desplegable de
   mazmorras, filtros, ajuste de columnas) **no están en esta rama**. Viven en el commit
   `0fb32ba` (`chore: sync active addon state`, rama `feat/alignmentdetail-diagnostics`),
   mezclados con cambios no relacionados, y en la carpeta de desarrollo local sin commitear.
   Deben separarse y probarse en un PR propio sobre esta base.
5. `MitzuMPlusAPI` no es una barrera de seguridad: `_G.MitzuMPlus` sigue siendo global, y en
   Lua `rawset` sobre el proxy de la API podría ensombrecer una función para otros consumidores.
   Ningún addon de este repositorio lo hace (comprobado estáticamente).
6. `PullNavigator` (teclas) y `RouteProgress` pueden divergir; es anterior a la separación y se
   expone tal cual en la API.
7. `MitzuMPlus.INITIALIZED` nunca se pone a `true`; `IsReady()` usa la existencia de la base de datos.

### MitzuRouteArrows (no se publica)

1. Sin probar en vivo tras la separación. Los bancos pasan, pero el anclaje a placas, Threat
   Plates y los valores secretos solo se validan en el cliente.
2. Todos sus callbacks corren ahora después de los manejadores del core; antes compartían
   prioridades con ellos.
3. `PullUnitResolver:ResolveCurrentPull` se dispara ante cualquier cambio del navegador, no solo
   con la tecla (sin asignaciones manuales es una operación vacía).
4. Ajustes de flechas e historial de telemetría de ArrowDemo no migrados desde `MPlusAdaptiveRouteDB`.
5. `Data/MDTPhysicalGroupData.lua` también deriva de MDT (GPL-2.0).
6. Coste de las copias de la API (ruta e índice) no medido en vivo; se cachean por revisión.
7. Las comprobaciones de dependencia son estáticas y de alcanzabilidad: un acceso ofuscado
   (`_G["Mitzu".."MPlus"]`) solo lo detectarían los bancos de comportamiento (E3, F1).

## 6. Publicar

No automatizado. Cuando la sección 3 esté completa y la licencia revisada:
subir `dist/MitzuMPlus-<versión>.zip` manualmente a CurseForge como *Beta* o *Release*.
