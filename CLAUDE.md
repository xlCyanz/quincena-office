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
    hay una por hito: `test_grid_camera` (1), `test_game_clock` (2), `test_new_game` (3), `test_ceo` (4), `test_construction` (5), `test_furniture` (6), `test_rooms` (7), `test_money_ui` (8), `test_save` (9), `test_vacancies` (10), `test_hiring` (11), `test_workday` (12), `test_payroll` (13), `test_contracts` (14), `test_teams` (15), `test_production` (16), `test_bugs` (17), `test_delivery` (18), `test_morale` (19), `test_bank` (20) y `test_credit` (21)

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
- `scripts/characters/` personajes · `scripts/staff/` cargos y nombres · `scripts/projects/` catálogo de contratos · `scripts/ui/` interfaz · `data/` datos de diseño · `assets/` arte · `tests/` pruebas sin ventana
- Escena inicial: `scenes/main_menu.tscn`; la partida es `scenes/main.tscn`.
  La interfaz superpuesta es `Hud` (dinero y reloj) más `BuildPanel` (botón Construir y herramientas).
  Todo movimiento de dinero pasa por `Economy` con un concepto (queda en `Economy.movements`, los últimos 200, y en
  `Economy.month_totals`, totales por concepto del mes actual y el anterior). Menú Banco (`BankPanel`): saldo, resumen del
  mes con «<»/«>» y movimientos, los nuevos arriba; no pausa. Los botones de la barra miden `Hud.MENU_BUTTON_SIZE`.
  `SaveManager.new_game()` prepara una partida nueva; la oficina inicial está en `data/starting_office.json`.
  Las partidas se guardan en `user://saves/` (`autosave.json` y `slot_1.json` … `slot_5.json`); las pruebas
  ponen `SaveManager.save_dir = "user://test_saves"` para no tocar las del jugador.
- Autoloads (en este orden): `EventBus`, `GameClock`, `Economy`, `OfficeState`, `Staff`, `Projects`, `Bank`, `SaveManager`.
- `Staff` guarda vacantes y candidatos (`data/staff.json`, `data/names.json`); su azar usa una semilla guardada
  en la partida (`Staff.set_seed` en las pruebas). El menú Personal (`StaffPanel`) no pausa el tiempo.
  `Staff.employees` son los contratados; cada uno ocupa la silla de un puesto con `assigned_to = Staff.employee_key(id)`.
- Un puesto de trabajo (`Workstations`) es una silla delante del frente de un escritorio con computadora, ambos dentro
  de un Área de trabajo que funciona; cada escritorio sirve a una sola silla. Sus muebles no se venden ni giran mientras está ocupado.
- Jornada: `Staff.is_expected(key, día, hora)` dice quién debe estar en la oficina; `main.gd` se lo pasa cada hora a los
  personajes (`OfficeCharacter`, base de `Ceo` y `Employee`). Cada empleado tiene el turno de su equipo o, sin equipo, el horario
  de su cargo (`data/staff.json`); `WorkSchedule` admite turnos que cruzan la medianoche y cada uno almuerza a la 4.ª hora de su jornada. El CEO no tiene horario: llega solo a las 8 en días hábiles y se queda hasta que el
  jugador lo manda a casa (`Staff.ceo_at_work`, botón «CEO: irse a casa»). Con la oficina vacía el tiempo salta a la próxima llegada.
  Un clic en un empleado abre su ficha (`EmployeeCard`).
- Nómina (`Staff`): cada empleado gana sueldo/30 por día desde `paid_until`; los días 15 y 30 se paga todo o nada.
  Lo que no alcanza queda en `owed`, baja el ánimo y se paga solo al alcanzar el saldo. Despedir cobra lo ganado más
  lo debido (puede dejar saldo negativo). Los avisos al jugador van por `EventBus.notice` y los muestra el `Hud`.
- `Projects` guarda reputación (empieza en 1 ★), ofertas y contratos (`data/contracts.json`, `ContractCatalog`). A las 9:00
  caducan las ofertas viejas (5 días) y llega una con 50 % + 25 % por vendedor (bandeja de 6). Tamaños: pequeño siempre,
  mediano con 2 ★ o un vendedor, grande con 4 ★ y exige Sala de reuniones. Contratos en curso: uno por equipo (mínimo 1).
  Aceptar cobra el anticipo (30 %, si trae). El menú Proyectos (`ProjectsPanel`) no pausa.
