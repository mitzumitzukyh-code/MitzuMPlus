# PTR development workflow (1.1.0)

| Entorno | Ruta | Versión | Regla |
|---|---|---|---|
| Retail / CurseForge | `D:\World of Warcraft\_retail_\Interface\AddOns\MitzuMPlus` | `1.0.0-beta.1` | No se toca |
| Repo | `D:\proyectos\MitzuMPlus`, rama `develop/1.1.0` | `1.1.0-dev.N` | Todo el desarrollo |
| PTR | `D:\World of Warcraft\_xptr_\Interface\AddOns\MitzuMPlus` | `1.1.0-dev.N` | Runtime de pruebas |

## Ciclo

1. Cambio en `develop/1.1.0`.
2. `python tests/run_lua_tests.py` y `python tests/run_static_checks.py`
   (con `PYTHONIOENCODING=utf-8` en Windows).
3. Commit pequeño y semántico.
4. `python tools/deploy_ptr.py --dry-run`, después `python tools/deploy_ptr.py`.
   - Rechaza cualquier destino que no sea `_xptr_`/`_ptr_`.
   - Hace backup en `D:\Mitzu_Backups\<fecha>_ptr_MitzuMPlus_<versión>`.
   - Copia solo runtime (misma lista que el empaquetador) y valida: TOC en
     `AddOns\MitzuMPlus\MitzuMPlus.toc`, sin carpeta doble, cada entrada del TOC
     presente, contenido idéntico al repo.
   - `python tools/deploy_ptr.py --verify` compara sin tocar nada.
5. En el PTR: `/reload` si solo cambió Lua existente; **reinicio completo del
   cliente** si cambió el `.toc` (ficheros nuevos o metadatos).
6. Prueba guiada, `/emp bugreport` y, en fase de tracker, `/emp dev tracker`.
7. Bug → reproducir, capturar, test, arreglar, suite, desplegar, volver a probar.

## Interface

El TOC declara `## Interface: 120100, 120105`: Retail 12.1.0 y PTR 12.1.5
(valor leído de `lastAddonVersion` en `_xptr_\WTF\Config.wtf`). Una sola build
carga en ambos clientes.

## Release

Nada de dev/alpha sale del PTR. Solo con autorización explícita:
`1.1.0-beta.1` → `tools/package_mitzumplus.py --check` → tag → GitHub Release →
CurseForge. Los materiales de `release/` siguen nombrando `1.0.0-beta.1` hasta
entonces (el static check lo permite para versiones `-dev`/`-alpha`).
