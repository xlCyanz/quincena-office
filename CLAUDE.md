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
    hay una por hito: `test_grid_camera` (1), `test_game_clock` (2), `test_new_game` (3), `test_ceo` (4), `test_construction` (5), `test_furniture` (6), `test_rooms` (7), `test_money_ui` (8), `test_save` (9), `test_vacancies` (10), `test_hiring` (11), `test_workday` (12), `test_payroll` (13), `test_contracts` (14), `test_teams` (15), `test_production` (16), `test_bugs` (17), `test_delivery` (18), `test_morale` (19), `test_bank` (20), `test_credit` (21), `test_loans` (22), `test_default` (23), `test_emergency` (24), `test_land` (25), `test_company_value` (26), `test_stages` (27), `test_objectives` (28), `test_phase3` (29), `test_promotions` (30), `test_leaders` (31) y `test_managers` (32)

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
- El local es un conjunto de casillas (`Lot`, `OfficeState.lot`; `lot_rect` es solo el rectángulo que lo encierra). Crece comprando
  terreno (`Builder.quote_land`/`buy_land`, herramienta Terreno: lado, ancho × fondo y posición; $150/m² más la cerámica a mitad de precio, en
  `data/construction.json`): se apoya en la casilla más lejana de cada fila, así rellena huecos y cobra solo lo nuevo; no sale del
  solar ni tapa la entrada; el borde compartido se abre y el contorno nuevo lleva pared. Una habitación puede crecer hacia el
  terreno nuevo pero no juntarse con otro espacio. El mantenimiento se cobra por `lot.get_area()`.
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
- Autoloads (en este orden): `EventBus`, `GameClock`, `Economy`, `OfficeState`, `Staff`, `Projects`, `Bank`, `Company`, `SaveManager`.
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
  mediano desde Startup o con un vendedor, grande con 4 ★ y exige Sala de reuniones. Plazo = puntos ÷ `points_per_day` del tamaño
  (17 el CEO, 34 un equipo, 100) × `days_slack` (1.1–1.4), hacia arriba (`ContractCatalog.get_days_range`). Contratos en curso: uno por equipo (mínimo 1).
  Aceptar cobra el anticipo (30 %, si trae). El menú Proyectos (`ProjectsPanel`) no pausa.
- Equipos (`Staff.teams`): `{id, name, members, schedule}`; un empleado está como mucho en un equipo. El turno es hora de entrada
  y días (mínimo 1 de descanso); dura 9 h (8 + almuerzo). El contrato guarda quién lo lleva (`team_id`: equipo, `Projects.CEO_TEAM`
  o `NO_TEAM`); un equipo lleva uno a la vez y el tope de contratos es equipos con miembros + 1 (el CEO). Menú Equipos (`TeamsPanel`).
  Personal, Proyectos, Equipos, Banco y Empresa ocupan el lado izquierdo: abrir uno cierra los otros.
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
- Ascensos (`Staff.promote`, `get_promotion_progress`; `data/staff.json`, promotion): `projects_worked` cuenta los contratos entregados en
  los que sumó puntos (el contrato anota `worked_by`; `EventBus.contract_delivered`); los vendedores cuentan los aceptados mientras estaban
  (`EventBus.contract_accepted`). Con 3/30, 8/90 y 15/180 (contratos/días desde `hired_day`) la ficha muestra la fila Ascender con un sueldo
  mayor que el actual (sugerido el del nivel nuevo); la habilidad principal sube al mínimo del nivel y cuenta como aumento (`_apply_raise`).
- Líderes de equipo (`team_leader`, cargo sin niveles: `fixed_salary` y `min_stage` en `data/staff.json`; `StaffCatalog.has_levels`, `describe_title`):
  desde Startup un Senior asciende a líder (`next_role` en el progreso; si era miembro de un equipo sin líder pasa a liderarlo) o se contrata con
  su vacante (sin nivel). El equipo guarda `leader_id`; el líder no es miembro, no suma puntos y sigue el turno (`get_team_of` lo encuentra).
  `add_to_team` con un líder lo nombra líder (uno por equipo); hasta `max_members` 10 miembros; quitarlo lo deja líder sin equipo.
  Desde Startup un equipo sin su líder presente (`is_leader_present`) rinde `no_leader_factor` 75 % (`Staff.get_team_factor` en `Projects.get_workers`).
- Gerentes (`manager`, $6,000, desde Pequeña empresa; `management` en `data/staff.json`): escalera `ladder` Senior → líder → gerente
  (`StaffCatalog.get_next_role`). Trabajan en una Oficina única (`workplace`): `Workstations.find_all(…, room_type)` da puestos con `room_type`;
  en una oficina basta escritorio y silla delante, uno por oficina. `get_free_workstations(role)` / `get_station_problem(role)`. Ascender a otro
  lugar de trabajo cambia la silla (`blocker` "station" si no hay oficina libre). Cada líder guarda `manager_id` (0 = el CEO); `set_manager` desde el
  organigrama de Personal: hasta 5 líderes por gerente y 5 líderes con equipo para el CEO (un sexto no se nombra en `add_to_team`). Con el gerente
  presente sus equipos rinden ×1.1 y la meta de estrés de sus miembros baja 10. Al irse el gerente, sus líderes vuelven al CEO.
