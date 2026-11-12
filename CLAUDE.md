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
  - Prueba única sin ventana: `Godot --headless --path . res://tests/test_all.tscn` (imprime `RESULTADO: OK`). Corre en orden
    las partes de `tests/suites/` (una por hito, `test_<nombre>.gd`, más `test_starting_company`); cada parte emite `finished(fallos,
    comprobaciones)` en vez de cerrar el juego, y `test_all` quita entre partes las conexiones de señales que dejó. Solo algunas:
    `… res://tests/test_all.tscn -- --only=reception,administration`. Una parte nueva se agrega a `SUITES` en `tests/test_all.gd`.

## Herramientas de desarrollo

Solo para probar y balancear; no son parte del juego. Investigación de por qué estas: `docs/investigacion_assets.md`.

- **`DevTools`** (autoload, `scripts/debug/dev_tools.gd`): en compilaciones de depuración registra monitores
  `Quincena/…` (saldo, deuda, nómina por pagar, valor, reputación, empleados, puntos por hora, ánimo/estrés/energía
  medios, día). Se ven en el editor en Depurador → Monitores mientras el juego corre. Un monitor nuevo se agrega en
  `get_monitor_sources()`. Los quita en `_exit_tree`: si quedan registrados, Godot se cae al cerrar (signal 11).
- **Panku Console 1.7.9** (`addons/panku_console/`, MIT, autoload `Panku`): consola en el juego con la tecla de la
  izquierda del 1. Los comandos propios están en `DevCommands` (`scripts/debug/dev_commands.gd`) con el nombre `qo`:
  `qo.help()`, `qo.add_money(50000)`, `qo.skip_days(3)`, `qo.skip_hours(5)`, `qo.set_mood(20)`, `qo.set_stress(90)`,
  `qo.set_energy(10)`. Cada comando usa las funciones públicas de los sistemas; su texto de ayuda es una constante
  `_HELP_<función>`. No se modifica el código del addon.
- En una exportación release `DevTools` no hace nada y `panku/disable_on_release=true` quita el autoload `Panku`.
  Al crear el primer preset de exportación, excluir también `addons/panku_console/*` y `scripts/debug/*`.

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
- `scripts/characters/` personajes · `scripts/staff/` cargos y nombres · `scripts/projects/` catálogo de contratos · `scripts/ui/` interfaz · `data/` datos de diseño · `assets/` arte · `scripts/debug/` herramientas de desarrollo · `addons/` addons de terceros · `tests/` pruebas sin ventana
- Escena inicial: `scenes/main_menu.tscn`; la partida es `scenes/main.tscn`.
  La interfaz superpuesta es `Hud` (dinero y reloj) más `BuildPanel` (botón Construir y herramientas).
  Todo movimiento de dinero pasa por `Economy` con un concepto (queda en `Economy.movements`, los últimos 200, y en
  `Economy.month_totals`, totales por concepto del mes actual y el anterior). Menú Banco (`BankPanel`): saldo, resumen del
  mes con «<»/«>» y movimientos, los nuevos arriba; no pausa. Los botones de la barra miden `Hud.MENU_BUTTON_SIZE`.
  `SaveManager.new_game()` prepara una partida nueva; la oficina inicial está en `data/starting_office.json` y, con
  `SaveManager.start_with_demo` (false por defecto: el CEO solo; true para probar), `StartingCompany.apply()` la convierte en la empresa de `data/starting_company.json`:
  Mediana empresa, local de 22×18, 40 empleados en 6 equipos con líder, 2 gerentes, 2 ejecutivos, apoyo y 7 contratos en curso
  (`Staff.hire_directly`, `Projects.create_offer`). `test_starting_company` y `test_dev_tools` lo ponen en true un momento.
  Las partidas se guardan en `user://saves/` (`autosave.json` y `slot_1.json` … `slot_5.json`); las pruebas
  ponen `SaveManager.save_dir = "user://test_saves"` para no tocar las del jugador.
