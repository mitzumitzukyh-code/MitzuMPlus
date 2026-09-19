# Changelog

Dos addons, dos historiales. Las versiones marcan la diferencia de estabilidad:
MitzuMPlus es una beta pública; MitzuRouteArrows es desarrollo (`-dev`).

El historial anterior a la separación está en `docs/history/CHANGELOG_legacy.txt`.

## MitzuMPlus

Numeración: tras `7.14.0-rc1` el producto pasó a la serie pública `1.0.0`.
Durante la preparación hubo dos builds internas sin publicar, etiquetadas
`1.0.0-beta.1` y después `1.0.0-rc1`. La primera versión pública es
`1.0.0-beta.1`, que reúne ambas. Las entradas `7.x` quedan como historial.
El changelog público (CurseForge) está en `release/CHANGELOG.md`.

### 1.1.0 — versión estable pública

**Primera versión estable de la serie 1.1. Reúne todo el trabajo interno
`1.1.0-dev.1` … `1.1.0-dev.12` y `1.1.0-experimental.1` … `1.1.0-experimental.13`,
validado en Retail LIVE.**

El cambio de fondo: MitzuMPlus deja de vivir al lado de la interfaz de Blizzard
y pasa a trabajar dentro de ella.

- **Tracker nativo:** los datos de la llave se pintan dentro del bloque M+ de
  Blizzard, con degradación de layout en barras estrechas y compatibilidad con
  Angry Keystones.
- **Predicción dinámica +3 / +2 / +1** junto al temporizador de Blizzard, con
  confianza opcional, y **estabilización**: la medida se difiere una vuelta del
  bucle tras `EndLayout` para que el ritmo no parpadee mientras las métricas de
  texto convergen.
- **Fuerzas enemigas como `actual / total`** y **«faltan N»** en lugar de sólo
  un porcentaje.
- **Resumen final de la carrera:** un único panel manda al terminar; los avisos
  de finalización y récord se suprimen mientras está visible y se consolidan en
  una sola línea.
- **Objetivo de temporada por personaje**, opcional. El antiguo valor 2000
  impuesto por el addon se migra a «desactivado» en vez de tratarse como una
  decisión del jugador.
- **Panel de temporada** integrado en `ChallengesFrame`, con puntuación por
  mazmorra sobre las tarjetas de Blizzard y **teleports** con estado de reutilización.
- **Auto-slot de la piedra angular**, idempotente por apertura del receptáculo y
  **sin inicio automático del desafío**: activar sigue siendo manual.
- **Comprobación de grupo** y **temporizador de pull configurable** (5 / 10 / 20 s)
  sobre el marco nativo de la piedra.
- **Cobertura de utilidad en LFG:** Heroísmo/Ansia, Brez y Calmar, en tres
  recuadros legibles sobre las cabeceras nativas. No se mueve ni redimensiona
  ningún marco de Blizzard, y no hay invitación ni rechazo automáticos.
- **InspectArbiter:** un único propietario del canal `NotifyInspect`. Mitzu cede
  ante la ventana de inspección de Blizzard y **nunca** llama a
  `ClearInspectPlayer()`, así que la caché compartida queda intacta.
- **Historial y base de datos:** la finalización de carrera ya no duplica
  entradas, y unas fuerzas enemigas ausentes se muestran como «Sin datos» en vez
  de un `0.0%` inventado.
- **Localización completa** por idioma de cliente: inglés (enUS/enGB y todo
  cliente sin traducir) y español (esES/esMX).

### 1.1.0-dev.11 — desarrollo interno (Retail dev, sin publicar)

**Pase final de tipografía del tracker integrado. Sin funciones nuevas.**

La observación era concreta: «los números de Mitzu se ven muy pequeños en
comparación con Blizzard, y los números debajo de la barra de tropas apenas se
ven». Tenía razón, y el motivo era una decisión de dev.9: para no competir con
el reloj de Blizzard, *todo* lo de Mitzu se dejó en fuentes `Small`. El
resultado fue discreto hasta la ilegibilidad en combate. dev.11 sustituye esa
regla plana por una jerarquía real, tomando como referencia visual —no de
código— cómo resuelve esto Angry Keystones.

