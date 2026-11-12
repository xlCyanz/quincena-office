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
    hay una por hito: `test_grid_camera` (1), `test_game_clock` (2), `test_new_game` (3), `test_ceo` (4), `test_construction` (5), `test_furniture` (6), `test_rooms` (7), `test_money_ui` (8), `test_save` (9) y `test_vacancies` (10)

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
- Una habitación es `{type, cells}` y ocupa siempre un espacio entero (zona cerrada por paredes y puertas, con puerta);
  `RoomRules` detecta los espacios y reubica las habitaciones al cambiar paredes.
- El mapa es el solar fijo de `GameConstants.MAX_SITE_SIZE` (40×40) con el local en el centro (`OfficeState.site_rect`);
  fuera del local se dibuja terreno. La cámara se mueve libre por el solar: su centro no sale del rombo del mapa.
  Al empezar encuadra la oficina (`OfficeCamera.fit_rect`); «Ver oficina» o la tecla F la vuelven a encuadrar.
- Las paredes y puertas del contorno del local no se compran ni se venden; los pisos no se quitan, solo se cambian por otro.
- Todo se controla con ratón; el teclado es un extra.

## Estructura

- `scenes/` escenas · `scripts/autoload/` sistemas globales · `scripts/office/` cuadrícula y construcción
- `scripts/characters/` personajes · `scripts/staff/` cargos y nombres · `scripts/ui/` interfaz · `data/` datos de diseño · `assets/` arte · `tests/` pruebas sin ventana
- Escena inicial: `scenes/main_menu.tscn`; la partida es `scenes/main.tscn`.
  La interfaz superpuesta es `Hud` (dinero y reloj) más `BuildPanel` (botón Construir y herramientas).
  Todo movimiento de dinero pasa por `Economy` con un concepto (queda en `Economy.movements`).
  `SaveManager.new_game()` prepara una partida nueva; la oficina inicial está en `data/starting_office.json`.
  Las partidas se guardan en `user://saves/` (`autosave.json` y `slot_1.json` … `slot_5.json`); las pruebas
  ponen `SaveManager.save_dir = "user://test_saves"` para no tocar las del jugador.
- Autoloads (en este orden): `EventBus`, `GameClock`, `Economy`, `OfficeState`, `Staff`, `SaveManager`.
- `Staff` guarda vacantes y candidatos (`data/staff.json`, `data/names.json`); su azar usa una semilla guardada
  en la partida (`Staff.set_seed` en las pruebas). El menú Personal (`StaffPanel`) no pausa el tiempo.
- `GameConstants` (`scripts/autoload/game_constants.gd`) es una clase con `class_name`, no un autoload.

## Forma de trabajo

- Un hito por sesión; no adelantar trabajo de hitos posteriores.
- Antes de dar un hito por terminado, comprobar su criterio de aceptación.
- La lista de hitos está en la sección 15.4 de `docs/diseno.md` (fase 1, hitos 0–9) y en la 16.3 (fase 2, hitos 10–19).

## Estado actual

| Hito | Descripción | Estado |
| --- | --- | --- |
| 0 | Proyecto | ✅ Completado |
| 1 | Cuadrícula y cámara | ✅ Completado |
| 2 | Reloj | ✅ Completado |
| 3 | Inicio de partida | ✅ Completado (menú y estado; paredes, muebles y CEO de la oficina inicial se añaden en sus hitos) |
| 4 | CEO | ✅ Completado (escritorio y silla iniciales dibujados fijos; horario lun–vie 8–17) |
| 5 | Construcción: pisos y paredes | ✅ Completado (precios provisionales en `data/construction.json`; paredes bajas) |
| 6 | Muebles | ✅ Completado (planta pequeña a $40 provisional; la silla del CEO no se vende) |
| 7 | Habitaciones | ✅ Completado (tipos y requisitos en `data/rooms.json`; los muebles que aún no existen se listan como faltantes) |
| 8 | Dinero e interfaz | ✅ Completado (primer mantenimiento el día 1 del mes 2; el saldo puede quedar negativo por gastos obligatorios) |
| 9 | Guardado | ✅ Completado (autoguardado al pasar a las 00:00 y ranuras manuales 1–5 desde Ajustes) |
| 10 | Vacantes y candidatos | ✅ Completado (programador, diseñador, QA y vendedor; llegan a las 9:00, esperan 3 días; contratar es el hito 11) |
| 11 | Contratación | Pendiente (fase 2) |
| 12 | Jornada de los empleados | Pendiente (fase 2) |
| 13 | Nómina y despidos | Pendiente (fase 2) |
| 14 | Ofertas de contratos | Pendiente (fase 2) |
| 15 | Equipos y turnos | Pendiente (fase 2) |
| 16 | Producción | Pendiente (fase 2) |
| 17 | Errores y pruebas | Pendiente (fase 2) |
| 18 | Entrega y reputación | Pendiente (fase 2) |
| 19 | Ánimo y renuncias | Pendiente (fase 2) |