- Equipos (`Staff.teams`): `{id, name, members, schedule}`; un empleado está como mucho en un equipo. El turno es hora de entrada
  y días (mínimo 1 de descanso); dura 9 h (8 + almuerzo). El contrato guarda quién lo lleva (`team_id`: equipo, `Projects.CEO_TEAM`
  o `NO_TEAM`); un equipo lleva uno a la vez y el tope de contratos es equipos con miembros + 1 (el CEO). Menú Equipos (`TeamsPanel`).
  Personal, Proyectos, Equipos y Banco ocupan el lado izquierdo: abrir uno cierra los otros.
- Producción (`Production`, funciones puras; `Projects._produce` al terminar cada hora): puntos/h por nivel (13.3) × energía
  (100 % desde 50, baja hasta 50 % en 0) × ánimo (100 % desde 50, baja hasta 70 % en 0) × (1 + `production_bonus` de la computadora). Cada uno suma en la fase de su cargo; si
  está cerrada o llena ayuda al 50 % en la primera con lugar. Una fase abre con la anterior al 50 % y nunca pasa su %. El CEO es
  generalista (SemiSenior) y no rinde en entrevistas ni dormido (de 22 a su llegada). `progress` guarda puntos con decimales.
- Errores (`data/contracts.json`, bugs): programar genera `bugs_hidden` (1 cada 20/30/45/70 puntos por nivel, el doble cansado o con estrés ≥70, sin acumularse);
  cada punto de pruebas encuentra cada oculto con probabilidad cobertura × puntos / pruebas del contrato (QA 3, otros 0.2) y
  pasan a `bugs_found`; programadores o CEO los corrigen a 3 puntos (`bugs_fixed`) antes de programar. Con pruebas al 100 % QA
  sigue revisando. El azar sale de `Projects._rng`; `Production.apply` devuelve qué hizo cada uno.
- Entrega (`Projects.deliver`/`cancel`, `preview_delivery`; valores en `data/contracts.json`, delivery): en cualquier momento,
  pago × hecho × (1 − atraso − errores) − anticipo (mín. 0); penalidades sumadas (3 días + 2 errores = 81 %). Errores entregados =
  ocultos + encontrados; el panel solo muestra los conocidos. Reputación 1–5: limpio +0.3, −0.05/error y −0.1/día (hasta −0.5),
  cancelar −0.5 y devuelve el anticipo. Atrasado, se sortea 3–10 días (`cancel_day`): ese día el cliente cancela sin pagar
  más (el anticipo queda). Estrellas enteras (hacia abajo) + valor, arriba a la izquierda en el `Hud`. `history` y `delivered_count`.
- Ánimo y estrés (`Staff._update_morale`, cada medianoche después de la nómina; valores en `data/staff.json`, morale): cada día se
  acercan 3 / 5 puntos a su meta. Ánimo: 70 + sueldo frente al de su nivel (≥110 % +15, ≥100 % +5, ≥90 % −10, menos −25) − 15 sin
  contrato (salvo vendedores) − 20 con nómina debida − 10 con estrés ≥70. Estrés: 20 + 30 con contrato atrasado + 20 si la energía
  bajó de 50. Con ánimo <30 o estrés >80 tres días seguidos avisa (`quit_day`) y a los 5 días renuncia (cobra lo ganado + lo debido,
  «Liquidación por renuncia»). `Staff.give_raise` (aumento ≥10 % lo retiene, +25 de ánimo; lo ganado antes queda en `carry`).
  Bajo el 110 % y desde 30 días del último aumento, 2 %/día pide +10 % (`raise_request`, 3 días): aceptar +10, negar o dejarlo pasar −15.
  La ficha muestra avisos, pedido (Dar el aumento / Negar) y la fila Aumento; su contenido se desplaza si no entra.
- Banco (`Bank`, `data/bank.json`): calificación A–E por puntaje = base 50 (C) + ingresos de contratos del mes pasado (hasta +20)
  + bienes (reventa de muebles y computadoras, hasta +10) + antigüedad (+2/mes, hasta +10) + pagos a tiempo (+2, hasta +20)
  − 15 por atraso; A ≥75, B ≥60, C ≥45, D ≥30. Se recalcula el día 1 y en el momento de un atraso. Pagos por
  `EventBus.payment_recorded`: nómina (Staff) y mantenimiento (Economy; atraso si deja saldo negativo). Límite = múltiplo de
  la letra × ingreso del mes pasado, mínimo $5,000. `EventBus.bank_changed` refresca el Banco. Lee su JSON al usarlo.
- `GameConstants` (`scripts/autoload/game_constants.gd`) es una clase con `class_name`, no un autoload.

## Forma de trabajo

- Un hito por sesión; no adelantar trabajo de hitos posteriores.
- Antes de dar un hito por terminado, comprobar su criterio de aceptación.
- La lista de hitos está en la sección 15.4 de `docs/diseno.md` (fase 1, hitos 0–9), en la 16.3 (fase 2, hitos 10–19) y en la 17.3 (fase 3, hitos 20–29).