- **Una escalera explícita de fuentes nativas de Blizzard**, de mayor a menor:
  reloj de Blizzard (`Huge`, 20) → umbral (`GameFontHighlightLarge`, 16) →
  ritmo (`GameFontHighlight`, 12) → recuento de fuerzas (`GameFontHighlight`,
  12) → restantes (`GameFontHighlightSmall`, 10) → penalización y confianza
  (10, además atenuada). Blizzard sigue siendo lo más grande de la pantalla;
  Mitzu ya no parece una nota al pie.
- **El umbral iguala el peso de Angry Keystones**: `+3 4:12` pasa de 12 a 16 px
  y se pinta en el oro de Blizzard (`1.00, 0.843, 0.00`), en un solo color. El
  código de color contextual (+3 verde / +2 oro / +1 naranja / OVERTIME rojo) se
  queda donde informa de algo que cambia: la línea de RITMO.
- **Las fuerzas, que era el problema principal**: el recuento `449 / 551` sube a
  12 px y a blanco pleno, y los restantes (`faltan 102` / `102 remaining`) dejan
  de compartir la fuente atenuada de la confianza —que es exactamente por lo que
  «apenas se veían»— y pasan a `GameFontHighlightSmall` en plata
  (`0.78, 0.78, 0.812`).
- **Y se miden con la fuente con la que se pintan.** Antes el layout medía los
  restantes con la fuente de la confianza: medir pequeño y pintar grande es como
  el texto se sale de la barra. El orden de sacrificio no cambia y sigue siendo
  el correcto: `SPLIT` → `PRIMARY` → `PRIMARY_COMPACT`. El recuento principal
  **nunca** encoge para conservar los restantes.
- **Sin nada nuevo que dibujar**: ni fondo, ni panel, ni brillo, ni contorno, ni
  barra propia, ni segundo reloj, ni HUD. Solo `FontString` propios con
  plantillas nativas. La legibilidad sale de elegir bien la fuente, no de
  `SetScale()`: la escala sigue siendo la preferencia del usuario, aplicada a los
  frames de Mitzu y solo con el valor ya acotado.
- **Nada de esto depende del idioma.** El ancho se mide sobre el texto ya
  traducido: a la anchura real de la barra (191 px) caben las dos columnas en
  español (116 px) y en inglés (131 px); si la barra se estrecha a 120 px el
  inglés sacrifica los restantes antes que el español, porque su cadena es más
  larga, no porque exista ninguna rama `if locale ==`.
- La vista previa flotante usa la misma escalera: lo que se enseña en
  Configuración es el tamaño que se verá en la llave.
- `lastEmbedded` gana cuatro campos de texto (`thresholdFont`, `paceFont`,
  `forcesPrimaryFont`, `forcesSecondaryFont`): nombres de plantilla, nunca
  objetos de fuente. Responden a «se ve pequeño» sin pedir una captura.
- Angry Keystones, penalización por muertes, localización, autoridad de
  finalización y las guardas de taint quedan **igual**: con Angry activo el
  umbral sigue diferido y vacío, el ritmo sigue siendo de Mitzu y no hay
  porcentaje duplicado.
- Tests: 7 pruebas nuevas (204 en total, 7024 aserciones) que fijan la escalera,
  su aplicación real a los `FontString`, la paridad con la vista previa, el
  degradado por anchura en los dos idiomas y el comportamiento con y sin Angry.
  El mock de WoW ahora conoce la altura real de cada plantilla de Blizzard —sin
  eso, una prueba de jerarquía tipográfica no significaría nada— y el mock del
  tracker de Blizzard vigila también `SetFont`/`SetFontObject`, que hasta ahora
  se podían llamar sobre el reloj de Blizzard sin que nadie se quejara.
- Comprobaciones estáticas nuevas: la escalera es estrictamente descendente y
  toda ella de plantillas nativas conocidas; el umbral nunca es `Small`; el
  recuento de fuerzas nunca es la fuente atenuada; ningún `SetFont`,
  `SetFontObject` ni `CreateFont` propios; `SetScale` solo sobre frames de Mitzu
  y solo con el ajuste acotado; oro y plata exactos; la vista previa no puede
  divergir del bloque integrado; y ninguna capa visual puede ramificar por
  idioma.
