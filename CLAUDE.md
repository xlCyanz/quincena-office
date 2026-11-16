# Quincena Office

Juego de gestión de oficina en pixel art isométrico: el jugador es el CEO de una empresa de software que contrata,
construye su oficina, toma contratos y paga la nómina cada 15 días.

| Documento | Qué tiene |
| --- | --- |
| `docs/diseno.md` | Diseño completo y lista de hitos. Es la fuente de verdad. |
| `docs/sistemas.md` | Referencia de cada sistema con sus nombres de código (leer la sección del sistema antes de tocarlo). |
| `docs/hitos.md` | Estado de cada hito y lo que dejó decidido. |
| `docs/sprites_128.md` | Reglas del arte de sprites (128 px). |
| `docs/investigacion_assets.md` | Por qué estas herramientas de desarrollo. |

## Motor y comandos

- Godot **4.7.2** estable, GDScript, renderizador **Compatibility** (`gl_compatibility`).
- Ejecutable (no está en el PATH): `/Applications/Godot.app/Contents/MacOS/Godot`.

| Para | Comando |
| --- | --- |
| Ejecutar sin ventana | `Godot --headless --path . --quit-after 5` |
| Reimportar y regenerar `.uid` | `Godot --headless --editor --quit` |
| Todas las pruebas (~150 s) | `Godot --headless --path . res://tests/test_all.tscn` → `RESULTADO: OK` |
| Algunas pruebas | `… res://tests/test_all.tscn -- --only=reception,administration` |
| Exportación de prueba | `tests/export_desktop.sh` (macOS, Windows y Linux a `build/`, que no se versiona) |

- Pruebas: una parte por hito en `tests/suites/test_<nombre>.gd`, en orden en `SUITES` de `tests/test_all.gd`. Cada parte
  emite `finished(fallos, comprobaciones)`; una que pasa de `MAX_SUITE_SECONDS` (60 s) cuenta como fallo.
- Las pruebas no tocan los datos del jugador: `SaveManager.save_dir = "user://test_saves"` y
  `Settings.path = "user://test_settings.cfg"`.
- La exportación necesita las plantillas de 4.7.2 en `~/Library/Application Support/Godot/export_templates/4.7.2.stable`.

## Herramientas de desarrollo

Solo para probar y balancear; no viajan en las exportaciones.

- **`DevTools`** (`scripts/debug/dev_tools.gd`): monitores `Quincena/…` en Depurador → Monitores. Uno nuevo va en
  `get_monitor_sources()`. Se quitan en `_exit_tree` (si quedan, Godot se cae al cerrar).
- **Panku Console 1.7.9** (`addons/panku_console/`): consola con la tecla a la izquierda del 1. Comandos propios en
  `DevCommands` (`scripts/debug/dev_commands.gd`) como `qo`: `qo.help()`, `qo.add_money(50000)`, `qo.skip_days(3)`,
  `qo.event("birthday")`… Cada uno usa funciones públicas; su ayuda es una constante `_HELP_<función>`. No se modifica el addon.
  La opción `console_overlay` de Ajustes deja la consola siempre visible.
- Las exportaciones excluyen `addons/panku_console/*`, `scripts/debug/*`, `tests/*` y `addons/quincena_export/*`; el plugin
  `QuincenaExport` quita los autoloads `Panku` y `DevTools` (`DEV_AUTOLOADS`).

## Convenciones de código

- GDScript con tipado estático siempre (parámetros, retornos y variables).
- Archivos, variables y funciones en inglés y `snake_case`; clases en `PascalCase`.
- Comentarios y textos para el jugador en español. Comentarios cortos y al punto: qué hace y el porqué que no se ve en el
  código; sin historia de hitos.
- Los `*.uid` que genera Godot se versionan junto a su script.

## Reglas de arquitectura

- Casilla isométrica de 64×32 px; 1 casilla = 1 m². La lógica trabaja en coordenadas de cuadrícula; solo se pasa a píxeles para dibujar.
- Los sistemas se comunican por señales de `EventBus`, no con referencias directas entre ellos.
- Los valores de diseño (precios, sueldos, tamaños) viven en `data/` o en `GameConstants`, nunca sueltos en la lógica.
- Todo sistema con estado implementa `export_state() -> Dictionary` e `import_state(state: Dictionary) -> void`.
- Todo movimiento de dinero pasa por `Economy` con un concepto.
- Las paredes van en los bordes de las casillas (`Vector3i(x, y, eje)`, ver `GridEdge`); los caminos usan `AStarGrid2D` a doble
  resolución para que bloqueen el paso.
- Una habitación es `{type, cells}` y ocupa siempre un espacio entero (cerrado por paredes, con puerta).
- La vista es fija desde una esquina. Todo se controla con ratón; el teclado es un extra.
- Un flag de sistema que solo usan las pruebas (`*_enabled`, no se guarda) lo apaga `test_all` en las partes anteriores a su hito.

## Estructura

| Carpeta | Contenido |
| --- | --- |
| `scenes/` | Escenas: `main_menu.tscn` (inicial) y `main.tscn` (la partida) |
| `scripts/autoload/` | Sistemas globales |
| `scripts/office/` | Cuadrícula, construcción, muebles y dibujo del local |
| `scripts/characters/` | Personajes (CEO, empleados, visitas) y turnos |
| `scripts/staff/`, `scripts/projects/`, `scripts/bank/` | Catálogos y funciones puras de cada sistema |
| `scripts/ui/` | Interfaz |
| `scripts/debug/` | Herramientas de desarrollo |
| `data/` | Datos de diseño (JSON) |
| `assets/` | Arte; `tools/sprites/` lo genera |
| `addons/` | Addons de terceros y el plugin de exportación |
| `tests/` | Pruebas sin ventana |

- Autoloads, en este orden: `EventBus`, `Settings`, `GameClock`, `Economy`, `OfficeState`, `Staff`, `Projects`, `Products`,
  `Bank`, `Company`, `Events`, `Tutorial`, `SaveManager`; para desarrollo `Panku` y `DevTools`.
- `GameConstants` (`scripts/autoload/game_constants.gd`) es una clase con `class_name`, no un autoload.

## Forma de trabajo

- Un hito por sesión; no adelantar trabajo de hitos posteriores.
- Antes de dar un hito por terminado, comprobar su criterio de aceptación.
- Cada hito agrega su parte en `tests/suites/`, la suma a `SUITES`, anota su sistema en `docs/sistemas.md` y su estado en
  `docs/hitos.md`.
- Hitos 0–69 completados (fases 1–7 y los agregados de la 21.6); la fase 8 (arte y sonido) está en curso.