## Estado actual

| Hito | Descripción | Estado |
| --- | --- | --- |
| 0 | Proyecto | ✅ Completado |
| 1 | Cuadrícula y cámara | ✅ Completado |
| 2 | Reloj | ✅ Completado |
| 3 | Inicio de partida | ✅ Completado (menú y estado; paredes, muebles y CEO de la oficina inicial se añaden en sus hitos) |
| 4 | CEO | ✅ Completado (escritorio y silla iniciales dibujados fijos; desde el hito 12 sin horario) |
| 5 | Construcción: pisos y paredes | ✅ Completado (precios provisionales en `data/construction.json`; paredes bajas) |
| 6 | Muebles | ✅ Completado (planta pequeña a $40 provisional; la silla del CEO no se vende) |
| 7 | Habitaciones | ✅ Completado (tipos y requisitos en `data/rooms.json`; los muebles que aún no existen se listan como faltantes) |
| 8 | Dinero e interfaz | ✅ Completado (primer mantenimiento el día 1 del mes 2; el saldo puede quedar negativo por gastos obligatorios) |
| 9 | Guardado | ✅ Completado (autoguardado al pasar a las 00:00 y ranuras manuales 1–5 desde Ajustes) |
| 10 | Vacantes y candidatos | ✅ Completado (programador, diseñador, QA y vendedor; llegan a las 9:00, esperan 3 días; contratar es el hito 11) |
| 11 | Contratación | ✅ Completado (oferta ≥ lo pedido acepta, desde el 85 % contraoferta, debajo rechaza y se va; entrevista de 2 h del CEO en su horario; la vacante se cierra al contratar; el empleado aún no se dibuja) |
| 12 | Jornada de los empleados | ✅ Completado (horario por cargo; almuerzo 12–13 fuera; energía −6/h trabajando y +4/h fuera; ficha solo informativa) |
| 13 | Nómina y despidos | ✅ Completado (primera nómina proporcional; sin dinero queda deuda y −20 de ánimo; despido −5 a compañeros, −10 si hubo otro en 7 días; botón en la ficha con confirmación) |
| 14 | Ofertas de contratos | ✅ Completado (primera oferta pequeña el día 1; tope de contratos = equipos, 1 sin equipos hasta el hito 15; penalidades solo se muestran hasta el hito 18) |
| 15 | Equipos y turnos | ✅ Completado (turno = entrada + días, 8 h fijas; almuerzo a la 4.ª hora; sin plantillas ni agenda; sin equipo = horario del cargo; el CEO lleva un contrato propio; sin recargo nocturno ni líderes) |
| 16 | Producción | ✅ Completado (CEO 24/día con jornada de 8 h, hasta 39 si se queda hasta las 22; equipo de 3 Junior 48/día; sin efecto de habilidad ni líder; el ánimo se suma en el hito 19) |
| 17 | Errores y pruebas | ✅ Completado (ocultos no se muestran; sin QA llega ~90 %, con QA ~10 % al terminar y 0 tras revisar; la penalidad se cobra en el hito 18) |
| 18 | Entrega y reputación | ✅ Completado (entrega en cualquier momento proporcional a lo hecho; cancelación del cliente sorteada; la reputación aún no cambia los candidatos) |
| 19 | Ánimo y renuncias | ✅ Completado (meta diaria de ánimo y estrés; 3 días mal → aviso de 5 días; aumento ≥10 % retiene; pedidos de aumento ~1 cada 2 meses; ánimo bajo 50 rinde hasta 70 % y estrés ≥70 duplica errores; la ficha muestra «Rinde N %»; el aviso del Hud se parte en líneas sin tapar dinero ni reloj) |
| 20 | Menú Banco | ✅ Completado (resumen por concepto del mes actual y el anterior; historial de 200 sin filtro; préstamos y calificación en sus hitos) |
| 21 | Calificación de crédito | ✅ Completado (puntaje con base C; historial = nómina y mantenimiento hasta el hito 22; límite mínimo $5,000; el contador llega en la fase 4) |
| 22 | Préstamos | Pendiente (fase 3) |
| 23 | Mora y embargo | Pendiente (fase 3) |
| 24 | Préstamo de emergencia | Pendiente (fase 3) |
| 25 | Compra de terreno | Pendiente (fase 3) |
| 26 | Valor de la empresa | Pendiente (fase 3) |
| 27 | Etapas y menú Empresa | Pendiente (fase 3) |
| 28 | Objetivos guiados | Pendiente (fase 3) |
| 29 | Comprobación de la fase | Pendiente (fase 3) |