- Mutación: 12 mutantes nuevos (52/52 detectados). Diez de ellos los caza una
  prueba de comportamiento, no solo el filtro de texto.

### 1.1.0-dev.10 — desarrollo interno (Retail dev, sin publicar)

**Bloqueo de release resuelto: el addon habla el idioma del cliente.**

Antes de 1.1.0 se detectó que, aunque `Locales/enUS.lua` y `Locales/esES.lua`
existían desde 1.0, **ningún módulo los usaba**: toda la interfaz estaba escrita
en español dentro del código. Un jugador con cliente inglés habría visto
«Historial», «RITMO» o «faltan 227». Eso no se puede publicar.

- **AceLocale-3.0 es ahora la única capa que elige idioma**, y elige el del
  cliente. `Bootstrap.lua` expone `MitzuMPlus.L` y todos los módulos consumen esa
  tabla. No hay selector, ni opción, ni SavedVariable, ni `/reload`, ni detección
  de región: lo decide `GetLocale()` del cliente y nada más.
- **Inglés (enUS) es el locale por defecto** (`NewLocale(..., "enUS", true)`), así
  que cualquier cliente sin traducción recibe inglés automáticamente. `enGB` lo
  resuelve el propio AceLocale sin duplicar un fichero. Español solo en `esES` y
  `esMX`, que comparten un único fichero.
- **~300 cadenas visibles migradas** a claves de AceLocale: tracker integrado,
  vista previa y resumen, las cuatro pestañas, Historial, Estadísticas,
  Jugadores, Configuración, popups, botón de minimapa, exportación, avisos de
  chat, marcas personales, fechas relativas y ayuda de comandos. `enUS` y `esES`
  pasan de 156 a 492 claves, con el mismo conjunto exacto en los dos ficheros.
- **Nada de identidades traducidas** (regla: guardar IDs, mostrar texto):
  `Panel.FormatResult` devuelve `+3/+2/+1/OUT/INCOMPLETE` y `Panel.ResultLabel`
  traduce solo al pintar (antes el filtro comparaba con la palabra «Fuera», que
  se habría roto en inglés); `Database` deja de guardar `seasonName` traducido y
  guarda solo `seasonKey`, de modo que un historial creado en un cliente español
  se lee en inglés en uno inglés.
- **Los nombres de clase los da Blizzard** (`LOCALIZED_CLASS_NAMES_*`): se retira
  la tabla española propia de `Players.lua`. Mazmorras, jefes y criterios ya
  venían del cliente y se siguen respetando sin tocarlos.
- **Diagnóstico técnico en un solo idioma**: los volcados de `/emp dev`, el
  ErrorLogger y `/emp forces` pasan a inglés. No se traducen (son para el
  desarrollador), pero ya no devuelven media frase en español a un jugador inglés.
- **Plurales sin frases rotas**: «hace 1 semana» / «hace N semanas» son claves
  distintas; nunca «1 semanas».
- **Bug Report `[LOCALIZATION]`**: `clientLocale`, `activeLocale`,
  `fallbackLocale=enUS`, `englishDefault`, `translatedClient`, `loadedKeys`,
  `missingKeys`, `localizationWarnings`. `ReportVersion` pasa a 5. Comando de
  diagnóstico opcional `/emp dev locale`.
- **Sin relleno silencioso**: una clave ausente no se sustituye por `?` ni por
  `UNKNOWN`; AceLocale avisa por el manejador de errores y el informe la cuenta.
  Los bancos exigen `missingKeys=0`.
- Tests: nuevo `tests/core/Localization.spec.lua` (21 pruebas, 4925
  aserciones) que arranca el addon COMPLETO con el cliente en enUS, enGB, esES,
  esMX, deDE, frFR, ptBR, ruRU, koKR, zhCN, zhTW e itIT; comprueba paridad de
  claves, especificadores de formato idénticos entre idiomas, cero español en
  clientes ingleses, cero inglés donde hay traducción, ninguna clave cruda
  pintada, que el layout mide el texto REAL (en inglés «227 remaining» es más
  largo que «faltan 227» y el sacrificio de columnas lo refleja) y que un
  historial guardado en español se lee en inglés. Nuevo
  `tests/harness/locale_stub.lua`; el escenario acepta `S.boot({ locale = ... })`.