- Autoloads (en este orden): `EventBus`, `GameClock`, `Economy`, `OfficeState`, `Staff`, `Projects`, `Products`, `Bank`, `Company`, `SaveManager`, y para desarrollo `Panku` y `DevTools` (ver Herramientas de desarrollo).
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
  o `NO_TEAM`); un equipo lleva uno a la vez y el tope de contratos es equipos con miembros + 1 (el CEO). Menú Horarios (`TeamsPanel`, antes Equipos).
  Personal, Proyectos, Horarios, Banco y Empresa ocupan el lado izquierdo: abrir uno cierra los otros.
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
- Departamentos y ejecutivos (`departments` en `data/staff.json`; `executive`, $9,000, desde Mediana empresa, Oficina única): Desarrollo
  (programador y QA), Diseño, Ventas (vendedor) y Administración (sin cargos todavía). Un departamento existe con algún empleado de sus cargos.
  Un gerente asciende a ejecutivo; cada ejecutivo dirige uno (`department`, por defecto el primero libre; `set_executive_department` desde el
  organigrama, uno por departamento). Desde `from_stage` 3, lo que dirige el CEO rinde según cuántos dirige (`ceo_factors` 100/100/85/70/55 %);
  con ejecutivo, 1 + 10 % × liderazgo/100, presente o no (`Staff.get_department_factor`). Multiplica la producción de sus miembros y la parte
  del vendedor en la oferta diaria (`Projects.get_offer_chance`). El ejecutivo de Administración puede entrevistar: `interview["by"]` es "ceo" o
  su clave (`start_interview(id, by_executive)`, botón «Delegar» en Personal). Gerentes y ejecutivos no entran en equipos.
- Horas extra y noche (`overtime` en `data/staff.json`): `WorkSchedule.overtime` (0–4) son las últimas horas de la jornada
  (`make_shift(entrada, días, extra)`, `set_team_shift(…, extra)`). Cada hora del horario que termina (esté o no en la oficina) suma a
  `overtime_pay` (hora = sueldo/30/8 × 1.5) y `night_pay` (+20 % de 22 a 6); la nómina las pasa a `owed` (`owed_overtime`, `owed_night`) y las
  cobra como «Horas extra» y «Recargo nocturno». Meta de estrés +5 por hora extra; con horas de noche, ánimo −10. Horario propio
  (`own_schedule`, `Staff.set_own_schedule`/`clear_own_schedule`, fila en la ficha): reemplaza el del equipo o el cargo. `ShiftEditor` son los
  controles de turno de Equipos y la ficha.
- Plantillas y agenda (`Staff.shift_templates`: `{id, name, schedule}`; empiezan Diurno, Tarde y Noche de `teams.templates`): un equipo
  sigue una (`template_id`) o tiene turno propio (`NO_TEMPLATE`); su `schedule` siempre es el vigente. `set_template_shift` cambia la plantilla
  y todos sus equipos; `set_team_shift` suelta la plantilla; borrar una deja a sus equipos con su turno. `Staff.get_agenda(día)` da 24 estados por
  equipo y persona con horario propio (`AGENDA_GAP` = equipo con miembros trabajando sin su líder, desde Startup); `get_agenda_gaps` los textos.
  Horarios tiene tres vistas (`set_view`): Equipos, Plantillas y Agenda (un día a la vez).
- Recepción y visitas (`visits` en `data/contracts.json`): `receptionist` ($700, desde Startup, Ventas) trabaja en una silla delante del frente
  de un mostrador (`reception_counter`, `is_counter`) dentro de la Recepción (`Workstations.RECEPTION`, uno por mostrador). Desde Startup y con
  Recepción que funciona (`Projects.visits_enabled`), cada oferta nueva llega con 40 % como visita (`Projects.visits`: `{id, offer, arrived_at,
  leaves_at}`); espera 3 h (6 con `waiting_sofa`). Al terminar cada hora, si hubo recepcionista en su puesto (`Staff.is_reception_attended`)
  la oferta entra en la bandeja; si no, al llegar `leaves_at` se va. Las visitas cuentan para el tope de la bandeja. `EventBus.visits_changed`;
  `main.gd` dibuja a cada cliente (`Visitor`) en `Projects.get_waiting_spots()` (sofá primero); no cuentan para la oficina vacía. La agenda
  tiene la fila Recepción con huecos «nadie en la Recepción». Los muebles tienen `short_name` para el botón del modo construcción.
