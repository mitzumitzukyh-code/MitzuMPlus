# Development workflow (1.1.0) — Retail primero, PTR opcional

Desde 1.1.0-dev.5 la validación principal es **Retail** (ver
`ROADMAP.md` → Política de validación). El PTR sigue siendo válido, pero ya no
bloquea fases.

| Entorno | Ruta | Versión | Regla |
|---|---|---|---|
| Público (CurseForge) | release `1.0.0-beta.1` | `1.0.0-beta.1` | Artefactos de release intactos |
| Repo | `D:\proyectos\MitzuMPlus`, rama `develop/1.1.0` | `1.1.0-dev.N` | Todo el desarrollo |
| Retail dev (**principal**) | `D:\World of Warcraft\_retail_\Interface\AddOns\MitzuMPlus` | `1.1.0-dev.N` | `deploy_ptr.py --retail`, backup previo, solo con `Wow.exe` cerrado |
| PTR (opcional) | `D:\World of Warcraft\_xptr_\Interface\AddOns\MitzuMPlus` | `1.1.0-dev.N` | `deploy_ptr.py` |

## Ciclo

1. Cambio en `develop/1.1.0`.
2. `python tests/run_lua_tests.py` y `python tests/run_static_checks.py`
   (con `PYTHONIOENCODING=utf-8` en Windows).
3. Commit pequeño y semántico.
4. `python tools/deploy_ptr.py --retail --dry-run`, después `python tools/deploy_ptr.py --retail`
   (sin `--retail`: PTR).
   - Sin `--retail` rechaza cualquier destino que no sea `_xptr_`/`_ptr_`; con
     `--retail` solo acepta `_retail_` y se niega si `Wow.exe` está abierto.
   - Hace backup en `D:\Mitzu_Backups\<fecha>_<retail|ptr>_MitzuMPlus_<versión>`.
   - Copia solo runtime (misma lista que el empaquetador) y valida: TOC en
     `AddOns\MitzuMPlus\MitzuMPlus.toc`, sin carpeta doble, cada entrada del TOC
     presente, contenido idéntico al repo.
   - `python tools/deploy_ptr.py --verify` compara sin tocar nada.
5. En el cliente: `/reload` si solo cambió Lua existente; **reinicio completo del
   cliente** si cambió el `.toc` (ficheros nuevos o metadatos).
6. Prueba guiada, `/emp bugreport` y, en fase de tracker, `/emp dev tracker` y `/emp dev blizzard`.
7. Bug → reproducir, capturar, test, arreglar, suite, desplegar, volver a probar.

## Interface

El TOC declara `## Interface: 120100, 120105`: Retail 12.1.0 y PTR 12.1.5
(valor leído de `lastAddonVersion` en `_xptr_\WTF\Config.wtf`). Una sola build
carga en ambos clientes.

## Release

Nada de dev/alpha se publica (ni desde Retail dev ni desde PTR). Solo con autorización explícita:
`1.1.0-beta.1` → `tools/package_mitzumplus.py --check` → tag → GitHub Release →
CurseForge. Los materiales de `release/` siguen nombrando `1.0.0-beta.1` hasta
entonces (el static check lo permite para versiones `-dev`/`-alpha`).