- Comprobaciones estáticas nuevas: paridad enUS/esES, toda clave `L["..."]` usada
  por el runtime existe en ambos ficheros, ninguna cadena española fuera de
  `Locales/`, `GetLocale()` solo en la capa de localización, ningún ajuste de
  idioma, los `Locales/` cargan antes que `Bootstrap.lua`, y las identidades
  (resultado de run, temporada, clase) no pueden volver a ser texto traducido.
- Mutación: 15 mutantes nuevos de localización (RITMO vuelve a estar escrito a
  mano, la barra de pestañas escribe español, el inglés deja de ser el locale por
  defecto, enGB pierde el fallback, falta una traducción española, falta una
  clave inglesa, el inglés muestra «faltan», aparece un selector de idioma, se
  guarda texto traducido, el resultado vuelve a ser una palabra, vista previa y
  resumen dejan de traducirse, se pinta una clave cruda, las clases se traducen a
  mano, un `%d` se convierte en `%s`). Total 40/40 detectados.
- Sin cambios en backend: `TrackerState`, `TrackerAdapter`, `PredictionEngine`,
  `RunSession`, `PartyProfiler`, `DungeonContext`, `KeystoneTracker` y el cálculo
  de estadísticas quedan intactos, igual que todo lo de dev.9 (snapshot
  `lastEmbedded`, penalización de muertes, Angry Keystones, enhancer integrado,
  autoridad de finalización, recuperación tras `/reload` y guardas de taint).

### 1.1.0-dev.9 — desarrollo interno (Retail dev, sin publicar)

Pasada final de pulido y observabilidad. **Sin funciones nuevas** y sin tocar
adaptador, estado, predicción, perfilado de grupo, sesiones, historial ni la
autoridad de finalización. dev.8 quedó validado en Retail (Guarida de Nalorakk
+4: `renderMode=EMBEDDED`, `NO_FLOATING_HUD_DURING_KEY=PASS`, `tainted=none`,
`enhancerErrors=0`, `/reload` con la misma sesión, historial +1,
`completionSource=CHALLENGE_MODE_COMPLETED` con el último jefe inferido).

- **RITMO más legible en combate**: la etiqueta deja el gris casi invisible
  (`a8a8b0` → `c8c8d2`) y la línea ya no se atenúa al 80 % cuando el bracket es
  provisional; eso lo cuenta la confianza, que sigue siendo secundaria y en
  `GameFontDisableSmall`. Mismo tamaño, sin fondo, sin borde y sin brillo: el
  temporizador de Blizzard sigue siendo lo más visible.
- **Fuerzas ancladas a la barra de Blizzard**: `502 / 729` y `faltan 227` cuelgan
  de una fila propia anclada a los extremos reales de la `StatusBar`
  (`BOTTOMLEFT`/`BOTTOMRIGHT` de la misma fila), con una única separación
  vertical. Misma base, misma altura, sin coordenadas absolutas y sin escribir
  nada sobre la barra de Blizzard.
- **Snapshot QA del último render integrado** (`MitzuTracker._lastEmbedded`):
  copia plana de lo último que Mitzu pintó **de verdad** dentro del bloque M+.
  Solo se actualiza con un render `EMBEDDED` válido (bloque visible, activo y
  enganche sano) y no se borra al ocultarse el tracker, con el resumen, con la
  vista previa, al terminar la llave ni al salir de la mazmorra. Vive en memoria:
  no toca SavedVariables, ni `TrackerState`, ni sesiones, ni historial.
- **Bug Report `[LAST EMBEDDED RENDER]`**: `lastEmbedded.available`,
  `lastEmbedded.age`, `stateRevision`, `renderRevision`, `thresholdDisplayed`,
  `thresholdTimeDisplayed`, `thresholdMode`, `paceDisplayed`, `paceMode`,
  `prediction`, `provisional`, `confidenceDisplayed`, `etaDisplayed`,
  `forcesPrimaryDisplayed`, `forcesSecondaryDisplayed`, `forcesLayoutMode`,
  `penaltyDisplayed`, `availableWidth`, `angryKeystonesLoaded`,
  `attachGeneration`, `attachmentHealthy`, `renderReason`. El prefijo separa
  ACTUAL (`[TRACKER VISUAL]`) de ÚLTIMO: tras el resumen el primero es `nil` y el
  segundo sigue contando la llave. `ReportVersion` pasa a 4.