- Contador y limpieza (`accounting` y `cleaning` en `data/staff.json`; Administración): `accountant` ($1,300, desde Startup, Área de trabajo).
  Con un contador en la empresa (`Staff.has_accountant`) el mantenimiento (`Economy.get_monthly_maintenance`) baja 10 % y la tasa de los préstamos
  nuevos (`Bank.get_monthly_rate`) 1 punto, los dos × el factor de Administración; 3 días antes de cada nómina y del día 1 avisa si el saldo de hoy no
  alcanza (`Bank.get_due_on_first`, `Staff.estimate_payroll`). Suciedad en cada habitación (`room["dirt"]`, 0–100, la sigue en `RoomRules.reconcile`,
  falta = 0): cada hora trabajada en un puesto suma 1 a la habitación del puesto (la mitad con `trash_can`, zafacón $30); desde 50 la meta de ánimo
  de quienes trabajan ahí baja 10 (`Staff.works_in_dirty_room`). `cleaner` ($500, desde el inicio) tiene su puesto en un armario (`is_closet`) dentro
  de un Cuarto de limpieza (`Workstations.CLEANING_ROOM`, uno por armario); en su turno quita 25/h × factor a la habitación más sucia y `main.gd` lo
  manda ahí (`Staff.get_cleaning_room`). `EventBus.dirt_changed`; `DirtOverlay` dibuja manchas. Botones del modo construcción en filas de 6.
- Competencia (`competition` en `data/staff.json`): cada medianoche (`Staff._update_morale`) otra empresa puede ofrecerle a un SemiSenior o
  Senior, o a un líder, gerente o ejecutivo (cuentan como Senior), su sueldo +15–30 % (`outside_offer`: `{salary, until_day}`, 5 días).
  `Staff.get_offer_chance`: Senior 1 %/día, SemiSenior 0.5 %, ×3 si gana menos que su nivel, ×0.3 desde el 110 %, leal ×0.25, ambicioso ×2.
  Un aumento que la iguala la cierra (+25 de ánimo; `match_offer`); `let_go` o el plazo lo sacan («Liquidación por irse a otra empresa»).
  La ficha muestra el aviso y «Igualar ($X)» / «Dejar ir».
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
- Sala de servidores (`OfficeState.SERVER_ROOM`, desde Pequeña empresa): funciona con `server_rack` ($3,000) y `air_conditioner` ($800, una
  casilla de piso hasta los objetos de pared del hito 45). `OfficeState.get_server_room()` / `get_server_capacity()` (racks de la sala
  que funciona; 1 rack = 1 unidad, los productos usan 1/3/8). Todo mueble con `monthly_cost` (cada rack $100, esté donde esté) se cobra el
  día 1 como «Mantenimiento de servidores» (`Economy.get_monthly_server_cost`, con el descuento del contador, y en su aviso). Builder
  `room_status` dice los racks; Empresa tiene la sección Servidores.
- Productos (`Products`, `ProductCatalog`, `data/products.json`; desde Pequeña empresa con una Sala de servidores que funcione): tipos App móvil,
  Software en la nube y Videojuego (reparto de puntos por fase) y tamaños 1,500/5,000/15,000 puntos (racks 1/3/8 e ingreso al lanzarlo, hito 42).
  Un producto es como un contrato sin cliente ni plazo (`points`, `progress`, errores con `Production.handle_bugs`/`note_workers`, `team_id`);
  comparte el tope con los contratos (`Projects.get_project_count`, `limit_problem`) y un equipo lleva un proyecto a la vez
  (`Projects.first_free_team`, `release_team` en los dos lados). Terminado avisa y queda en desarrollo hasta el lanzamiento; abandonar lo
  quita sin costo. Para el ánimo cuenta como trabajo (`Staff._contract_of`). Proyectos tiene las pestañas Contratos y Productos
  (`set_tab`); Horarios ofrece los productos en la lista de cada equipo (opciones con metadata, no ids: `add_item` con −1 pone uno automático).