- Banco (`Bank`, `data/bank.json`): calificación A–E por puntaje = base 50 (C) + ingresos de contratos del mes pasado (hasta +20, con $25,000)
  + bienes (reventa de muebles y computadoras, hasta +10) + antigüedad (+2/mes, hasta +10) + pagos a tiempo (+2, hasta +10)
  − 15 por atraso; A ≥75, B ≥60, C ≥45, D ≥30. Se recalcula el día 1 y en el momento de un atraso. Pagos por
  `EventBus.payment_recorded`: nómina (Staff) y mantenimiento (Economy; atraso si deja saldo negativo). Límite = múltiplo de
  la letra × ingreso del mes pasado, mínimo $5,000. `EventBus.bank_changed` refresca el Banco. Lee su JSON al usarlo.
  Préstamos (`Bank.loans`: base, rate, months, paid, refinanced): interés simple con la tasa de la letra al pedirlo, cuota =
  total / meses el día 1 siguiente (la última cierra el redondeo); varios mientras el capital pendiente (`get_debt`) no pase el
  límite; monto desde $1,000 de a $500, plazo 3–24. Saldar = capital pendiente + 1 mes de interés. Refinanciar una vez: +3 a +12
  meses (tope 24) a tasa +1 punto, repartiendo el capital pendiente.
- Mora y embargo (`Bank`): la cuota que no alcanza queda en `loan["overdue"]` con 5 % de recargo (atraso) y se paga sola, de la más
  vieja a la más nueva, al subir el saldo («Cuota atrasada»); con atrasos la cuota nueva va a la cola. `overdue_months` cuenta los días 1
  seguidos con atrasos (pagar todo lo pone en 0): a los 2 aviso y no presta, a los 3 embargo. `Embargo.plan` (funciones puras, reventa
  con computadora) se lleva decoración, después puestos libres y al final ocupados, lo que más vale primero; la silla y el escritorio
  del CEO nunca. El sobrante vuelve («Sobrante del embargo»). Si no alcanza: `Bank.game_over`, `EventBus.game_over(stats)`,
  `SaveManager` borra el autoguardado y deja de autoguardar, y `main.gd` para el reloj y abre `GameOverScreen` (estadísticas con
  `Staff.hired_count` y `Projects.best_reputation`; «Volver al menú»). El Banco muestra lo atrasado y qué haría hoy un embargo.
- Préstamo de emergencia (`Bank`): si la nómina (15 o 30) no alcanza, `Staff` emite `EventBus.payroll_short(falta, response)` antes de
  castigar; si el banco presta (menos de 2 meses debiendo) pone `response.held`, guarda `Bank.emergency_offer` (lo que falta a $100,
  12 %, 3 meses) y `Staff.payroll_held` espera. `main.gd` corta el salto (`GameClock.interrupt`), pausa y abre `EmergencyLoanDialog`.
  Aceptar: llega el dinero, `Staff` paga la nómina y cuenta a tiempo; el préstamo (`emergency`) no cuenta para el límite
  (`get_limit_debt`) ni se refinancia y cobra desde `first_due_day` (primer día 1 con ≥15 días). Rechazar: nómina debida como en la
  fase 2. Se guarda la oferta pendiente y al cargar vuelve a preguntar. `SaveManager` reinicia o importa `Economy` al final.
- Valor de la empresa (`Company`): dinero + reventa de muebles y computadoras (`Bank.get_assets_value`) + terreno a lo pagado
  (`OfficeState.land_paid`) − deuda con el banco (capital pendiente y atrasos, `Bank.get_seizable_debt`). Avisa con
  `EventBus.company_value_changed`; se muestra en el `Hud` tras las estrellas («Valor $X», rojo si es negativo) y en el Banco
  arriba, tras el saldo, con su detalle. Paredes y pisos no cuentan como bienes.
- Etapas (`Company.stage`, 0 = Emprendimiento … 4 = Corporación; `data/stages.json`, se lee al usarlo): requisitos (empleados sin el CEO,
  contratos entregados, equipos completos = diseñador + programador + QA; productos y ejecutivos valen 0 hasta las fases 4 y 5). Se
  revisan cada día (`day_changed`) y nunca bajan; al subir `EventBus.stage_changed` y aviso (al cargar, en silencio). Tope por préstamo
  (`max_loan`: $10k, $30k, $30k, sin tope; `Bank.get_max_request`), habitaciones por etapa (`rooms`: oficina única y sala de servidores
  en Pequeña empresa; `Builder.quote_mark_room` las rechaza y `BuildPanel` las deshabilita) y contratos medianos con `min_stage` 2
  o un vendedor. Menú Empresa (`CompanyPanel`, lado izquierdo, no pausa): etapa, requisitos de la siguiente, reputación, valor e
  ingresos y gastos del mes (los préstamos van aparte, no son ingreso). El tope por préstamo no va en `unlocks`: lo cuenta
  `Company.get_new_unlocks`. Las pruebas viejas fijan `Company.stage` cuando necesitan algo bloqueado.
