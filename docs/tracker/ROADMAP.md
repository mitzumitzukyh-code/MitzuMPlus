# MitzuMPlus 1.1.0 — roadmap

Objetivo: **Blizzard Tracker Enhancer + Enemy Forces**. Enhance, don't replace.

## Fuera de alcance
- Rutas, pulls, MDT, navegación, placas, tácticas (→ MitzuRouteArrows).
- **Retirado por decisión de diseño (2026-09-15):** HUD V2 independiente, modos
  Compacto/Normal/Avanzado, opción "Ocultar tracker Blizzard", reemplazo del
  Objective Tracker, timer duplicado, ventana M+ separada.

## Fases
| Fase | Contenido | Estado |
|---|---|---|
| 0 | Auditoría, rama, baseline | Hecho |
| 1 | TrackerAdapter + capacidades | Hecho; pendiente PRUEBA PTR #1 |
| 1b | Auditoría del Objective Tracker (fuente 12.1.5) + `BlizzardTrackerProbe` solo lectura | Hecho; se confirma en PRUEBA PTR #1 |
| 2 | TrackerState (snapshot normalizado, eventos, throttling) | Tras PRUEBA PTR #1 |
| 3 | Enemy Forces en TrackerState | |
| 4 | Boss state | |
| 5 | PaceEngine | |
| 6 | PredictionEngine sobre TrackerState (+3/+2/+1/OVERTIME, ETA, margen, confianza) | |
| 7 | **BlizzardTrackerEnhancer**: fuerzas precisas en la barra nativa, umbrales +3/+2 en el bloque M+, predicción/ETA/pace | |
| 8 | Configuración mínima (activar mejoras, qué mostrar) | |
| 9 | Bug Report 1.1 | |
| 10 | Llave completa en PTR | |
| 11 | Hardening / regresión / taint | |
| 12 | 1.1.0-beta.1 candidata | |

## Decisión abierta
`KeyPredictionHUD` (1.0) es una ventana flotante propia. Con el nuevo principio,
¿se mantiene en 1.1 como está, pasa a desactivado por defecto cuando el enhancer
funcione, o se retira? No se toca hasta que Mutzuki decida.