- **Penalización de muertes**: política intacta (solo el tiempo perdido que
  publica Blizzard, nunca el recuento, que ya es suyo) más un mínimo de 1 s para
  que una penalización sub-segundo no se pinte como `-0:00`.
- **Angry Keystones**: sin capa de compatibilidad nueva. Solo
  `C_AddOns.IsAddOnLoaded("AngryKeystones")`; con AK cargado el umbral es suyo
  (`thresholdMode=DEFERRED`) y Mitzu mantiene ritmo y fuerzas sin duplicar
  porcentaje ni temporizador.
- Vista previa alineada con el render real (misma fila de fuerzas, misma
  etiqueta de RITMO); ni el resumen ni la vista previa se rediseñan.
- Tests: fixture de regresión de la llave real (mapID 586 +4, límite 1920,
  `502 / 729`, `+3 5:18`, `RITMO +2` 50 %), ciclo de vida del snapshot (crear,
  actualizar, ocultar, resumen, vista previa, salir, llave nueva, sin efectos
  sobre estado/historial/sesión), jerarquía de RITMO, alineación de fuerzas,
  penalización de muertes y coexistencia con Angry Keystones.
- Nuevas comprobaciones estáticas: el enhancer no puede pintar fondo ni texturas,
  no puede escribir en `DeathCount`/`StatusBar`/`Label` de Blizzard, las fuentes
  secundarias siguen siendo pequeñas y grises, y el snapshot QA no puede escribir
  `TrackerState`, sesiones ni SavedVariables.
- Nueva puerta `tests/run_mutation_tests.py`: 25 mutantes (dev.6/7/8 conservados
  + los de dev.9), 25 detectados, 0 supervivientes.

### 1.1.0-dev.8 — desarrollo interno (Retail dev, sin publicar)

- Pasada de densidad y jerarquía visual del tracker integrado (sin cambios de
  lógica: adapter, estado, predicción, sesiones e historial intactos). dev.7
  validado en Retail (Guarida de Nalorakk +10: `attached=true`, `tainted=none`).
- Un solo umbral junto al reloj de Blizzard: el próximo que se puede perder
  (`+3 7:57` → `+2 …` → `+1 …`; nada fuera de tiempo).
  `TrackerPresenter.GetNextRelevantUpgradeThreshold` sobre los umbrales
  centralizados.
- `RITMO +1` con la confianza y la ETA en gris y en su propio texto;
  se sacrifican ETA → confianza → ritmo según el ancho, nunca antes que el umbral.
- Fuerzas en dos columnas bajo la barra: `329 / 729` … `faltan 400`; sin repetir
  el porcentaje (Blizzard/Angry Keystones ya lo muestran); se reduce a
  `329 / 729` y `329/729` si no cabe.
- Penalización de muertes discreta junto al contador de Blizzard; nada si no
  hay tiempo perdido publicado.
- Con Angry Keystones: Mitzu no repite el umbral junto al reloj y alinea el ritmo
  a la derecha.
- `TrackerPresenter.LayoutEmbedded`: decisión pura y testeada de qué cabe
  (modos de umbral, ritmo y fuerzas); anchos medidos cacheados.
- Vista previa/resumen: simulación estrecha del bloque de Blizzard con las mismas
  decisiones de layout.
- Bug Report `[TRACKER VISUAL]`: `thresholdDisplayed`, `thresholdTimeDisplayed`,
  `thresholdMode`, `paceMode`, `etaDisplayed`, `forcesPrimaryDisplayed`,
  `forcesSecondaryDisplayed`, `forcesLayoutMode`, `angryKeystonesLoaded`.

### 1.1.0-dev.7 — desarrollo interno (Retail dev, sin publicar)

