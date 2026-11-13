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
    Una parte que tarda más de `MAX_SUITE_SECONDS` (60 s) cuenta como fallo (hito 67).
  - Exportación de prueba: `tests/export_desktop.sh` (exporta macOS, Windows y Linux a `build/`, que no se versiona, revisa cada
    paquete con `tests/export_check.gd` y arranca la app de macOS; imprime `RESULTADO: OK`). Necesita las plantillas de exportación
    de 4.7.2 en `~/Library/Application Support/Godot/export_templates/4.7.2.stable` (instaladas solo las de escritorio).

## Herramientas de desarrollo

Solo para probar y balancear; no son parte del juego. Investigación de por qué estas: `docs/investigacion_assets.md`.

- **`DevTools`** (autoload, `scripts/debug/dev_tools.gd`): en compilaciones de depuración registra monitores
  `Quincena/…` (saldo, deuda, nómina por pagar, valor, reputación, empleados, puntos por hora, ánimo/estrés/energía
  medios, día). Se ven en el editor en Depurador → Monitores mientras el juego corre. Un monitor nuevo se agrega en
  `get_monitor_sources()`. Los quita en `_exit_tree`: si quedan registrados, Godot se cae al cerrar (signal 11).
- **Panku Console 1.7.9** (`addons/panku_console/`, MIT, autoload `Panku`): consola en el juego con la tecla de la
  izquierda del 1. Los comandos propios están en `DevCommands` (`scripts/debug/dev_commands.gd`) con el nombre `qo`:
  `qo.help()`, `qo.add_money(50000)`, `qo.skip_days(3)`, `qo.skip_hours(5)`, `qo.set_mood(20)`, `qo.set_stress(90)`,
  `qo.set_energy(10)`, `qo.event("birthday")`. Cada comando usa las funciones públicas de los sistemas; su texto de ayuda es una constante
  `_HELP_<función>`. No se modifica el código del addon.
- En una exportación release `DevTools` no hace nada y `panku/disable_on_release=true` quita el autoload `Panku`.
  Los presets (`export_presets.cfg`) excluyen `addons/panku_console/*`, `scripts/debug/*`, `tests/*` y `addons/quincena_export/*`, y el
  plugin del editor `QuincenaExport` (`addons/quincena_export/`) quita los autoloads `Panku` y `DevTools` de toda exportación (también debug).

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
  fuera del local se dibuja terreno (`MapDecor`, hito 68). La cámara se mueve libre por el solar: su centro no sale del rombo del mapa.
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
  Construir va en secciones (`BuildPanel.SECTION_*`: Estructura, Muebles, Habitaciones y Terreno, con «?» y Salir en la misma fila): solo se ve
  la abierta (`set_section`, `get_section_of`); Muebles se parte por `category` de `data/furniture.json` (`categories`; `set_category`,
  `FurnitureCatalog.get_category`) con Girar y Mejorar en la fila de categorías; Terreno muestra solo su fila (la herramienta va en un botón
  oculto). `select_tool` abre la sección y la categoría; `get_button_toward(tool)` es el botón a pulsar para llegar (lo resalta el tutorial
  con `tool:`). Prueba `test_build_sections`.
  Todo movimiento de dinero pasa por `Economy` con un concepto (queda en `Economy.movements`, los últimos 200, y en
  `Economy.month_totals`, totales por concepto del mes actual y el anterior). Menú Banco (`BankPanel`): saldo, resumen del
  mes con «<»/«>» y movimientos, los nuevos arriba; no pausa. Los botones de la barra miden `Hud.MENU_BUTTON_SIZE`.
  `SaveManager.new_game()` prepara una partida nueva; la oficina inicial está en `data/starting_office.json` y, con
  `SaveManager.start_with_demo` (false por defecto: el CEO solo; true para probar), `StartingCompany.apply()` la convierte en la empresa de `data/starting_company.json`:
  Mediana empresa, local de 22×18, 40 empleados en 6 equipos con líder, 2 gerentes, 2 ejecutivos, apoyo y 7 contratos en curso
  (`Staff.hire_directly`, `Projects.create_offer`). `test_starting_company` y `test_dev_tools` lo ponen en true un momento.
  Las partidas se guardan en `user://saves/` (`autosave.json` y `slot_1.json` … `slot_5.json`); las pruebas
  ponen `SaveManager.save_dir = "user://test_saves"` para no tocar las del jugador.
- Autoloads (en este orden): `EventBus`, `Settings`, `GameClock`, `Economy`, `OfficeState`, `Staff`, `Projects`, `Products`, `Bank`, `Company`, `Events`, `Tutorial`, `SaveManager`, y para desarrollo `Panku` y `DevTools` (ver Herramientas de desarrollo).
- `Staff` guarda vacantes y candidatos (`data/staff.json`, `data/names.json`); su azar usa una semilla guardada
  en la partida (`Staff.set_seed` en las pruebas). El menú Personal (`StaffPanel`) no pausa el tiempo.
  `Staff.employees` son los contratados; cada uno ocupa la silla de un puesto con `assigned_to = Staff.employee_key(id)`.
- Un puesto de trabajo (`Workstations`) es una silla delante del frente de un escritorio con computadora, ambos dentro
  de un Área de trabajo que funciona; cada escritorio sirve a una sola silla. Sus muebles no se venden ni giran mientras está ocupado.
- Tiempo: 1 hora de juego = `GameConstants.SECONDS_PER_GAME_HOUR` (60 s reales a 1x; hasta el hito 69 eran 10 s). Las pruebas que
  esperan con topes en segundos (`test_ceo`, `test_workday`) los escalan por `SECONDS_PER_GAME_HOUR / 10`.
- Jornada: `Staff.is_expected(key, día, hora)` dice quién debe estar en la oficina; `main.gd` se lo pasa cada hora a los
  personajes (`OfficeCharacter`, base de `Ceo` y `Employee`). Cada empleado tiene el turno de su equipo o, sin equipo, el horario
  de su cargo (`data/staff.json`); `WorkSchedule` admite turnos que cruzan la medianoche y cada uno almuerza a la 4.ª hora de su jornada. El CEO no tiene horario: llega solo a las 8 en días hábiles (se le ve entrar a las 7:30 a abrir) y se queda hasta que el
  jugador lo manda a casa (`Staff.ceo_at_work`, botón «CEO: irse a casa»). Con la oficina vacía el tiempo salta a la próxima llegada.
  Un clic en un empleado abre su ficha (`EmployeeCard`). El muñeco se dibuja a `OfficeCharacter.BODY_SCALE` (0.8, unos 50 px de pie, a la escala
  de los muebles); sentado la cadera queda a `SEAT_HEIGHT_PX` y el icono de estado no se achica; `CLICK_AREA` ya va escalado.
  Caminan a `CHARACTER_WALK_SPEED` (1 casilla/s a 1x; con prisa, `OfficeCharacter.hurry`, × `CHARACTER_HURRY_FACTOR` 2 hasta llegar: quien entra después de su hora (`main._arrive_staggered`) y el candidato llamado a la entrevista) y hay una persona por casilla del local: cada uno ocupa la suya y, al
  caminar, la siguiente (`OfficeCharacter._occupants`, estático; `is_cell_taken`, `get_held_cells`). Si la siguiente está ocupada
  espera; cada `CHARACTER_REPATH_WAIT` busca un camino que esquive a los demás (`OfficePathfinder.find_path(…, avoid)`) y tras
  `CHARACTER_PASS_WAIT` pasa igual (dos de frente en un pasillo de una casilla). Aparece en la entrada si está libre; si no,
  espera en la calle sin verse. Fuera del local no hay límite. `main.gd` no manda a dos al mismo lugar: limpieza, almuerzo,
  pausas y visitas toman la casilla libre más cercana (`_cells_near`, `_free_spot_near`). Desde la calle se entra por turno (`_door_queue`, primero el que espera hace más); quien está afuera y debe irse se va sin cruzar la puerta (`update_routine`, `_walk_to` con `WALKING_OUT`). Prueba `test_walking`.
  Llegadas escalonadas (`arrivals` en `data/staff.json`): al empezar la jornada cada empleado entra entre −30 y +10 minutos de su hora
  (`Staff.get_arrival_offset(empleado, hora absoluta)`, fijo por persona y hora; 10 % tarde, impuntual 50 % y desde −10). `get_early_minutes`
  (turno que empieza la hora siguiente, sin tardanza sorteada: `_lateness_roll` predice `_check_arrivals`) y `get_late_minutes` (llegada de ahora).
  `main._arrive_staggered` guarda `_arrivals` (clave → minuto absoluto, `get_arrival_minute`) y `_process` lo revisa cada minuto; quien llega
  antes (`_early`, `is_waiting_shift`) espera de pie (`OfficeCharacter.standing`) en la Sala de descanso o da vueltas (`_waiting_spot`, cambia cada
  `wander_minutes`). Al terminar la jornada (no al almorzar) se queda 0–20 min (`Staff.get_leave_minutes`; `main._departures`, `get_pending_departures`, ficha
  «terminando antes de irse»). Solo visual: producción y presencia siguen por hora. La oficina vacía salta a la hora anterior y con `GameClock.skip_to_minute`
  al primero que entra. `Staff.arrival_spread_enabled` (no se guarda) es solo para pruebas: `test_all` lo apaga antes de `arrivals`.
  El CEO abre la oficina: llega siempre `ceo.open_minutes` (30) antes de su hora (`Staff.get_ceo_early_minutes`, `main._ceo_opens`) y va a su
  silla; `ceo_at_work` y su producción siguen empezando a las 8. Va primero en `get_characters`, así nadie entra antes que él.