- Comprobación de la fase 4 (`test_phase4`): desde el CEO solo, una política de jugador construye por pasos (puestos, Recepción,
  terreno al este, oficinas únicas y Cuarto de limpieza al norte, más terreno), contrata por vacantes una plantilla (4 equipos de
  2 diseñadores, 4 programadores y 2 QA con líder, vendedores, contador, recepcionista, limpieza, gerente y ejecutivo) que rellena
  si alguien se va, le da a cada equipo el contrato más grande y al CEO solo pequeños; guarda 1.5 meses de gastos. Llega a Mediana
  empresa (~mes 13) e imprime un resumen por mes; compara 3 meses con el CEO dirigiendo 4 departamentos contra un ejecutivo.
- `GameConstants` (`scripts/autoload/game_constants.gd`) es una clase con `class_name`, no un autoload.

## Forma de trabajo

- Un hito por sesión; no adelantar trabajo de hitos posteriores.
- Antes de dar un hito por terminado, comprobar su criterio de aceptación.
- Cada hito agrega su parte en `tests/suites/` y la suma a `test_all`.
- La lista de hitos está en la sección 15.4 de `docs/diseno.md` (fase 1, hitos 0–9), en la 16.3 (fase 2, hitos 10–19), en la 17.3 (fase 3, hitos 20–29), en la 18.3 (fase 4, hitos 30–39) y en la 19.3 (fase 5, hitos 40–49).

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
| 33 | Departamentos y ejecutivos | ✅ Completado (desde Mediana empresa, que pide solo 40 empleados; ascender un gerente o contratarlo; el ejecutivo rinde siempre, sin depender de estar presente; el CEO con 3+ departamentos rinde menos; Administración solo entrevista, el jugador elige quién) |
| 34 | Horas extra y turno de noche | ✅ Completado (0–4 h extra al final del turno a 1.5×; +20 % de 22 a 6; se pagan por hora de horario en la nómina siguiente con su concepto; estrés +5 por hora extra y ánimo −10 de noche; horario propio desde la ficha, también sin equipo) |
| 35 | Agenda semanal | ✅ Completado (Equipos pasa a Horarios con vistas Equipos, Plantillas y Agenda; Diurno, Tarde y Noche editables; cada equipo sigue una plantilla o tiene turno propio; agenda de un día con huecos sin líder desde Startup; la recepción se marca en el hito 36) |
| 36 | Recepcionista y visitas | ✅ Completado (mostrador $600 con silla delante, uno por mostrador; recepcionista $700 desde Startup; visitas solo con Recepción armada, 40 % de las ofertas; esperan 3 h o 6 con sofá $300; atendidas al terminar una hora con recepcionista; el cliente se ve en la Recepción) |
| 37 | Contador y limpieza | ✅ Completado (contador $1,300 desde Startup: −10 % mantenimiento y −1 punto a préstamos nuevos por el factor de Administración, avisos 3 días antes si el saldo no alcanza; suciedad +1 por persona-hora, zafacón la mitad, desde 50 ánimo −10; personal de limpieza $500 con armario en un Cuarto de limpieza, −25/h a la habitación más sucia) |
| 38 | Competencia por empleados | ✅ Completado (SemiSenior, Senior y dirección; 1 %/día Senior, ×3 mal pagado, ×0.3 bien pagado, leal ×0.25, ambicioso ×2; oferta +15–30 % con 5 días; igualar retiene, «Dejar ir» o el plazo lo sacan) |
| 39 | Comprobación de la fase | ✅ Completado (CEO solo a Mediana empresa en ~13 meses sin préstamos ni quiebra; medianos pagan $9,000–16,500 para que un equipo de 8 con líder deje margen; un ejecutivo en Desarrollo sube los ingresos ~75 % frente al CEO con 4 departamentos; partida nueva otra vez con el CEO solo) |
| 40 | Sala de servidores | ✅ Completado (rack $3,000 y aire acondicionado $800 de piso; funciona con los dos; capacidad = racks de la sala; $100/mes por rack el día 1 aparte del local, −10 % con contador; sección Servidores en Empresa) |
| 41 | Desarrollo de productos | ✅ Completado (App móvil, Software en la nube y Videojuego en 3 tamaños; desde Pequeña empresa con Sala de servidores que funcione, los racks se piden al lanzar en el hito 42; comparte el tope y los equipos con los contratos; pestaña Productos en Proyectos; abandonar con confirmación) |