- Dirección visual definitiva: **Blizzard Mythic+ Tracker Enhancer**. dev.6 fue
  un prototipo independiente; durante una llave real ya no hay ventana de Mitzu.
  `BlizzardTrackerEnhancer` añade al bloque M+ nativo
  (`ScenarioObjectiveTracker.ChallengeModeBlock`, auditado en 12.1.0.69814):
  tiempos de mejora `+3/+2/+1` adaptativos junto al temporizador, `RITMO +N` y
  confianza, recuento/restante (y % preciso sin Angry Keystones) bajo la barra
  de fuerzas y tiempo perdido junto al contador de muertes.
- Seguridad: solo post-hooks `ChallengeModeBlock.Activate` y
  `ScenarioObjectiveTracker.EndLayout`; frames propios hijos del bloque; ninguna
  escritura sobre frames de Blizzard; discover/attach/detach/reattach por
  instancia; kill switch a los 3 errores. Sin bloque, sin fallback flotante.
- `TrackerView` (ventana) queda para vista previa (rechazada con llave en curso)
  y el resumen de 20 s (Blizzard retira el bloque al terminar).
- Ajustes nuevos: `showPrediction`, `showUpgradeTimes`, `showForcesCount`,
  `showForcesRemaining`, `showDeaths`. Posición/bloqueo solo de la ventana.
- Bug Report `[TRACKER VISUAL]`: `renderMode`, `attached`, `attachGeneration`,
  `attachReason`, `attachmentHealthy`, estado del bloque y lo pintado.
  Invariante `NO_FLOATING_HUD_DURING_KEY`.
- Static checks del enhancer (solo lectura de `blizz*`, hooks permitidos,
  `SetParent` propio, enrutado sin HUD en llave). Mock fiel del Objective
  Tracker para los tests; el cliente simulado mide texto por glifo.

### 1.1.0-dev.6 — desarrollo interno (Retail dev, sin publicar)

- TrackerState: `CHALLENGE_MODE_COMPLETED` es la autoridad terminal del final.
  Retail dev.5 (Reposo de los Reyes +12) terminó con `3/4` observado porque
  Blizzard retiró los criterios antes de la relectura. Ahora se separan
  convergencia de API (`completionConverged`) y final oficial
  (`terminalStateConfirmed=true`, `completionSource=CHALLENGE_MODE_COMPLETED`,
  `criteriaUnavailableAfterCompletion`). Lo observado no se reescribe
  (`bossesCompleted=3`); el valor terminal va aparte con su origen
  (`bossesCompletedFinal=4`, `bossCountSource=INFERRED_FROM_COMPLETION_EVENT`;
  igual para fuerzas). `completionCriteriaIncomplete` ya no marca como incompleta
  una llave terminada.
- Bug Report `[PARTY]`: leía `member.class`/`member.role`, campos que
  PartyProfiler nunca escribe (`classFile`/`effectiveRole`), y mostraba
  `class=nil role=nil`. Añade `assigned` y `specRole`.
- PartyProfiler: el rol de la spec se resuelve también para el resto del grupo
  cuando su specID es conocido (grupos premade sin rol asignado). Consulta por
  ID con la función global de Retail como respaldo; classFile con respaldo a
  `UnitClass` y filtro de valores secretos.
- Nuevo **Mitzu Tracker** (V1): `TrackerPresenter` (modelo puro) →
  `TrackerView` (frames creados una vez) ← `MitzuTracker` (controlador). Timer
  restante dominante, umbrales +3/+2/+1 por reloj, ritmo de PredictionEngine con
  confianza y ETA, fuerzas (%, recuento, restantes), jefes, muertes y
  penalización publicada. Estados PENDING/RUNNING/COMPLETING/SUMMARY y vista
  previa aislada. Mismos ajustes (`settings.hud`), comandos y opciones.
- Retirado `KeyPredictionHUD.lua` (1.0): sin dependencias tras la migración;
  rollback en git (`v1.0.0-beta.1`). Sección `[TRACKER]` del Bug Report pasa a
  `[TRACKER VISUAL]`.
- Umbrales +2/+3 centralizados en `Constants` (`KEY_UPGRADE_PLUS2/3_RATIO`).
- Tests: fixture de la llave real (+12, reload, final sin criterios),
  PartyProfiler, Presenter y tracker visual con el addon completo; 14 mutantes.

### 1.1.0-dev.5 — desarrollo interno (Retail dev, sin publicar)

