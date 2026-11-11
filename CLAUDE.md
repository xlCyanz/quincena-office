# Quincena Office

Juego de gestión de oficina en pixel art isométrico: el jugador es el CEO de una empresa
de software que contrata, construye su oficina, toma contratos y paga la nómina cada 15 días.
El diseño completo vive en `docs/diseno.md`; es la fuente de verdad.

## Motor

- Godot **4.7.2** estable (`4.7.2.stable.official`), GDScript.
- Renderizador: **Compatibility** (`gl_compatibility`), pensando en móvil.
- Ejecutable en macOS (no está en el PATH): `/Applications/Godot.app/Contents/MacOS/Godot`.
  - Ejecutar sin ventana: `Godot --headless --path . --quit-after 5`
  - Reimportar y regenerar `.uid`: `Godot --headless --editor --quit`
  - Pruebas sin ventana: `Godot --headless --path . res://tests/<prueba>.tscn` (imprime `RESULTADO: OK`);
    hay una por hito: `test_grid_camera` (1), `test_game_clock` (2), `test_new_game` (3), `test_ceo` (4) y `test_construction` (5)

## Convenciones de código

- GDScript con tipado estático siempre (parámetros, retornos y variables).
- Archivos, variables y funciones en inglés y `snake_case`; clases en `PascalCase`.
- Comentarios y todos los textos visibles para el jugador en español.
- Los archivos `*.uid` que genera Godot se versionan junto a su script.

## Reglas de arquitectura

- Casilla isométrica de 64×32 px; 1 casilla = 1 m².
- Toda la lógica trabaja en coordenadas de cuadrícula y solo se convierte a píxeles para dibujar.
- Los sistemas se comunican por señales de `EventBus`, no con referencias directas entre ellos.
- Los valores de diseño (precios, sueldos, tamaños) viven en `data/` o en `GameConstants`,
  nunca escritos sueltos dentro de la lógica.
- Todo sistema con estado implementa `export_state() -> Dictionary` e `import_state(state: Dictionary) -> void`.
- Las paredes van en los bordes de las casillas, no ocupan casilla. Un borde es `Vector3i(x, y, eje)` (ver `GridEdge`);
  los caminos usan `AStarGrid2D` a doble resolución para que las paredes de borde bloqueen el paso.
- Todo se controla con ratón; el teclado es un extra.

## Estructura

- `scenes/` escenas · `scripts/autoload/` sistemas globales · `scripts/office/` cuadrícula y construcción
- `scripts/characters/` personajes · `scripts/ui/` interfaz · `data/` datos de diseño · `assets/` arte · `tests/` pruebas sin ventana
- Escena inicial: `scenes/main_menu.tscn`; la partida es `scenes/main.tscn`.
  `SaveManager.new_game()` prepara una partida nueva; la oficina inicial está en `data/starting_office.json`.
- Autoloads (en este orden): `EventBus`, `GameClock`, `Economy`, `OfficeState`, `SaveManager`.
- `GameConstants` (`scripts/autoload/game_constants.gd`) es una clase con `class_name`, no un autoload.

## Forma de trabajo

- Un hito por sesión; no adelantar trabajo de hitos posteriores.
- Antes de dar un hito por terminado, comprobar su criterio de aceptación.
- La lista de hitos está en la sección 15.4 de `docs/diseno.md`.

## Estado actual

| Hito | Descripción | Estado |
| --- | --- | --- |
| 0 | Proyecto | ✅ Completado |
| 1 | Cuadrícula y cámara | ✅ Completado |
| 2 | Reloj | ✅ Completado |
| 3 | Inicio de partida | ✅ Completado (menú y estado; paredes, muebles y CEO de la oficina inicial se añaden en sus hitos) |
| 4 | CEO | ✅ Completado (escritorio y silla iniciales dibujados fijos; horario lun–vie 8–17) |
| 5 | Construcción: pisos y paredes | ✅ Completado (precios provisionales en `data/construction.json`; paredes bajas) |
| 6 | Muebles | Pendiente |
| 7 | Habitaciones | Pendiente |
| 8 | Dinero e interfaz | Pendiente |
| 9 | Guardado | Pendiente |