- Nómina (`Staff`): cada empleado gana sueldo/30 por día desde `paid_until`; los días 15 y 30 se paga todo o nada.
  Lo que no alcanza queda en `owed`, baja el ánimo y se paga solo al alcanzar el saldo. Despedir cobra lo ganado más
  lo debido (puede dejar saldo negativo). Los avisos al jugador van por `EventBus.notice` y los muestra el `Hud`.
- `Projects` guarda reputación (empieza en 1 ★), ofertas y contratos (`data/contracts.json`, `ContractCatalog`). A las 9:00
  caducan las ofertas viejas (5 días) y llega una con 50 % + 25 % por vendedor (bandeja de 6). Tamaños: pequeño siempre,
  mediano desde Startup o con un vendedor, grande desde Mediana empresa con 4 ★ y exige Sala de reuniones (hito 47). Plazo = puntos ÷ `points_per_day` del tamaño
  (17 el CEO, 34 un equipo, 100) × `days_slack` (1.1–1.4), hacia arriba (`ContractCatalog.get_days_range`). Contratos en curso: uno por equipo (mínimo 1).
  Aceptar cobra el anticipo (30 %, si trae). El menú Proyectos (`ProjectsPanel`) no pausa.
- Equipos (`Staff.teams`): `{id, name, members, schedule}`; un empleado está como mucho en un equipo. El turno es hora de entrada
  y días (mínimo 1 de descanso); dura 9 h (8 + almuerzo). El contrato guarda quién lo lleva (`team_id`: equipo, `Projects.CEO_TEAM`
  o `NO_TEAM`); un equipo lleva uno a la vez y el tope de contratos es equipos con miembros + 1 (el CEO). Menú Horarios (`TeamsPanel`, antes Equipos).
  Personal, Proyectos, Horarios, Banco y Empresa ocupan el lado izquierdo: abrir uno cierra los otros.
- Producción (`Production`, funciones puras; `Projects._produce` al terminar cada hora): puntos/h por nivel (13.3) × energía
  (100 % desde 50, baja hasta 50 % en 0) × ánimo (100 % desde 50, baja hasta 70 % en 0) × (1 + `production_bonus` de la computadora). Cada uno suma en la fase de su cargo; si
  está cerrada o llena ayuda al 50 % en la primera con lugar. Una fase abre con la anterior al 50 % y nunca pasa su %. El CEO es
  generalista (SemiSenior) y no rinde en entrevistas ni dormido (de 22 a su llegada). La entrevista dura `interview_minutes` (30) minutos de juego
  desde que empieza (`interview`: `starts_at`/`ends_at` en minutos absolutos, `Staff.get_absolute_minute`; termina en `Staff._process` o en la hora
  con `check_interview`); el CEO rinde esa hora × `get_ceo_interview_factor` (0.5); las partidas viejas (ends_at en horas) terminan a esa hora.
  Se ve: `main.interviewee` (un `Visitor` con `configure_candidate`, de pie) entra y espera del otro lado del escritorio de quien entrevista
  (`_interview_spot`, en su habitación) y se va al terminar o cortarse (`_sync_interview` con `staff_changed`); la ficha del ejecutivo dice
  «entrevistando a X». Prueba `test_interview_view`.
  Citas (`Staff.appointments`: `{candidate_id, by, at}` en minutos absolutos, guardadas): «Entrevistar»/«Delegar» llaman a `schedule_interview`
  (`appointment_problem`), que cita para el próximo día en que trabaja quien entrevista a su hora de entrada (el CEO a su llegada) o el siguiente
  hueco de media hora antes de su almuerzo (`_next_appointment_slot`, hasta `appointment_max_days`). `_check_appointments` (en `_process` y cada hora)
  a la hora, si quien entrevista está y no hay otra, llama al candidato (`_call_interview`: `called_at`, `starts_at`/`ends_at` = `INTERVIEW_NOT_STARTED`, `is_interview_started`); la media hora empieza cuando se sienta en la silla de visita (`main._on_interviewee_seated` → `start_called_interview`) o a los `interview_walk_max_minutes` (90) sin escena que lo dibuje; mientras camina el CEO rinde entero; a los `appointment_grace_minutes` sin él la cancela con
  aviso. El citado no se va (`_process_arrivals`). `get_appointment_arrival` (10–25 min antes, fijo por candidato): `main._sync_appointments` lo
  dibuja (`appointment_visitors`) de pie en la Recepción o junto a la entrada y `_sync_interview` lo pasa a `interviewee`. `start_interview` sigue
  empezando una al momento (pruebas). Prueba `test_appointments`.