- TrackerState: convergencia del final de llave. Tras
  `CHALLENGE_MODE_COMPLETED` el tiempo final se congela en el acto, pero los
  criterios se releen hasta 3 s (estado interno `COMPLETING`) para no congelar
  un boss que Blizzard publica después del evento (Retail dev.4 dejó `2/3` en
  una llave completada). Nunca se inventa un boss ni se sustituye un valor real
  por nil o 0; si Blizzard no expone el final, `completionCriteriaIncomplete=true`.
- Diagnóstico: `completionConverged`, `completionAttempts`,
  `completionConvergenceMs`, `completionCriteriaIncomplete`,
  `completionRegressionsIgnored`, `duplicateCompletions` en `/emp dev state` y
  en `[TRACKER STATE]` del Bug Report; FlightRecorder `STATE_COMPLETION_*`.
- Eventos de relectura añadidos: `SCENARIO_UPDATE`, `SCENARIO_COMPLETED`.
- Validación: Retail pasa a ser el cliente principal; PTR queda opcional
  (`docs/tracker/ROADMAP.md`). `tools/deploy_ptr.py --retail` despliega en la
  instalación de desarrollo de Retail (con backup y solo con WoW cerrado).
- Tests: la ejecución en Lua 5.1 emula el `xpcall` de WoW (pasa argumentos);
  antes AceAddon no llegaba a ejecutar `OnInitialize` en esa pasada.

### 1.1.0-dev.4 — desarrollo interno (solo PTR, sin publicar)

- Capacidades: `requiredMissing`, `optionalMissing` y `legacyFallbacksAbsent`
  sustituyen al ambiguo `missingSignature=all`.
- TrackerState: la espera normal del temporizador y los criterios al arrancar
  la llave o tras `/reload` se muestra como `transient` y solo se convierte en
  aviso si dura más de 10 s.
- Validado en Retail 12.1.0 (dev.3): TrackerState RUNNING y recuperación tras
  `/reload` con continuidad del temporizador del servidor.

### 1.1.0-dev.3 — desarrollo interno (solo PTR, sin publicar)

- Nuevo `TrackerState` (fase 2): snapshot normalizado de la llave construido
  solo desde `TrackerAdapter`. Ciclo IDLE/PENDING/RUNNING/COMPLETED,
  temporizador del servidor interpolado, fuerzas y bosses, recuperación tras
  `/reload`, avisos por llave. Eventos agrupados y resync lento solo durante la
  llave. Una lectura parcial conserva lo sabido marcado como obsoleto.
- `/emp dev state` y sección `TRACKER STATE` del Bug Report.
- Capacidades: una red heredada ausente (`C_Scenario.*`, constante `LE_`) con
  su API principal presente se informa como opcional, no como API que falta.
- Validado en llave real de Retail 12.1.0: fuerzas 144/608 (23.684 %), bosses
  1/4, paridad con 1.0 y final de llave. Pendiente en PTR 12.1.5.

### 1.1.0-dev.2 — desarrollo interno (solo PTR, sin publicar)

- Diseño: 1.1 mejora el tracker nativo de Blizzard en lugar de crear un HUD
  propio. Auditado `Blizzard_ObjectiveTracker` (idéntico en 12.1.0 y 12.1.5).
- `BlizzardTrackerProbe`: sonda de solo lectura del bloque Mythic+ nativo
  (`/emp dev blizzard`, sección `BLIZZARD TRACKER` del Bug Report) con línea
  base de taint.
- TrackerAdapter: el tipo del temporizador de la llave se resuelve con
  `Enum.WorldElapsedTimerTypes.ChallengeMode`, como hace Blizzard.

### 1.1.0-dev.1 — desarrollo interno (solo PTR, sin publicar)

Rama `develop/1.1.0`. La beta pública sigue siendo `1.0.0-beta.1`.

- TOC con `## Interface: 120100, 120105`: la misma build carga en Retail
  12.1.0 y en el PTR 12.1.5.
- Nuevo `TrackerAdapter`: única capa que habla con las APIs de Challenge Mode,
  escenario y temporizador del servidor. Normaliza timer, mapa, nivel,
  criterios, fuerzas enemigas y bosses; se degrada a "desconocido" ante APIs
  ausentes, valores secretos o datos parciales. Todavía no alimenta al HUD.
