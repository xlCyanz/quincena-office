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
- Las paredes van en los bordes de las casillas, no ocupan casilla.
- Todo se controla con ratón; el teclado es un extra.

## Estructura

- `scenes/` escenas · `scripts/autoload/` sistemas globales · `scripts/office/` cuadrícula y construcción
- `scripts/characters/` personajes · `scripts/ui/` interfaz · `data/` datos de diseño · `assets/` arte
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
| 1 | Cuadrícula y cámara | Pendiente |
| 2 | Reloj | Pendiente |
| 3 | Inicio de partida | Pendiente |
| 4 | CEO | Pendiente |
| 5 | Construcción: pisos y paredes | Pendiente |
| 6 | Muebles | Pendiente |
| 7 | Habitaciones | Pendiente |
| 8 | Dinero e interfaz | Pendiente |
| 9 | Guardado | Pendiente |