- Objetivos guiados (`Company.objectives_done`; `data/objectives.json`, 15 en orden): se ven los 3 primeros sin cumplir
  (`ObjectivesPanel`, izquierda bajo el dinero, plegable). Las condiciones miran el estado (habitación, cargos, empleados,
  `Projects.accepted_count`, entregados, equipos, etapa, terreno, estrellas, valor) y se revisan con las señales de esos sistemas;
  al cumplirse uno avisa, paga «Objetivo cumplido» y/o `Projects.add_reputation` una sola vez y entra el siguiente.
  `SaveManager` envuelve preparar/cargar en `Company.begin_load`/`finish_load` para no revisar con el estado a medias; una
  partida sin `objectives_done` marca al cargar los que ya cumple, sin recompensa. `main.gd` pliega la lista mientras hay un
  panel izquierdo abierto y al cerrarlo vuelve como el jugador la tenía. Las pruebas que miden saldo o reputación exactos
  marcan todos los objetivos como cumplidos en su `_new_game`. Una recompensa se paga mientras se avisa otro cambio: quien
  escuche `balance_changed` o `company_value_changed` lee el valor actual (`Economy.balance`, `Company.get_value()`), no el de la señal.
- Comprobación de la fase 3 (`test_phase3`): simula con una política simple (aceptar lo que se pueda, entregar lo terminado, el CEO
  de 8 a 17) un CEO solo 3 meses, el primer equipo con $5,000 a 12 meses durante 6 y una empresa que deja de pagar; imprime un resumen
  por mes. Sirve para ajustar `data/bank.json`, `data/stages.json` y `data/contracts.json`.
- `GameConstants` (`scripts/autoload/game_constants.gd`) es una clase con `class_name`, no un autoload.

## Forma de trabajo

- Un hito por sesión; no adelantar trabajo de hitos posteriores.
- Antes de dar un hito por terminado, comprobar su criterio de aceptación.
- La lista de hitos está en la sección 15.4 de `docs/diseno.md` (fase 1, hitos 0–9), en la 16.3 (fase 2, hitos 10–19), en la 17.3 (fase 3, hitos 20–29) y en la 18.3 (fase 4, hitos 30–39).

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
| 22 | Préstamos | ✅ Completado (varios préstamos; tope por etapa en el hito 27; la cuota sin dinero deja saldo negativo hasta la mora del hito 23) |
| 23 | Mora y embargo | ✅ Completado (5 % de recargo por cuota; meses seguidos debiendo globales; al pagar todo vuelve a 0; el sobrante se devuelve; lo del CEO no se embarga; préstamo de emergencia en el hito 24) |
| 24 | Préstamo de emergencia | ✅ Completado (días 15 y 30; aceptar = nómina a tiempo sin golpe; monto = lo que falta redondeado a $100; primera cuota el primer día 1 con ≥15 días; no se refinancia) |
| 25 | Compra de terreno | ✅ Completado (local como conjunto de casillas; $150/m² + cerámica a mitad de precio; no tapa la entrada; rellena huecos cobrando solo lo nuevo; controles −/+ con vista previa; una habitación no se junta con otro espacio) |
| 26 | Valor de la empresa | ✅ Completado (dinero + reventa + terreno a lo pagado − deuda; paredes y pisos no suman; en el Hud tras las estrellas y en el Banco con detalle) |
| 27 | Etapas y menú Empresa | ✅ Completado (se revisan cada día y nunca bajan; el CEO no cuenta como empleado; tope por préstamo $10k/$30k/$30k/sin tope; oficina única y sala de servidores desde Pequeña empresa; medianos desde Startup o con vendedor; líderes, gerentes, productos y ejecutivos en fases siguientes) |
| 28 | Objetivos guiados | ✅ Completado (15 objetivos hasta Pequeña empresa, $300–$5,000 y algunos con ★; 3 visibles; se pliega con los paneles izquierdos y vuelve como estaba) |
| 29 | Comprobación de la fase | ✅ Completado (CEO solo ~$4,000/mes; primer equipo ~$9,000/mes contra $3,600 de sueldos y paga su préstamo; dejar de pagar embarga en la 3.ª cuota; plazos según los puntos; A más difícil) |
| 30 | Ascensos | ✅ Completado (cuentan los contratos entregados en que sumó puntos; cancelados no; vendedores por contratos aceptados; sueldo nuevo mayor que el actual; el progreso solo se ve en la ficha) |
| 31 | Líderes de equipo | ✅ Completado (ascender un Senior o contratarlo desde Startup; $4,200 sin niveles; no produce; sin líder presente 75 % desde Startup; quitarlo lo deja líder sin equipo; el liderazgo aún no cambia nada) |
| 32 | Gerentes y organigrama | ✅ Completado (ascender un líder o contratarlo desde Pequeña empresa; Oficina única con escritorio y silla, una persona por oficina; el jugador asigna los líderes en el organigrama; +10 % solo con el gerente presente; el estrés baja siempre) |