- Silla de visita: la Oficina Ejecutiva y la Oficina única piden dos sillas (`count` en un requisito de `data/rooms.json`,
  `RoomRules.function_problems`): la de quien trabaja ahí y una de visita (`Staff.get_guest_chair`, silla sin dueño de su habitación), donde se
  sienta el candidato; sin ella la oficina no funciona (sin puesto) y no se entrevista. La oficina inicial y la empresa de prueba la traen.
  `RoomRules.counts_enabled` (no se guarda) es solo para pruebas: `test_all` lo apaga antes de `office_chairs`. `progress` guarda puntos con decimales.
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
  manda ahí (`Staff.get_cleaning_room`). `EventBus.dirt_changed`; `DirtOverlay` dibuja manchas. Botones del modo construcción en filas según el ancho (hito 65).
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
  contratos entregados, equipos completos = diseñador + programador + QA; productos lanzados y activos desde el hito 42). Se
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
- Sala de servidores (`OfficeState.SERVER_ROOM`, desde Pequeña empresa): funciona con `server_rack` ($3,000) y `air_conditioner` ($800, objeto
  de pared desde el hito 45). `OfficeState.get_server_room()` / `get_server_capacity()` (racks de la sala
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
- Lanzamiento (`Products.launch`/`launch_problem`, hito 42): terminado y con sus racks libres (`get_free_racks`; los racks se reparten en orden
  de lanzamiento, `get_supported_ids`, y sin los suyos tiene la mitad de los usuarios). Calidad 0–1 (`get_quality`): la mitad por el nivel medio de
  quien diseñó (`design_done`/`design_skill`, `Projects.get_workers` da `level`) y la mitad por errores al lanzar (10 por 1,000 puntos = 0); el
  ingreso va del 50 al 150 %. Cada día (`_live_day`): `curve` crece 30 días desde 5 % (vendedores +15 % de velocidad cada uno), 60 en el pico,
  120 de caída hasta 10 %; `production_bugs` suman `bug_loss` 0.5 %/día por error (hasta 70 %); cobra «Ingreso de productos». Actualización
  (`start_update`): proyecto `product["update"]` del 20 % de los puntos (`get_active_projects`, cuenta para el tope, `assign`/`abandon` por id de
  producto); al terminar corrige los errores y vuelve al pico. `retire` libera los racks. Valor de la empresa + `value_days` días de ingreso (540 desde el hito 49); Mediana empresa
  pide `products_launched` 1 y Corporación `active_products` 3 (`Company`). `test_phase4` arma la sala y un equipo hace un producto pequeño.
- Eventos (`Events`, `data/events.json`, hito 43): cada hora con el reloj de la partida andando (`GameClock.is_processing()` y sin pausa;
  construcción pausa) y sin tarjeta abierta, sale uno con probabilidad 1 / (`mean_days`[etapa] × 24) entre los que cumplen `conditions`
  (min_employees, min_stage, min_reputation, offer_room), por `weight`. Tarjeta `Events.card` (`trigger`, `choose`): `answer_seconds` 120 reales
  que solo corren con el reloj andando (`advance_countdown`, a cualquier velocidad); al acabarse elige al azar. Efectos: money (concepto «Evento»,
  `Economy.charge`), mood/energy/stress a todos (`Staff.change_all`), reputation, offer (`Projects.create_bonus_offer`). `EventCard` a la
  derecha bajo el reloj, plegable; `EventBus.event_started` corta el salto de horas (`main.gd`). Las pruebas con el reloj detenido no reciben
  eventos. Consola `qo.event("id")`.
- Lista de eventos (hito 44, los 16 de 10.2; la cabecera de `data/events.json` explica cada clave): condiciones también por opción y
  `weight_if` (factor si se cumplen); has_role/no_role, no_furniture, working_room, launched_product, tired. `target` (empleado, dos, producto,
  contrato, equipo con líder flojo, equipo con programador, computadora, entrega reciente, multa) se elige al abrir y queda en `card["target"]`;
  los montos (horas extra, multa, computadora, retenido) se calculan al abrir. Efectos nuevos: lose_work (`Projects.get_nominal_rate` × horas
  con `Projects.remove_work`, de la última fase hacia atrás), product_loss (`Products.add_user_loss`, una actualización lo recupera),
  contract_change (`Projects.change_scope`), withhold («Pago retenido» y `Events.scheduled` lo devuelve como «Pago atrasado»), mood_some,
  clean_all. Prevención: contador (sin multa, cobra en 3 días), archivero (multa a la mitad), baterías (sin apagón), personal de limpieza (sin
  oficina sucia), líder con liderazgo ≥60 (sin reunión inútil), Sala de descanso (café ×0.3). Muebles: inodoro, lavamanos, cafetera, baterías y archivero.
- Ambiente y decoración (`Ambiance`, funciones puras; `ambiance` y adornos en `data/furniture.json`, hito 45): ambiente de una habitación =
  puntos de adornos × 10 / área − amontonar (caben uno cada 4 m²; −15 con 50 % más escritorios, en proporción antes), redondeado entre −15 y +15; suma a la meta de ánimo de quien tiene
  su silla ahí (`Staff.get_workplace_room`, `get_ambiance`); la pecera (`stress_relief`) baja 5 la meta de estrés. Objetos de pared
  (`wall_mounted`: cuadro, reloj y el aire acondicionado): no ocupan casilla; `cell` es la casilla que miran y la pared queda detrás del frente
  (`FurnitureCatalog.get_wall_edge`); uno por cara (`OfficeState.find_wall_item`); una pared con algo colgado no se vende, ni pasa a puerta, ni
  la abre el terreno. La alfombra (`walkable`) ocupa casillas pero no tapa el paso: los caminos usan `OfficeState.get_blocking_cells`. Al cargar,
  un objeto de pared sin pared se cuelga en la cara libre más cercana de su habitación o se quita devolviendo su precio. El modo construcción
  cuelga en la pared más cercana al ratón y muestra el ambiente; la ficha dice «Trabaja en: … · Ambiente +N».
- Comprobación de la fase 4 (`test_phase4`): desde el CEO solo, una política de jugador construye por pasos (puestos, Recepción,
  terreno al este, oficinas únicas y Cuarto de limpieza al norte, más terreno), contrata por vacantes una plantilla (4 equipos de
  2 diseñadores, 4 programadores y 2 QA con líder, vendedores, contador, recepcionista, limpieza, gerente y ejecutivo) que rellena
  si alguien se va, le da a cada equipo el contrato más grande y al CEO solo pequeños; guarda 1.5 meses de gastos. Llega a Mediana
  empresa (~mes 13) e imprime un resumen por mes; compara 3 meses con el CEO dirigiendo 4 departamentos contra un ejecutivo.
- Calidades de muebles (hito 46, `data/furniture.json`): computadora básica/media/pro (`production_bonus` 0/0.15/0.3), segundo monitor
  (`is_monitor`, $300, +0.05, en `furniture["monitor"]` sobre un escritorio con computadora, uno por escritorio; se vende antes que la
  computadora), silla ergonómica ($250, `energy_per_work_hour` −4 en vez de −6: `Staff.get_work_energy`) y escritorio amplio ($350, 2×1,
  `mood_bonus` +5 a la meta de ánimo de su puesto: `Staff.get_desk_mood`, `Workstations.station_desk_of`). `upgrade_to` es la calidad
  siguiente; `Builder.quote_upgrade`/`upgrade` (herramienta Mejorar) la cambia en su lugar cobrando la diferencia, también en un puesto
  ocupado o la silla del CEO. El bono de un puesto es computadora + monitor (`Workstations.get_desk_bonus`, `bonus_of`, `bonuses_by_owner`
  con caché). `data/rooms.json` acepta la silla ergonómica y el escritorio amplio donde pedía silla y escritorio.
- Contratos grandes y élite (hito 47, `data/contracts.json`): grande (`min_stage` 4 = Mediana empresa, 4 ★) y `elite` «De élite» (`min_stage`
  5 = Corporación, 5 ★, puntos del grande, pago ×1.5, clientes de `elite_clients`); los dos exigen Sala de reuniones que funcione
  (`requires_room`, mesa de reuniones 2×2 $1,200). La Sala de reuniones (`unlocked_by_offer` en `data/rooms.json`) se marca solo desde que
  llega la primera oferta que la exige (`Projects.meeting_room_unlocked`, guardado; `_unlock_room_for` en `_make_offer`, aviso y
  `EventBus.rooms_unlocked`; partidas viejas la habilitan si ya hay una sala u oferta que la pide). `Company.room_lock_reason` da el motivo
  al modo construcción. Pantalla de presentaciones (de pared, $800): en una Sala de reuniones que funciona el peso de esos tamaños ×1.25
  (`Projects.get_size_weight`, `meetings.screen_weight_factor`). La pizarra queda para más adelante.
- Corporación y salir a bolsa (hito 48, `ipo` en `data/stages.json`): Corporación pide 4 ejecutivos y 3 productos activos. Siendo
  Corporación con valor de más de $5,000,000 (`Company.ipo_problem`) se avisa una vez (`ipo_announced`) y el menú Empresa ofrece
  «Salir a bolsa» con confirmación. `Company.go_public` no da dinero: guarda `public_day`, avisa y emite `EventBus.went_public(stats)`
  (`get_ipo_stats`); `main.gd` pausa, cierra los paneles y abre `IpoScreen` (estadísticas de 9.5 + empleados de hoy; «Seguir jugando»
  vuelve a la pausa de antes, «Volver al menú»). Después la partida sigue en modo libre y Empresa dice «Cotiza en bolsa desde el día X»;
  no se sale dos veces. El terreno no tiene tope propio: se compra hasta llenar el solar.
- Comprobación de la fase 5 (`test_phase5`, extiende `test_phase4`): corre el crecimiento de la fase 4 hasta Mediana empresa y sigue
  con su propia política (`_phase5`; los métodos que cambia llaman a `super` antes): agranda la Sala de servidores al norte, compra
  terreno al oeste (4 oficinas únicas y la Sala de reuniones, que arma al habilitarse) y al sur (28 puestos), suma vendedores y 3 equipos,
  3 equipos hacen productos medianos (racks al 50 %, lanzar sin errores conocidos, actualizar a los 90 días), los demás el contrato más
  grande que lleguen a hacer a tiempo (entrega tras 4 días de revisión), retiene gente, pide prestado con A–C, responde eventos al azar
  con el reloj «andando» (`GameClock.start`) y contrata los ejecutivos que faltan con 3 productos activos y el 60 % del valor de la bolsa.
  Llega a la bolsa ~20 meses después de Mediana empresa con ~60 % de ingresos de productos. Ajustó `data/products.json`: medianos
  $1,800/día y grandes $6,600 (×3; el pequeño sigue en $150) y `value_days` 540. Un equipo de 8 en contratos apenas paga su costo:
  la ganancia del final viene de los productos. La empresa de `data/starting_company.json` no se sostiene (≈$110k/mes de nómina,
  mucha dirección para 24 productores).
- Rasgos de producción (hito 50, `traits` en `data/staff.json`; ids y nombres en `data/names.json`): cada rasgo es un diccionario de efectos
  que leen las funciones de siempre. `Staff.get_trait_points_factor(persona, hora)` (perfeccionista −15 %, sociable −5 %, noctámbulo +20 % de 22 a 6
  y −10 % de día), `get_trait_bug_factor` (perfeccionista ×0.6 al programar) y `get_trait_find_factor` (×1.25 al probar; `worker["find_factor"]` en
  `Production.handle_bugs`) entran en `Projects.get_workers`; `get_mentor_factor` (+15 % a Pasantes y Juniors de su equipo con el mentor en turno,
  sin contarse a sí mismo) y `get_mentor_projects` (un contrato menos para ascender). Sociable: +5 a la meta de ánimo de todo su equipo, una vez
  (`get_team_trait_mood`); el noctámbulo no pierde ánimo por la noche (`night_mood_free`). Todos hacen efecto aunque no se conozcan; la ficha solo
  explica los conocidos (`Staff.describe_trait`) y «Rinde N %» no los cuenta. `_discover_traits` cada 15 días en la empresa revela el siguiente con aviso.
- Rasgos de conducta e historial (hito 51, `traits` en `data/staff.json`): impuntual (`late_chance` 20 %, `absent_chance` 2 %) se sortea al empezar
  cada turno (`Staff._check_arrivals`, azar fijo por `hash([semilla, id, hora])`, no gasta el de `Staff`): tarde falta 1 h, ausente toda la jornada
  (aviso «X faltó hoy al trabajo.»); se guarda en horas absolutas (`missing_from`/`missing_until`, `is_missing`) y `_is_working_at` lo descuenta.
  Adicto al café: −15 % de puntos sin café (`Staff.has_coffee()` = Sala de descanso que funciona y no `coffee_out_day`; el evento del café,
  «Esperar al pedido», aplica `coffee_out` ese día) y +2 de energía por hora trabajada con café. Ambicioso: `promotion_ready_day` anota desde
  cuándo puede ascender (`_update_promotion_waits`, antes del ánimo); a los 15 días sin ascenso −15 a la meta de ánimo (`is_waiting_promotion`);
  `promote` lo reinicia. Leal: renuncia tras el doble de días malos (`quit_days_factor`). Historial (`describe_history`, en la ficha): contratos,
  `bugs_caused` (`Production.handle_bugs` anota `item["bugs"]` y `Staff.note_bugs_caused`), `late_count`, `absent_count`, `on_time_count` y
  puntualidad (`get_punctuality`, −1 sin datos). `test_phase4` quita impuntual y adicto y olvida la espera del ambicioso (la política no asciende).
- Baños (hito 52, `bathrooms` en `data/staff.json`): capacidad (`Staff.get_toilet_capacity`) = inodoros (`is_toilet`) de los Baños que funcionan
  (`OfficeState.count_working_toilets`) − `broken_toilets`; hace falta 1 cada 10 presentes (`count_present(at)`: quienes trabajan esa hora y el CEO
  si está en el trabajo; `get_toilets_needed`, hacia arriba). Siempre aplica, también sin baño (el CEO solo rinde 95 %). Por inodoro que falta
  (`get_bathroom_shortage`) la producción de todos ×(1 − 5 %), hasta −20 % (`get_bathroom_factor`, en `Projects.get_workers` vía `shared["bathroom"]`);
  cada hora `_check_bathrooms` anota `bathroom_short_day` y la meta de ánimo baja 10 ese día y el siguiente. Los que no caben salen del edificio a
  buscar un baño y vuelven: `main._send_bathroom_trips(hora)` manda a cada sentado una vez cada `trip_every_hours` (6) horas, en su turno por `person_key.hash()`, hasta
  los que no caben (10 por inodoro que falta) ÷ 6 por hora (`OfficeCharacter.step_out`, actividad
  `STEPPING_OUT`; no vacía la oficina). «Baño dañado»: «Poner un cartel» aplica `break_toilet` (un inodoro deja de contar) y Empresa muestra la
  sección Baños con «Reparar el baño ($400)» (`Staff.repair_toilet`, «Reparación del baño»). `Staff.bathrooms_enabled` (no se guarda) es solo para
  pruebas: `test_all` lo apaga en las partes anteriores a `bathrooms` (oficinas sin baño con números exactos).
- Almuerzo dentro (hito 53, `lunch` en `data/staff.json`; nevera $400, microondas $150 y mesa de comedor 2×1 $300 con `lunch_part` y `dining_seats` 4
  en `data/furniture.json`): `OfficeState.get_lunch_tables`/`get_lunch_seats` cuentan las mesas de la Sala de descanso que funciona (`get_working_room`)
  solo si también tiene nevera y microondas. `Staff.get_lunch_inside(at)` da quiénes almuerzan dentro: el CEO en su hora y después los empleados por
  antigüedad en su 4.ª hora (sin tardanza ni ausencia) hasta llenar los asientos. Ellos recuperan `energy_factor` ×2 la energía de descanso y
  `Projects.get_workers` los suma a `work_factor` 0.5 (`shared["lunch"]`); los demás salen como siempre. `main._update_routines` los manda a una casilla
  libre junto a una mesa (`get_lunch_spots`, `set_seat`) y después a su lugar (`_home_spot`); la ficha dice «almorzando en la Sala de descanso».
- Sala de descanso y pausas (hito 54, `breaks` en `data/staff.json`; sofá $500 2×1 `rest_places` 2, dispensador de agua $120 `break_mood` 2, ping pong
  $700 2×2 `break_mood` 8 y `distraction` 0.03, máquina expendedora $900 `break_mood` 3 y `vending_income` 2): solo cuentan en la Sala de descanso que
  funciona (`OfficeState.get_break_room_items`) y uno de cada tipo (`get_break_room_effect`). Al empezar cada hora `Staff._decide_breaks` manda a una
  pausa a quienes trabajan en un cargo que produce con energía bajo 40, los más cansados primero, hasta llenar los lugares de los sofás
  (`get_rest_places`); `Staff.breaks` guarda hora absoluta → claves (la actual y la anterior; `get_breaks(at)`, `is_on_break`). En la pausa no
  produce (`Projects.get_workers`) y recupera +15; con café (`has_coffee`) +3 más, también al almorzar dentro. `get_break_mood` suma a la meta de ánimo
  de todos (en `_seat_lookup_cache` durante `_update_morale`); el ping pong multiplica los puntos de cada empleado por 0.97 (`shared["distraction"]`).
  `_note_presence` anota cada hora quién está (`present_today`) y al cambiar de día `_collect_vending` cobra $2 por persona («Máquina expendedora»).
  `main._update_routines` lleva a los que descansan junto a un sofá (`get_rest_spots`); la ficha dice «descansando en la Sala de descanso».
- Impresora, pizarra y ventanas (hito 55): impresora ($350, `accountant_boost` 1.25 en `data/furniture.json`): en el Área de trabajo donde está la
  silla de un contador (`Staff.get_printer_factor`) multiplica sus descuentos de mantenimiento y de tasa y el cobro del pago atrasado (`withhold` con
  `by_accountant`: días ÷ factor, 3 → 2; se resuelve en `Events._resolve`). Pizarra (de pared, $250, `meeting_board`): en una Sala de reuniones que
  funciona (`Projects.has_room_item(tipo, campo)`, que también usa la pantalla) la reunión inútil pierde la mitad de horas (`lose_work` con
  `halved_by {room, field}`) y los tamaños que exigen la sala traen `meetings.board_days_factor` 1.1 de plazo (`Projects._offer_days`, después del
  sorteo para no mover el azar). Ventana (`ConstructionCatalog.WINDOW`, $200, `ambiance` 4 en `data/construction.json`): solo cambia un tramo de
  pared del contorno (`Builder._is_window_swap`; la pared del contorno no se cobra ni devuelve, `_paid_kind`); venderla o pasarle Pared la deja
  pared; cierra como pared (`blocks_passage`, caminos, espacios) y nada se cuelga en ella. Suma sus puntos al ambiente de la habitación a la que da
  (`OfficeState.count_room_windows`, `Ambiance.get_detail(…, windows)`). Al comprar terreno las del borde que se abre se devuelven a la mitad
  (`window_refund`, «Construcción»). No cuentan como bienes. Herramienta Ventana en la sección Estructura (`BuildController.TOOL_WINDOW`).
- Candidatos según la empresa (hito 56, `hiring` en `data/staff.json`): el primer día de una vacante (`vacancy["first_done"]`, falta = true)
  llega la primera tanda `Staff.get_first_batch()` = 3 + (estrellas enteras − 3), al menos 1, más 1 con publicidad; después, cada día como antes
  (`_roll_daily`). Calidad (`get_candidate_quality`, ±0.8) = 2.5 × (sueldo ofrecido / tabla − 1) + 0.02 × ambiente medio de las Áreas de trabajo
  (`get_work_area_ambiance`); `quality_position` corre cada habilidad dentro de su rango (0.5 = la mitad de arriba); lo que piden no cambia. El
  «Premio de la industria» (efecto `candidates`, 7 días) suma 1 por día a cada vacante (`Staff.award_until`, guardado). Personal muestra el
  pronóstico bajo el sueldo (`describe_hiring_outlook`). `Staff.company_hiring_enabled` (no se guarda) es solo para pruebas: `test_all` lo apaga
  en las partes anteriores a `candidates` (cuentan candidatos y habilidades exactos; las simulaciones de fase siguen iguales).
- Iconos de estado y avisos con destino (hito 57, `status_icons` en `data/staff.json`): `Staff.get_status_icon(empleado)` da el primero de `order`
  que se cumple: `no_station` (sin silla), `tired` (energía < 30), `upset` (ánimo < 30 o aviso de renuncia), `stressed` (estrés ≥ 70) e `idle`
  (`is_idle`). `main.update_status_icons` lo pone en cada `Employee` (`OfficeCharacter.set_status_icon`, globo con signo de `STATUS_ICONS`) al
  cambiar la hora, el personal, la oficina o los proyectos; nunca por cuadro. Avisos: `EventBus.send_notice(destino, texto)` emite `notice` con
  `get_notice_target()` válido mientras dura; destinos `target_employee/contract/product/room/menu` ("staff", "projects", "teams", "bank",
  "company"). El `Hud` muestra el aviso con destino en celeste con «›»; un clic (`click_notice`) lo cierra y emite `notice_clicked`, y
  `main.open_notice_target` abre la ficha, Proyectos en su pestaña, el menú o centra la cámara en la habitación. `notice.emit(texto)` sigue
  siendo un aviso sin destino. Llevan destino los avisos del personal (renuncia, aumento, oferta de otra empresa, falta, rasgo, ascenso),
  contratos, productos, Banco, Empresa y la habitación sucia.
- Inversionista (hito 58, `investor` en `data/bank.json` y evento `investor` en `data/events.json`, desde Pequeña empresa): el target `investor`
  pide `Bank.make_investor_offer(rng)` (vacío si `investor_problem()`: ya hay uno, valor ≤ 0 o ingresos de contratos y productos del mes pasado bajo
  $5,000): efectivo 10–25 % del valor (de a $1,000), 12–24 meses y parte `investor_share` = efectivo × 1.6 / (ingreso del mes pasado × meses),
  entre 5 y 40 %. Aceptar (efecto `investor`, `Bank.accept_investor`) cobra «Inversión» (no es ingreso: Empresa lo muestra aparte) y guarda
  `Bank.investor` (`income_before` = lo del mes que no le toca). Cada día 1 `_charge_investor` cobra la parte de los ingresos del mes que terminó
  con `Economy.charge` («Pago al inversionista»), aunque deje el saldo negativo; al cumplir los meses termina con aviso. `get_investor_remaining`
  (parte × ingreso del mes pasado × meses que faltan) resta del valor como una parte más de `Company.get_value_parts`. Empresa y Banco tienen su
  sección. `Bank.investor_enabled` (no se guarda) es solo para pruebas: `test_all` lo apaga antes de `investor` (las simulaciones sortean igual).
- Comprobación de la fase 6 (`test_phase6`, extiende `test_phase5`, hito 59): la misma partida con todo encendido (rasgos sin quitar,
  baños, almuerzo, pausas, candidatos según la empresa e inversionista; responde los eventos al azar). La política suma desde el primer
  día una franja al sur de la Recepción (x 1–2, filas 8–17) con dos Baños y un inodoro cada 10 personas, y desde Startup otra al otro lado
  de la entrada (x 4–5, filas 8–22) con la Sala de descanso completa. Desde Mediana empresa compara 30 días: tal cual, sin esos muebles
  (≈ +40 % de puntos con ellos: se pagan en días) y sin rasgos (+5–6 %). Llega a la bolsa en ~16 meses desde Mediana empresa (la fase 5
  en 20; `_target_months` [12, 30]). Sin cambios de datos. Para que dure menos de un minuto, `OfficeState` guarda por hora las consultas
  de habitaciones que funcionan, mesas, muebles de la Sala de descanso e inodoros (`_query_cache`, se borra con `office_changed`, la hora,
  `new_game` e `import_state`) y `Staff` quién está presente y quién almuerza dentro (`get_present_keys`, `_present_cache`, `_lunch_cache`;
  se borran con la hora, `staff_changed`, `office_changed` y tras sortear las tardanzas). Las cachés solo se usan mientras el reloj procesa
  una hora (`GameClock.in_hour_tick`); fuera, por ejemplo en pruebas que cambian cosas a mano, se calcula de nuevo.
- Opciones (`Settings`, hito 60; `data/settings.json`): `user://settings.cfg` (`ConfigFile`, sección `options`), aparte de las partidas;
  `get_value`, `set_value` (valida tipo y rango, aplica, guarda y emite `EventBus.settings_changed`), `load_settings` (lo que falta o no sirve
  vuelve a su valor por defecto) y `reset_to_defaults`. Opciones: `fullscreen` (no hace nada sin ventana), `autosave` (`SaveManager`),
  `start_speed` (`GameClock.new_game`), `pause_on_build` y `pause_on_focus_loss` (`main.gd`, `on_focus_lost`). `test_all` usa
  `Settings.path = "user://test_settings.cfg"` con los valores por defecto. Ajustes (`SettingsPanel`) tiene las pestañas Guardar, Cargar y
  Opciones (`set_tab`); cargar y salir piden confirmación (`is_confirming`) y emiten `load_requested`/`quit_requested`; `main.gd` carga la
  ranura y vuelve a abrir la escena de juego. Los controles de opciones son `OptionsList` (también en el menú principal).
- Menú principal (`main_menu.gd`, hito 61): Continuar (la partida más reciente, `SaveManager.get_latest_slot` por `saved_at`; con empate el
  autoguardado; no aparece sin partidas), Nueva partida (con autoguardado pregunta antes: vista `confirm`), Cargar, Ajustes (`OptionsList`) y
  Salir. Vistas `buttons`/`load`/`options`/`confirm` (`get_view`). Las pruebas cambian `change_scene` y `quit_action` para no salir del menú.
- Menú de pausa (hito 62, `PauseMenu`, capa 15, se arma en `main.gd`): Esc (`main.handle_escape`, devuelve qué hizo) cierra primero lo
  abierto: la pregunta de Ajustes (`SettingsPanel.cancel_confirm`), Ajustes, la pregunta y la pausa, el modo construcción, la ficha y los
  paneles izquierdos; sin nada abre la pausa. Fin de partida, bolsa y préstamo de emergencia no se cierran con Esc. `set_pause_menu_open`
  cierra paneles y ficha, oculta la barra, apaga el reloj del `Hud` y guarda `_was_paused_before_pause`; Seguir (o Esc) lo devuelve.
  Guardar, Cargar y Ajustes cierran la pausa (el reloj vuelve a como estaba) y abren Ajustes en su pestaña; al cerrarlo
  (`_settings_from_pause`) se vuelve a la pausa, así se guarda con el reloj de antes. Salir al menú pregunta en la misma pausa.
- Tutorial (hito 63, autoload `Tutorial`; pasos en `data/tutorial.json`, la cabecera explica las claves): cada paso tiene `text`, `highlight`
  (lista; se resalta lo primero que se vea: `office` o botones `build`, `build_exit`, `tool:<herramienta>`, `staff`, `staff_publish`, que da
  `main.tutorial_target_rect`) y `condition`: `action` (`EventBus.ui_action`: `camera_moved` desde `OfficeCamera`, una vez por arrastre o paso de
  zoom, y `build_opened`; se anotan en `Tutorial.actions` aunque sean de antes), `workstations`, `vacancies` o los tipos de los objetivos
  (`Company.get_objective_progress`). `check` (con `staff/office/projects_changed`) salta todos los pasos ya cumplidos; al terminar avisa. Una
  partida nueva lo muestra si la opción `tutorial_seen` es false; terminarlo o saltarlo («Saltar», `Tutorial.skip`) la pone en true. Ajustes →
  Opciones: «Retomar el tutorial» (desde el paso donde quedó) o «Volver a empezar» (`resume`). Se guarda (`tutorial`: active, step por id,
  finished, actions); sin estado carga como terminado y la empresa de prueba empieza sin él. `SaveManager` lo envuelve en
  `begin_load`/`finish_load`. `TutorialPanel` (capa 5): tarjeta arriba entre los paneles izquierdos y el reloj, marco y flecha que no atrapan clics.
- Tutorial del negocio y ayuda (hito 64): 10 pasos; tras contratar siguen aceptar un contrato (`projects_accept` = Aceptar de la primera oferta),
  la nómina con la velocidad (`speed_changed`: botón o tecla 1–3; resalta 2x), abrir el Banco (`bank_opened`) y entregar (`projects_deliver` =
  Entregar del primer contrato); termina con la primera entrega. Ayuda: `HelpButton.create(tema)` es el «?» (44 px, tooltip «Ayuda») en la
  cabecera de Personal, Proyectos, Horarios, Banco y Empresa y en la fila de secciones de Construir (`get_help_button()`); emite
  `EventBus.help_requested` y `HelpDialog` (capa 12, en `main.gd`, `get_help_dialog`) muestra el título y el texto de `data/help.json`
  (`topics`) sin pausar; «Entendido» o Esc (lo primero que cierra `handle_escape`) la cierran.
- Interfaz escalable (hito 65): opción `ui_scale` (`ui_scales` 100/125/150 en `data/settings.json`) que pone `content_scale_factor` de la
  ventana (a 150 % en 1280×720 quedan 853×480). `Settings` sube a `min_button_height` (44) el alto mínimo de todo botón que entra al árbol
  (`node_added`, salvo Panku). `UiLayout`: `bottom_space` (lo mide `BuildPanel` desde la barra de menús, ahora `HFlowContainer` que se
  parte en filas) y `top_space` (lo mide `Hud` desde el dinero y el reloj); `EventBus.ui_layout_changed` hace que los paneles izquierdos
  (`fit_left_panel`: ancho hasta la pantalla y alto sobre la barra), la ficha, la tarjeta de eventos (cuerpo desplazable) y Ajustes (pestañas
  desplazables) se acomoden. Personal desplaza todo bajo la cabecera; Construir parte sus herramientas en filas (`HFlowContainer`) según el
  ancho y las desplaza si no entran entre `top_space` y abajo. La tarjeta del tutorial va entre el dinero y el reloj o, si no entra, bajo el
  reloj (`corners_provider` = `Hud.get_corner_rects`). Los botones sin palabras (−, +, <, >, ?, escala) tienen `tooltip_text`. Las pruebas
  sin ventana simulan 1280×720 con `content_scale_aspect = KEEP` (`test_ui_scale`).
- Exportación de escritorio (hito 66): `export_presets.cfg` con macOS (universal, firma ad hoc, `com.quincenaoffice.game`), Windows y Linux
  (x86_64, `.pck` aparte) a `build/`; todos exportan los recursos más `data/*.json` (el juego los lee con `FileAccess`) y excluyen lo de
  desarrollo. macOS universal pide `import_etc2_astc`. Nombre «Quincena Office», `config/version` 0.7.0 (los presets la repiten) e icono
  propio (`icon.svg`). Un autoload nuevo cuyo archivo no viaja se suma a `DEV_AUTOLOADS` del plugin. `test_export` revisa presets, plugin,
  icono y que ningún archivo que viaja nombre lo excluido; `export_desktop.sh` hace la exportación real. Con `--main-pack` lo que falta en el
  paquete se busca en la carpeta actual: la revisión corre desde una vacía.
- Comprobación de la fase 7 (`test_phase7`, hito 67): en una pantalla de 1280×720 (`content_scale_aspect = KEEP`), desde el menú principal
  (Nueva partida) hasta la primera entrega siguiendo el tutorial solo con eventos del ratón (clics en lo que resalta, arrastre de la cámara,
  clic en casillas del local con `grid.get_canvas_transform() * cell_to_world`, y si la interfaz las tapa (`gui_get_hovered_control`) arrastra
  la cámara con el clic derecho; clic derecho para girar muebles, rueda para llegar a botones de listas desplazables, «+» si el candidato pide
  más); entre pasos solo deja correr el reloj (`GameClock.advance`, con el reloj detenido para que no salgan eventos). Con ventana el cursor
  real se mezcla con los eventos de la prueba: se corre sin ventana. Comprueba que el marco del tutorial encierra cada botón que pulsa y que no llegó ninguna tecla. Tres semillas; termina
  a tiempo hacia el día 6–9 con unos $22,000. Sin cambios de datos ni de balance.
- Mapa y cámara (hito 68, fuera de la lista del diseño): `CAMERA_ZOOM_LEVELS` 0.25–4 en 11 niveles (referencia 2.0, índice 7); la cámara
  guarda `{"zoom": nivel, x, y}` y una partida vieja con solo `zoom_index` lo lee en `CAMERA_LEGACY_ZOOM_LEVELS`. Estado lógico = `position` y
  `zoom_index`; lo que se ve (`get_shown_zoom`) llega con una animación que deja fijo el punto bajo el ratón; `fit_rect`/`center_on(…, animate)`
  se deslizan («Ver oficina», F y los avisos de habitación); al soltar un arrastre rápido sigue con inercia; WASD/flechas (por posición, no con
  un campo de texto activo) y el ratón en el borde de la ventana (no sobre la interfaz, solo con ventana y foco) la mueven; `pan_blocker` lo
  corta con un menú encima. Opciones `smooth_camera` y `edge_pan` (Ajustes). `OfficeCamera.smoothing_enabled` (no se guarda) es solo para
  pruebas: `test_all` lo apaga antes de `camera_view`; `finish_motion()` termina la animación. Girar la vista: `OfficeGrid.view_rotation`
  (0–3, `_to_view`/`_from_view` alrededor del solar) cambia solo dónde se dibuja cada casilla: todo lo que pasa por `cell_to_world`,
  `grid_to_world` y `world_to_cell` gira solo, e `IsoBox.draw` busca la esquina de arriba. `main.rotate_view` (botón ↻ en la barra, Q/E)
  deja en el centro lo mismo, redibuja y llama `OfficeCharacter.refresh_position`; la escena guarda `view_rotation`. Mapa (`MapDecor`,
  funciones puras, `data/map.json`): pasto variado en el solar, camino de la puerta al borde, afuera (`Surroundings`, otra capa debajo del
  piso, 10 casillas) acera y calle del lado de la salida y pasto oscuro, árboles (`TreeView`) a 2 casillas o más del local, y la línea
  discontinua del límite (`SiteBorder`); se rehace solo si cambia el local, la entrada o el giro. «Ver oficina» es más angosto para que la
  barra entre en una fila a 1280.
- Puerta doble de vidrio (hito 69, diseño 21.6; `glass_door` en `data/construction.json`, $900, `ambiance` 6): la puerta de la Recepción. Solo
  reemplaza la puerta de entrada (`OfficeState.get_entrance_edge()`, `Builder._is_entrance_swap`); la puerta del contorno no se cobra
  (`_paid_kind`) y vender la de vidrio o pasarle otra pieza deja la puerta normal. `ConstructionCatalog.is_door` (pasa, abre espacios, la
  entrada) reemplaza las comparaciones con `DOOR`. Suma sus puntos al ambiente de la habitación con la casilla de entrada
  (`OfficeState.get_room_door_ambiance`, cuarto parámetro `extra_points` de `Ambiance`). `EdgePieceView` la dibuja con dos postes, dintel y
  dos hojas. Herramienta `TOOL_GLASS_DOOR` («Puerta de vidrio»); la empresa de prueba la trae puesta. No cuenta como bien.
- `GameConstants` (`scripts/autoload/game_constants.gd`) es una clase con `class_name`, no un autoload.

## Forma de trabajo

- Un hito por sesión; no adelantar trabajo de hitos posteriores.
- Antes de dar un hito por terminado, comprobar su criterio de aceptación.
- Cada hito agrega su parte en `tests/suites/` y la suma a `test_all`.
- La lista de hitos está en la sección 15.4 de `docs/diseno.md` (fase 1, hitos 0–9), en la 16.3 (fase 2, hitos 10–19), en la 17.3 (fase 3, hitos 20–29), en la 18.3 (fase 4, hitos 30–39), en la 19.3 (fase 5, hitos 40–49) en la 20.3 (fase 6, hitos 50–59) y en la 21.3 (fase 7 de pulido, hitos 60–67; solo escritorio, sin Android ni iOS; el arte y el sonido pasan a la fase 8); los agregados antes de la fase 8 (hitos 68–69) en la 21.6.

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
| 42 | Lanzamiento y ciclo de vida | ✅ Completado (lanzar con racks libres; usuarios 30 días crecen, 60 en el pico y 120 caen hasta 10 %; calidad = nivel de quien diseñó + errores, ingreso 50–150 %; errores en producción −0.5 %/día por error; actualización del 20 % de los puntos vuelve al pico; retirar libera racks; valor +60 días de ingreso; Mediana empresa pide 1 lanzado) |
| 43 | Eventos | ✅ Completado (sorteo cada hora: uno cada 5/4/3/2/1.5 días según la etapa, uno a la vez, por condiciones y peso; tarjeta plegable a la derecha con 2 minutos reales que se detienen en pausa y construcción, al acabarse elige al azar; efectos de dinero, ánimo, energía, estrés, reputación y oferta; 4 eventos de prueba, la lista completa en el hito 44) |
| 44 | Lista de eventos | ✅ Completado (los 16 de 10.2; multa 10 % de los ingresos del mes pasado, mínimo $500, la mitad con archivero y nada con contador; pago atrasado retiene 30 % de una entrega de la última semana, 15 días o 3 con contador; baterías anulan el apagón; oficina sucia solo sin limpieza; reunión inútil con líder bajo 60; inodoro, lavamanos y cafetera nuevos para Baño y Sala de descanso; los buenos pesan más) |
| 45 | Ambiente y decoración | ✅ Completado (planta grande, cuadro, reloj, lámpara, alfombra que se pisa y pecera que baja el estrés; puntos × 10 / área − amontonar según el porcentaje de escritorios de más que 1 cada 4 m² (−15 con 50 % más), tope ±15 a la meta de ánimo; objetos de pared en una cara de pared con casilla y lado; el aire acondicionado pasa a la pared y las partidas viejas lo cuelgan solas) |
| 46 | Calidades de muebles | ✅ Completado (computadora media $1,200 +15 % y pro $2,500 +30 %; segundo monitor $300 +5 % sobre un escritorio con computadora; silla ergonómica $250 −4/h de energía en vez de −6; escritorio amplio $350 +5 a la meta de ánimo; herramienta Mejorar sube computadora o silla en su lugar cobrando la diferencia, también en puestos ocupados) |
| 47 | Contratos grandes y Sala de reuniones | ✅ Completado (grandes desde Mediana empresa con 4 ★; de élite desde Corporación con 5 ★, pago ×1.5 y clientes propios; los dos exigen Sala de reuniones con mesa 2×2 $1,200; la sala se habilita para siempre con la primera oferta grande; pantalla de presentaciones $800 en la pared: +25 % de peso a grandes y de élite; pizarra pendiente) |
| 48 | Corporación y salir a bolsa | ✅ Completado (Corporación con 4 ejecutivos y 3 productos activos; bolsa siendo Corporación con valor > $5,000,000, solo cierre sin dinero; botón en Empresa con confirmación y aviso al cumplirse; pantalla de cierre con estadísticas, «Seguir jugando» en modo libre o «Volver al menú»; terreno sin tope hasta llenar el solar) |
| 49 | Comprobación de la fase | ✅ Completado (sigue la empresa de la fase 4 desde Mediana empresa; bolsa ~20 meses después sin quebrar; productos 40–70 % de los ingresos del último año (~60 %); medianos y grandes pagan ×3 y valen 540 días de ingreso; eventos y etapas sin cambios; la prueba tarda ~40 s) |
| 50 | Rasgos de producción | ✅ Completado (noctámbulo +20 % de noche y −10 % de día sin perder ánimo de noche; perfeccionista −15 % de puntos, −40 % de errores y QA encuentra 25 % más; sociable −5 % y +5 a la meta de ánimo de su equipo; mentor +15 % a Pasantes y Juniors de su equipo en su turno y un contrato menos para ascender; un rasgo más se descubre cada 15 días; la ficha explica los conocidos) |
| 51 | Rasgos de conducta e historial | ✅ Completado (impuntual 20 % tarde una hora y 2 % falta la jornada, sorteado al empezar el turno; adicto al café −15 % sin Sala de descanso o con el café agotado por el evento, +2 de energía por hora con café; ambicioso −15 de ánimo tras 15 días sin ascenso pudiendo; leal renuncia con el doble de días malos; historial en la ficha: contratos, errores causados, tardanzas, ausencias y puntualidad) |
| 52 | Baños con capacidad | ✅ Completado (1 inodoro cada 10 presentes con el CEO; siempre aplica, también sin baño: salen del edificio a buscar uno y vuelven; por inodoro que falta −5 % de producción hasta −20 % y −10 a la meta de ánimo ese día y el siguiente; «Baño dañado» con cartel quita un inodoro hasta repararlo desde Empresa por $400; las pruebas anteriores corren sin baños) |
| 53 | Almuerzo en la oficina | ✅ Completado (Sala de descanso con nevera $400, microondas $150 y mesas de comedor $300 de 4 asientos; almuerzan dentro el CEO y los más antiguos hasta llenar los asientos; dentro recuperan el doble de energía y rinden media hora; los demás salen; caminan a la mesa y vuelven a su silla) |
| 54 | Sala de descanso y pausas | ✅ Completado (sofá $500 con 2 lugares: quien produce con energía bajo 40 descansa una hora sin producir y recupera +15, +3 con café, también en el almuerzo; dispensador de agua $120 +2, ping pong $700 +8 y −3 % de puntos, máquina expendedora $900 +3 y $2 por persona al día; uno de cada uno y solo en la Sala de descanso que funciona) |
| 55 | Impresora, pizarra y ventanas | ✅ Completado (impresora $350 en el Área de trabajo del contador: sus efectos ×1.25 y cobra el pago atrasado en 2 días; pizarra de pared $250 en la Sala de reuniones: reunión inútil 1 h en vez de 2 y grandes y de élite con 10 % más de plazo; ventana $200 solo en paredes exteriores, +4 puntos de ambiente a la habitación, nada colgado; el terreno devuelve la mitad de las ventanas del borde que abre) |
| 56 | Candidatos según la empresa | ✅ Completado (primera tanda de 3 ± 1 por estrella sobre 3, al menos 1, +1 con publicidad, después como antes; sueldo ofrecido y ambiente medio de las Áreas de trabajo corren las habilidades dentro del rango del nivel, hasta ±80 %; el premio suma 1 candidato por día a cada vacante durante 7 días; pronóstico en el formulario de Personal; las pruebas anteriores corren sin la regla nueva) |
| 57 | Iconos de estado y avisos | ✅ Completado (un icono por empleado: sin puesto, cansado bajo 30, molesto bajo 30 o con aviso de renuncia, estresado desde 70 y sin tarea, en ese orden; se recalcula al cambiar la hora o el personal, no por cuadro; avisos con destino en celeste con «›»: un clic abre la ficha, Proyectos en Contratos o Productos, Banco, Empresa, Personal o centra la cámara en la habitación) |
| 58 | Inversionista | ✅ Completado (evento desde Pequeña empresa con valor positivo e ingresos del mes pasado desde $5,000; ofrece 10–25 % del valor por una parte de los ingresos de contratos y productos durante 12–24 meses, calculada para devolverle 1.6 veces, entre 5 y 40 %; aceptar da el efectivo como «Inversión», aparte de los ingresos; cada día 1 «Pago al inversionista» aunque deje saldo negativo; el valor descuenta lo que falta estimado con el mes pasado; uno a la vez; rechazar no cambia nada) |
| 59 | Comprobación de la fase | ✅ Completado (la empresa de la fase 5 con rasgos, baños, almuerzo, pausas, candidatos e inversionista llega a la bolsa sin quebrar en ~16 meses desde Mediana empresa; baños y Sala de descanso (~$17,000) suman ~40 % de puntos y se pagan en días; los rasgos suman ~6 %; sin cambios de datos; consultas de muebles y presencia guardadas por hora para que la prueba dure menos de un minuto) |
| 60 | Opciones y Ajustes | ✅ Completado (autoload `Settings` con `user://settings.cfg`: pantalla completa, autoguardado, velocidad inicial, pausa al construir y al perder el foco; un valor roto vuelve al de `data/settings.json`; Ajustes con pestañas Guardar, Cargar y Opciones; cargar y salir piden confirmación; la escala de la interfaz queda para el hito 65) |
| 61 | Menú principal | ✅ Completado (Continuar carga la partida guardada más reciente y no aparece sin partidas; Nueva partida pregunta si hay autoguardado, que se reemplaza, y deja las ranuras manuales; Ajustes con las mismas opciones que en la partida; Salir cierra el juego) |
| 62 | Menú de pausa | ✅ Completado (Esc cierra la pregunta, Ajustes, la pausa, construcción, la ficha o los paneles izquierdos, en ese orden; sin nada abierto abre la pausa con Seguir, Guardar, Cargar, Ajustes y Salir al menú y detiene el reloj; Seguir lo deja como estaba; Guardar, Cargar y Ajustes abren Ajustes en su pestaña y vuelven a la pausa; salir pregunta; las pantallas de fin, bolsa y préstamo de emergencia no se cierran con Esc) |
| 63 | Tutorial: primeros pasos | ✅ Completado (6 pasos: cámara, Construir, Área de trabajo, puesto, vacante de programador y primera contratación; marco y flecha sobre el botón o el local sin bloquear la interfaz; los pasos ya cumplidos se saltan solos; se ve en partidas nuevas hasta terminarlo o saltarlo una vez; «Retomar el tutorial» en Ajustes; se guarda en la partida y las viejas cargan sin él) |
| 64 | Tutorial: el negocio y ayuda | ✅ Completado (4 pasos más: aceptar un contrato, la nómina y la velocidad, el Banco y la primera entrega, que termina el tutorial; botón «?» en Personal, Proyectos, Horarios, Banco, Empresa y Construir con su texto de `data/help.json`, sin pausar y se cierra con Entendido o Esc; las partidas viejas cargan sin tutorial; las descripciones emergentes de los botones sin texto quedan para el hito 65) |
| 65 | Interfaz escalable | ✅ Completado (Tamaño de la interfaz 100/125/150 % en Opciones; a 150 % en 1280×720 la barra se parte en dos filas y los paneles, la ficha, Construir, Ajustes, eventos, tutorial, ayuda, pausa y pantallas de cierre entran en pantalla sin tapar la barra, con desplazamiento donde no entran; todo botón mide al menos 44 px; −, +, <, > y la escala con descripción emergente) |
| 66 | Exportación de escritorio | ✅ Completado (presets de macOS, Windows y Linux en `build/` sin Panku, DevTools ni pruebas, también en debug; icono propio, nombre y versión 0.7.0; la exportación de prueba arranca la app de macOS y cada paquete llega al menú principal; sin firma de Windows ni notarización de macOS) |
| 67 | Comprobación de la fase | ✅ Completado (del menú a la primera entrega solo con el ratón siguiendo el tutorial, en tres semillas, hacia el día 6–9; el marco del tutorial encierra cada botón que se pulsa; test_all falla si una parte pasa de 60 s: la más larga es la fase 6, ~54 s; sin cambios de datos) |
| 68 | Mapa y cámara | ✅ Completado (pedido aparte de la lista del diseño: zoom de 0.25 a 4 en 11 niveles con animación que deja fijo el punto bajo el ratón; inercia al soltar un arrastre; WASD, flechas y el borde de la ventana mueven la cámara; girar la vista de a 90° con ↻, Q y E, guardado en la partida; pasto variado, camino a la calle, acera, calle, árboles y el límite del solar marcado; opciones Cámara suave y borde de la pantalla) |
| 69 | Puerta doble de vidrio | ✅ Completado (puerta de la Recepción: solo en lugar de la puerta de entrada, $900, al venderla devuelve $450 y queda la normal; pasa y cuenta como puerta; +6 puntos de ambiente a la habitación de la entrada; marco oscuro y dos hojas de vidrio; herramienta en Construir; la empresa de prueba la trae) |