- Informe de desarrollo `/emp dev tracker` (capacidades de API y paridad con
  los módulos 1.0) y sección `TRACKER ADAPTER` en el Bug Report.
- `tools/deploy_ptr.py`: sincronización al PTR con backup y validación.

### 1.0.0-beta.1 — primera beta pública

Reúne la limpieza de producto (build interna) y el trabajo de la build interna
`1.0.0-rc1`. Autor y copyright unificados como `Mutzuki Mizt` (LICENSE, TOC,
marca de agua y documentación de release).

- Notificaciones como texto flotante, sin panel.
- Set de iconos aprobado (header 30 px, pestañas 20 px, opciones y cerrar
  22 px sobre area de clic 24 px, sin fondo y con hover por alpha; minimapa y lista de addons). Texturas recortadas para que el arte
  ocupe ~90% del lienzo (el minimapa conserva 87.5% por el recorte del 5% de
  LibDBIcon); retirada una línea casi transparente que descentraba
  `btn_options_64` y `btn_minimize_64`. Retirados `logo_64.tga`,
  `2_settings.tga`, `3_close.tga` y `5a/5b/5e_tab_*.tga`.
- Carpeta runtime limpia: `README.md`, `CHANGELOG.md`, `CURSEFORGE_PAGE.md` y
  `MitzuMPlus_Logo_512.png` pasan a `release/`; `MitzuMPlus/LICENSE` se retira
  (el empaquetador copia el `LICENSE` raíz al ZIP).
- Retirado `modules/SpecDatabase.lua` (fuera del TOC y sin consumidores) y
  `tools/convert_logo.py` (generaba el `logo_64.tga` obsoleto).
- Tests alineados con cambios intencionales de la limpieza de producto: resultado
  `Incompleta` para runs sin tiempo final, separador ASCII `  -  ` en el HUD y
  flecha ASCII `v` en los desplegables. Sin emoji en el código.

### Build interna (sobre 7.14.0-rc1) — limpieza final de producto

Simplificación de producto en feature freeze.

- Historial V2 reconstruido con filtros compactos, tabla 65/35, detalle,
  selección, exportación y paginación.
- Retirados del producto los sistemas de rutas, navegación manual, Coach
  táctico, datasets derivados de MDT, API experimental y ajustes sin consumidor.
- `RunSession` reducido a identidad, reload y deduplicación; corregido el doble
  registro causado por información de finalización reciclada.
- Configuración reorganizada y Bug Report alineado con el producto final.
- Paquete MIT sin dependencia runtime ni datos derivados de MDT.

**Cambiado**
- El HUD en vivo es ahora el **Key Prediction HUD** (`modules/KeyPredictionHUD.lua`):
  un frame pequeño estilo Blizzard con mazmorra y nivel, tiempo / límite, predicción
  `+3` / `+2` / `+1` / `OVERTIME` (o `CALCULANDO...`), confianza y final estimado cuando
  el motor lo da por fiable. Al completar, resultado final unos segundos.
  Lee solo DungeonContext, ChallengeClock y PredictionEngine.
- `/emp hud test` previsualiza el tracker; `[HUD]` del Bug Report usa
  `implementation=KEY_PREDICTION_HUD` con prediction/confidence/estimatedFinish/elapsed/limit.
- Invariante `HUD_MATCHES_AUTHORITY` → `HUD_PREDICTION_ONLY`; `COACH_ROUTE_POSITION_TRUST` retirado.
- La tecla `MITZUMPLUS_OVERLAY` alterna el HUD de predicción.
- Core marca `run.completionInfoSource` cuando el resultado viene de la API de finalización.

**Retirado**
- Coach HUD V2 (`modules/CoachHUD.lua`): pull, `MANUAL`, % de ruta, siguiente pull,
  mobs y consejo táctico.
- Overlay clásico del Coach (`modules/UI_Overlay_v2.lua`) y sus ajustes/paneles.
- Ajustes `hud.compact`, `hud.showPreKey`, `hud.replaceClassic` (se quitan al cargar).

**Corregido**
- PredictionEngine (BUG PRED-HYST): una mejora de varios brackets comparaba contra el
  umbral más lejano y podía quedarse en `FUERA` con la proyección muy por debajo del límite.

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
