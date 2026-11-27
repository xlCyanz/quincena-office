# Sistemas del juego (referencia de código)

Detalle de cada sistema con sus nombres de código. Las reglas de diseño están en `docs/diseno.md`;
lo general (motor, convenciones, reglas de arquitectura) en `CLAUDE.md`.

## Oficina, construcción y mapa

- Las paredes van en los bordes de las casillas, no ocupan casilla. Un borde es `Vector3i(x, y, eje)` (ver `GridEdge`);
  los caminos usan `AStarGrid2D` a doble resolución para que las paredes de borde bloqueen el paso.
- Una habitación es `{type, cells}` y ocupa siempre un espacio entero (zona cerrada por paredes y puertas, con puerta);
  `RoomRules` detecta los espacios y reubica las habitaciones al cambiar paredes.
- Las paredes y puertas del contorno del local no se compran ni se venden; los pisos no se quitan, solo se cambian por otro.
- El local es un conjunto de casillas (`Lot`, `OfficeState.lot`; `lot_rect` es solo el rectángulo que lo encierra). Crece comprando
  terreno: el solar, menos el local inicial (`OfficeState.get_base_rect`), se parte en lotes rectangulares de tamaños variados
  (`LandPlots.partition_blocks`: cuatro franjas alrededor del local inicial cortadas al azar en bloques hasta que cada lado mide de 4 a 6 m,
  `land.plot_sides_blocks` en `data/construction.json`; sin bloques, `partition` con `plot_sides` de 3 a 6; con la semilla de la partida, `OfficeState.land_seed`, guardada; `OfficeState.get_land_plots`/`get_land_plot_at`).
  La herramienta Terreno marca los lotes que tocan el local con su precio (`Builder.get_plot_cells`, `get_land_plots` con `action` "buy";
  `BuildController.get_land_plots`, `refresh_land_plots`) y un clic en uno lo compra (`buy_land_plot_at`, `Builder.buy_land_cells`); es la
  única forma de comprar en el juego: para llegar a uno de más afuera hay que comprar antes el que lo separa. Así el local toma formas libres
  hechas de rectángulos. Los rellenos y bordes de los lotes van en `LandOverlay` (capa de `OfficeGrid` sobre el piso, bajo paredes y
  muebles: `get_land_overlay`); los precios los dibuja `BuildController` encima. Los lotes propios enteros se marcan con su borde punteado (`action` "sell") y un clic pregunta si se venden
  («Sí» / «No», `ask_confirm`): `Builder.quote_sell_land_plot`/`sell_land_plot` devuelven `sale_refund_ratio` del terreno y su piso
  (`ConstructionCatalog.get_land_refund`), bajan `land_paid`, quitan sus pisos y cierran el contorno nuevo con pared. Solo se vende un lote
  vacío (sin muebles, habitación, paredes de adentro, puertas ni ventanas en su borde, ni la entrada) que no parte el local
  (`Lot.without_cells`, `is_joined`). Las partidas con lotes de antes (4×4) los completan comprando lo que falta; el local inicial no se vende. Para pruebas y simulaciones sigue el rectángulo libre (`BuildController.set_land_rect`/`get_land_rect`, `land_changed`;
  Comprar en `BuildPanel`) y `Builder.quote_land_rect`/`buy_land_rect` (o `quote_land_cells`; `quote_land`/`buy_land` por lado siguen para
  pruebas) toman sus casillas dentro del solar y fuera del local, conectadas al local; si entre ellas va la casilla de frente a la puerta, la entrada
  se corre derecho al borde nuevo con su puerta (`result["entrance"]`, `OfficeState.entrance`; ese pedazo se abre hacia el espacio de la entrada,
  así la Recepción la conserva; los personajes toman la entrada nueva en `_refresh_entrance`) ($150/m² más la cerámica a
  mitad de precio, en `data/construction.json`). El contorno nuevo lleva pared; cada pedazo nuevo abre los bordes que comparte con un solo
  espacio viejo (`_edges_with_land`: el que no es habitación antes, si no el de más bordes), así no junta habitaciones; una pared con algo
  colgado queda cerrada. Solo se rechaza si se perdería una habitación. El mantenimiento se cobra por `lot.get_area()`.
- Bloques de construcción (hito 71, `BuildGrid`, funciones puras; `GameConstants.BUILD_BLOCK` 2): paredes, puertas, ventanas, pisos y
  terreno van en bloques de 2×2 m que empiezan en coordenadas pares; muebles y personajes siguen en casillas de 1 m. El modelo no cambia
  (bordes de 1 m y casillas, guardado, habitaciones, caminos): un tramo de bloque son 2 bordes en línea (`block_segment`) y una línea de
  bloque es la de un borde con x impar (eje x) o y impar (eje y) (`is_block_edge`). Construir usa `BuildController._build_edge`
  (`nearest_block_edge`) para pared, puerta y ventana; la pared avanza de a tramo (`_edge_line`) y el piso se agranda a bloques enteros
  (`snap_rect_to_blocks`); Vender sigue en 1 m (`GridEdge.nearest`). `Builder.quote` rechaza con `OFF_BLOCK_MESSAGE` poner una pieza fuera
  de línea de bloque (salvo el contorno) o un piso que no cubre bloques enteros del local (`_breaks_blocks`); quitar siempre se puede, así
  las partidas viejas cargan como están y venden sus paredes de 1 m. El solar queda alineado (`site_around`), los lotes se cortan en
  bloques (`LandPlots.partition_blocks`, `land.plot_sides_blocks` [2, 3] = 4–6 m) y la puerta doble usa el otro borde de su tramo
  (`place_double_door`). La oficina inicial (CEO de 4×4) y la empresa de prueba están alineadas; las partes anteriores usan
  `tests/fixtures/starting_office_legacy.json` y `starting_company_legacy.json` con `OfficeState.build_blocks_enabled` en false (no se
  guarda; `FIRST_BUILD_BLOCKS_SUITE`). Prueba `test_build_blocks`.
- Mudar la Oficina Ejecutiva (fase 8): marcarla en otro espacio cerrado con puerta, cuando ya hay una, es mudarla
  (`Builder.quote_mark_room` → `quote_move_ceo_office`): hace falta ahí una silla sin dueño con el frente de un escritorio delante; el resultado
  trae `confirm` y el modo construcción pregunta («Sí, mudar» / «No»: `BuildController.ask_confirm`/`answer_confirm`/`is_confirming`,
  `confirm_changed`; `BuildPanel.show_confirm`, `get_confirm_button`). Al aceptar (`move_ceo_office`) la silla nueva pasa a ser del CEO, la de antes
  queda libre y la oficina de antes sin marcar; `mark_room` sola no la muda. `main._on_office_changed` manda al CEO a su silla nueva.
- Suelo con detalle (`GroundPainter`, funciones puras): pisos y terreno se pintan con `DETAIL` (4) veces más píxeles por casilla (256×128) y
  las capas `Floor` y `Surroundings` se dibujan a 1/4 con `TEXTURE_FILTER_LINEAR_WITH_MIPMAPS`; la casilla sigue midiendo 64×32 en el mundo
  (`cell_to_world` pasa por la capa). Cada estilo tiene un material (`MATERIALS`): cerámica en 2×2 losas con junta y bisel, madera en 4 tablones
  con veta, alfombra en cuadros, concreto, pasto con manchas y briznas, grava, acera y asfalto; los dibujos se repiten cada casilla sin costuras
  (`noise` periódico). El TileSet se pinta una vez por ejecución (~1 s, `OfficeGrid._shared_tile_set`). Es solo el dibujo. Prueba `test_ground`.
- Cuartos de casilla (como Timberborn, que coloca en bloques enteros y comparte casillas): los muebles con `small` en `data/furniture.json`
  (planta pequeña, zafacón, dispensador de agua y lámpara de pie) ocupan un cuarto de su casilla (`quarter` 0–3 en el mueble, guardado;
  `FurnitureCatalog.get_quarter`, `get_quarter_offset`, `quarter_at`, `overlaps`). Caben hasta 4 chicos por casilla y nunca con uno grande;
  la casilla sigue siendo de 1 m² para paredes, habitaciones, caminos y precios y sigue tapando el paso. `Builder.quote_place(…, quarter)`
  (sin cuarto, el primero libre), `rotate`/`sell_furniture_at(cell, quarter)` y `OfficeState.find_furniture_at(cell, quarter)` eligen el del
  cuarto bajo el ratón; las partidas viejas los ponen en el cuarto 0. Prueba `test_quarters`.
- Mover (`BuildController.TOOL_MOVE`): un clic toma el mueble bajo el ratón (lo colgado junto al ratón primero; `pick_up`,
  `is_moving`, `get_move_index`, `move_changed`) y otro lo suelta donde se elija, con su contorno; clic derecho o R lo gira; soltarlo
  donde estaba, Esc (`main.handle_escape` → "move"), otra herramienta o salir de Construir lo dejan donde estaba (`cancel_move`).
  `Builder.quote_pick_up`/`quote_move`/`move(index, anchor, rotation, quarter)`: gratis, con su computadora, pantallas y dueño; las mismas
  reglas que poner (o colgar, para lo de pared); no lo del puesto de un empleado y la silla del CEO solo dentro de su oficina. Con lo
  colgado tomado las paredes suben. Prueba `test_furniture`.
- Tienda e inventario: los muebles se compran en la Tienda (`ShopScreen`, a pantalla completa; `Builder.quote_buy`/`buy(id, count)`,
  `BuildController.buy`) y quedan en `OfficeState.inventory` (id → cantidad, guardado; `get_stock`, `add_stock`, señal
  `EventBus.inventory_changed`). `quote_place`, `quote_install_computer` y `quote_install_monitor` sacan del inventario sin costo si hay
  (`"stock"` en la cotización, lo descuenta `_commit`); sin inventario cobran el precio como antes. Guardar (`BuildController.TOOL_STORE`;
  `quote_store_furniture_at`/`store_furniture_at`, `quote_store_wall_item`/`store_wall_item`) devuelve al inventario lo que Vender
  vendería, en el mismo orden y con los mismos límites, sin dinero (`"stored"`). Lo del inventario cuenta en `Bank.get_assets_value` por su
  reventa. `TOOL_NONE` es «sin herramienta» (inventario vacío o se acabó lo elegido). Prueba `test_inventory`.
- Contorno de selección: en Construir, el mueble ya puesto que elige la herramienta (vender, girar, mejorar, ponerle computadora o
  pantalla, o el objeto de pared que se vende) y el que se va a poner se marcan con una línea punteada que sigue su silueta, verde si se
  puede y rojo si no (`BuildController._preview_item`, `_preview_new`, `get_selection_outline`, `SELECTION_*`; el que se va a poner se
  arma con piezas de prueba fuera del árbol, `OfficeGrid._make_views`). `SelectionOutline` pinta las piezas del mueble en una
  máscara a la resolución de los sprites (`FurnitureView.get_outline_piece`: el sprite o, sin él, la caja provisional), llena los huecos
  de adentro y toma el borde exterior, separado 1 px y punteado; `OfficeGrid.get_furniture_outline` lo guarda por mueble hasta que
  cambian los muebles. Sin ventana no hay imagen de los sprites y usa su rectángulo visible (`SpriteLibrary.get_image`,
  `get_visible_rect`). Prueba `test_furniture`.
- El mapa es el solar fijo de `GameConstants.MAX_SITE_SIZE` (40×40) con el local en el centro (`OfficeState.site_rect`);
  fuera del local se dibuja terreno (`MapDecor`, hito 68). Paredes arriba / abajo (solo la vista, no se guarda):
  botón Paredes de la fila de secciones de Construir (`BuildPanel.walls_toggled`, `get_walls_button`, con el icono `ui_walls`) o tecla P (`main.set_walls_up`, `are_walls_up`; `OfficeGrid.walls_up`, `is_tall_edge`) suben todas las piezas de borde a su
  alto y lo colgado se ve a tamaño real; al elegir un objeto de pared en Construir suben solas (`main._apply_walls`). Con las paredes abajo, un
  tramo del contorno va alto solo si es de atrás y no tapa local: se miran solo las casillas de su columna de pantalla (x − y de sus
  extremos) que caben en su alto (`OfficeGrid.is_back_edge`): con el local en L, solo baja el tramo que tiene el saliente justo detrás. La cámara se mueve libre por el solar: su centro no sale del rombo del mapa.
  Al empezar encuadra la oficina (`OfficeCamera.fit_rect`); «Ver oficina» o la tecla F la vuelven a encuadrar.
- Mapa y cámara (hito 68, fuera de la lista del diseño): `CAMERA_ZOOM_LEVELS` 0.25–4 en 11 niveles (referencia 2.0, índice 7); la cámara
  guarda `{"zoom": nivel, x, y}` y una partida vieja con solo `zoom_index` lo lee en `CAMERA_LEGACY_ZOOM_LEVELS`. Estado lógico = `position` y
  `zoom_index`; lo que se ve (`get_shown_zoom`) llega con una animación que deja fijo el punto bajo el ratón; `fit_rect`/`center_on(…, animate)`
  se deslizan («Ver oficina», F y los avisos de habitación); al soltar un arrastre rápido sigue con inercia; WASD/flechas (por posición, no con
  un campo de texto activo) y el ratón en el borde de la ventana (no sobre la interfaz, solo con ventana y foco) la mueven; `pan_blocker` lo
  corta con un menú encima. La rueda y el pellizco sobre un control (`is_pointer_over_ui`) no hacen zoom aunque la ventana no los use. Opciones `smooth_camera` y `edge_pan` (Ajustes). `OfficeCamera.smoothing_enabled` (no se guarda) es solo para
  pruebas: `test_all` lo apaga antes de `camera_view`; `finish_motion()` termina la animación. La vista ya no se gira (se quitó
  después del hito 69): siempre desde la misma esquina; una partida guardada con `view_rotation` distinto de 0 encuadra la oficina al cargar.
  Paredes: las de atrás (`OfficeGrid.is_back_edge`: contorno con la casilla de fuera detrás) se dibujan a su `height` de `data/construction.json`
  (pared 60, puerta 46, ventana 60, puerta de vidrio 57) y todas las demás a `low_wall_height` (10), para ver adentro (`EdgePieceView.tall`);
  un objeto de pared en una pared baja se dibuja pegado abajo y no más alto que ella. Mapa (`MapDecor`,
  funciones puras, `data/map.json`): pasto variado en el solar, camino de la puerta al borde, afuera (`Surroundings`, otra capa debajo del
  piso, 10 casillas) acera y calle del lado de la salida y pasto oscuro, árboles (`TreeView`) a 2 casillas o más del local, y la línea
  discontinua del límite (`SiteBorder`); se rehace solo si cambia el local, la entrada o el giro. «Ver oficina» es más angosto para que la
  barra entre en una fila a 1280.
- Un puesto de trabajo (`Workstations`) es una silla delante del frente de un escritorio con computadora, ambos dentro
  de un Área de trabajo que funciona; cada escritorio sirve a una sola silla. Sus muebles no se venden ni giran mientras está ocupado.
- Silla de visita: la Oficina Ejecutiva y la Oficina única piden dos sillas (`count` en un requisito de `data/rooms.json`,
  `RoomRules.function_problems`): la de quien trabaja ahí y una de visita (`Staff.get_guest_chair`, silla sin dueño de su habitación), donde se
  sienta el candidato; sin ella la oficina no funciona (sin puesto) y no se entrevista. La oficina inicial y la empresa de prueba la traen.
  `RoomRules.counts_enabled` (no se guarda) es solo para pruebas: `test_all` lo apaga antes de `office_chairs`. `progress` guarda puntos con decimales.
- Sala de servidores (`OfficeState.SERVER_ROOM`, desde Pequeña empresa): funciona con `server_rack` ($3,000) y `air_conditioner` ($800, objeto
  de pared desde el hito 45). `OfficeState.get_server_room()` / `get_server_capacity()` (racks de la sala
  que funciona; 1 rack = 1 unidad, los productos usan 1/3/8). Todo mueble con `monthly_cost` (cada rack $100, esté donde esté) se cobra el
  día 1 como «Mantenimiento de servidores» (`Economy.get_monthly_server_cost`, con el descuento del contador, y en su aviso). Builder
  `room_status` dice los racks; Empresa tiene la sección Servidores.
- Ambiente y decoración (`Ambiance`, funciones puras; `ambiance` y adornos en `data/furniture.json`, hito 45): ambiente de una habitación =
  puntos de adornos × 10 / área − amontonar (caben uno cada 4 m²; −15 con 50 % más escritorios, en proporción antes), redondeado entre −15 y +15; suma a la meta de ánimo de quien tiene
  su silla ahí (`Staff.get_workplace_room`, `get_ambiance`); la pecera (`stress_relief`) baja 5 la meta de estrés. Objetos de pared
  (`wall_mounted`: cuadro, reloj y el aire acondicionado): no ocupan casilla; `cell` es la casilla que miran y la pared queda detrás del frente
  (`FurnitureCatalog.get_wall_edge`); uno por cara (`OfficeState.find_wall_item`); una pared con algo colgado no se vende, ni pasa a puerta, ni
  la abre el terreno. La alfombra (`walkable`) ocupa casillas pero no tapa el paso: los caminos usan `OfficeState.get_blocking_cells`. Al cargar,
  un objeto de pared sin pared se cuelga en la cara libre más cercana de su habitación o se quita devolviendo su precio. El modo construcción
  cuelga en la pared más cercana al ratón y muestra el ambiente; la ficha dice «Trabaja en: … · Ambiente +N».
- Calidades de muebles (hito 46; fase 8, `data/furniture.json`): dos niveles de computadora, básica (`basic_computer`, $500, la crema todo en uno)
  y pro (`pro_computer`, $2,500, `production_bonus` 0.3, negra con torre); la media se quitó (una partida vieja la carga como básica). Pantalla
  extra (`second_monitor`, `is_monitor`, $300, +0.05 cada una): solo sobre un escritorio que las admite (`max_monitors`: el largo, 2) y con una
  computadora que las admite (`extra_monitors`: la pro); `furniture["monitor"]` + `"monitors"` (cuántas, `FurnitureCatalog.get_monitor_count`); se
  venden de a una antes que la computadora; las de una partida vieja que ya no caben se quitan devolviendo lo pagado
  (`OfficeState._replace_removed_furniture`). Escritorio largo (`long_desk`, $350, 2×1, acepta computadora). Silla ergonómica ($250,
  `energy_per_work_hour` −4 en vez de −6: `Staff.get_work_energy`). El escritorio amplio ($350, 2×1, +5 de ánimo) se quitó: una partida vieja lo
  carga como sencillo en la casilla con la silla delante; queda el mecanismo `mood_bonus` de un escritorio (`Staff.get_desk_mood`,
  `Workstations.station_desk_of`), que hoy ningún mueble usa. `upgrade_to` es la calidad siguiente (básica → pro); `Builder.quote_upgrade`/`upgrade`
  (herramienta Mejorar) la cambia en su lugar cobrando la diferencia, también en un puesto ocupado o la silla del CEO. El bono de un puesto es
  computadora + pantallas extra (`Workstations.get_desk_bonus`, `bonus_of`, `bonuses_by_owner` con caché). `data/rooms.json` acepta la silla
  ergonómica donde pedía silla y el escritorio largo donde pedía escritorio.
- Sillas de oficina (`data/furniture.json`, todas `is_seat`, sin `upgrade_to`): de malla (`mesh_chair`, $150, −5/h), gerencial
  (`manager_chair`, $400, −4/h, 1 de ambiente), sillón ejecutivo (`executive_chair`, $700, −3/h, 2 de ambiente), de visita (`visitor_chair`,
  $90, patas fijas) y taburete (`stool`, $70); `data/rooms.json` las acepta donde pide silla. Sprites en `tools/sprites/art/furniture/chair_*`
  (`_chairs.py`); cada una necesita su base en `_figure.CHAIRS` y en `export_game.py` (`FURNITURE`, `PARTS`, `SEATED_CHAIRS`) para
  que el personaje sentado se componga con ella (`sit_<id>`, `type_<id>`).
- Laptop y mesa de vidrio (hito 70, diseño 21.6; `data/furniture.json`): laptop (`laptop`, $1,800, `production_bonus` 0.2) con `desks`
  = los escritorios donde cabe (`["executive_desk"]`; vacío = cualquiera): `FurnitureCatalog.get_desks`/`fits_desk`, que revisa
  `Builder.quote_install_computer`. Sin `upgrade_to` ni `extra_monitors`; Mejorar dice que no se puede mejorar (no «es la mejor»).
  Mesa de reuniones de vidrio (`glass_meeting_table`, 2×2, $2,000, `ambiance` 6): `data/rooms.json` la acepta como mesa de la Sala de
  reuniones. Sprites `computer_laptop` y `glass_meeting_table` (con rotaciones) de `tools/sprites/art/furniture/`.
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
- Puerta de vidrio de una hoja (hito 69, rehecha en el 72; `glass_door` en `data/construction.json`, $900, `height` 57, `ambiance` 6):
  una hoja de la doble, de vidrio sin marco de punta a punta del borde (`tools/sprites/art/walls/glass_door/`), que abre con sus
  cuadros (`OPENING_DOORS` en `export_game.py`). Se compra en cualquier borde de adentro como una puerta (en línea de bloque; no en el
  contorno) con la herramienta Puerta de vidrio de Estructura (`BuildController.TOOL_GLASS_DOOR`); se vende a la mitad. También queda
  en la entrada cuando no cabe la doble. `ConstructionCatalog.is_door` (pasa, abre espacios, la entrada) reemplaza las comparaciones
  con `DOOR`. `OfficeState.get_room_door_ambiance`: la de la entrada suma a la habitación con la casilla de entrada y cada una de
  adentro a las habitaciones de sus dos lados (cuarto parámetro `extra_points` de `Ambiance`). No cuenta como bien. Prueba
  `test_glass_door_single`.
- Puerta de vidrio doble (`glass_door_double` en `data/construction.json`, `price` 0, `height` 57, `ambiance` 10): la entrada la lleva
  siempre. Sin marco, de dos bordes: la puerta de entrada y un tramo del contorno de al lado, en línea (`GridEdge.get_line_neighbors`);
  los dos guardan la misma pieza y `OfficeState.get_double_door_partner` da el otro. `OfficeState.place_double_door(edges, lot, door)`
  la pone (partida nueva, `import_state` para partidas viejas, empresa de prueba y terreno): primero el tramo que ya la tenía, si no
  una pared sin nada colgado (la de arriba primero), si no pared o ventana; sin tramo posible queda la sencilla. Es fija: `Builder`
  rechaza cualquier cambio en sus dos bordes (`_is_entrance_door`, `ENTRANCE_FIXED_MESSAGE`) y no se compra ni tiene
  herramienta. Con terreno frente a la entrada se corre entera (el tramo con el mismo desplazamiento). El camino de grava sale de sus
  dos tramos (`MapDecor.get_path_starts`, `plan(…, edges)`), así queda centrado y sigue a la puerta. `ConstructionCatalog.is_glass_door`
  cubre las dos para el ambiente. `EdgePieceView` dibuja en cada borde su mitad (`glass_door_double_<a|b>_<tall|low>_<x|y>`,
  `get_double_half`: a = el de menor x o y) y abre sus dos mitades juntas con sus cuadros (`glass_door_double_<a|b>_tall_<eje>_open_<n>`,
  `OfficeGrid.update_doors`: alguien junto a una abre las dos); como pared del frente, solo con las paredes arriba. Pruebas anteriores a `glass_door_double` corren con `OfficeState.double_door_enabled`
  en false.

## Tiempo, jornada y personajes

- Tiempo: 1 hora de juego = `GameConstants.SECONDS_PER_GAME_HOUR` (60 s reales a 1x; hasta el hito 69 eran 10 s). Velocidades
  `CLOCK_SPEEDS` 1x, 2x, 4x, 8x y 16x (botones del reloj, `Hud.SPEED_BUTTON_WIDTH`, y teclas 1 a 5). Las pruebas que
  esperan con topes en segundos (`test_ceo`, `test_workday`) los escalan por `SECONDS_PER_GAME_HOUR / 10`.
- Jornada: `Staff.is_expected(key, día, hora)` dice quién debe estar en la oficina; `main.gd` se lo pasa cada hora a los
  personajes (`OfficeCharacter`, base de `Ceo` y `Employee`). Cada empleado tiene el turno de su equipo o, sin equipo, el horario
  de su cargo (`data/staff.json`); `WorkSchedule` admite turnos que cruzan la medianoche y cada uno almuerza a la 4.ª hora de su jornada. El CEO no tiene horario: llega solo a las 8 en días hábiles (se le ve entrar a las 7:30 a abrir) y se queda hasta que el
  jugador lo manda a casa (`Staff.ceo_at_work`, botón «CEO: irse a casa»). Con la oficina vacía el tiempo salta a la próxima llegada.
  Un clic en un empleado abre su ficha (`EmployeeCard`). El muñeco se dibuja a `OfficeCharacter.BODY_SCALE` (0.8, unos 50 px de pie, a la escala
  de los muebles); sentado la cadera queda a `SEAT_HEIGHT_PX` y el icono de estado no se achica; `CLICK_AREA` ya va escalado.
  Caminan a `CHARACTER_WALK_SPEED` (1 casilla/s a 1x; con prisa, `OfficeCharacter.hurry`, × `CHARACTER_HURRY_FACTOR` 2 hasta llegar: quien entra después de su hora (`main._arrive_staggered`) y el candidato llamado a la entrevista) y hay una persona por casilla del local: cada uno ocupa la suya y, al
  caminar, la siguiente hasta pasar la mitad del tramo, cuando suelta la de atrás (`OfficeCharacter._occupants`, estático; `is_cell_taken`, `get_held_cells`). Si la siguiente está ocupada
  espera; cada `CHARACTER_REPATH_WAIT` busca un camino que esquive a los demás (`OfficePathfinder.find_path(…, avoid)`) y tras
  `CHARACTER_PASS_WAIT` pasa igual (dos de frente en un pasillo de una casilla). Aparece en la entrada si está libre; si no,
  espera en la calle sin verse. Fuera del local no hay límite. `main.gd` no manda a dos al mismo lugar: limpieza, almuerzo,
  pausas y visitas toman la casilla libre más cercana (`_cells_near`, `_free_spot_near`). El proyecto ajusta todo a píxeles enteros del mundo
  (`snap_2d_transforms_to_pixel`): con zoom 4 eso haría saltar de a 4 px a quien camina, así que al caminar el dibujo se corre lo que
  el ajuste le quita, redondeado a píxeles de pantalla (`OfficeCharacter._draw_offset`, `_subpixel_offset`; quieto vale cero). Desde la calle se entra por turno (`_door_queue`, primero el que espera hace más); quien está afuera y debe irse se va sin cruzar la puerta (`update_routine`, `_walk_to` con `WALKING_OUT`). Prueba `test_walking`.
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

## Personal

- `Staff` guarda vacantes y candidatos (`data/staff.json`, `data/names.json`); su azar usa una semilla guardada
  en la partida (`Staff.set_seed` en las pruebas). El menú Personal (`StaffPanel`) no pausa el tiempo. Ocupa el ancho entre el
  dinero y la barra de menús (empieza bajo la tarjeta del tutorial: `avoid_provider`; si no cabe, se desplaza entero) y va en capas:
  `scripts/ui/staff/staff_panel_base.gd` (constantes, estado, piezas: `Bar` es la barra fina, con rango para habilidades sin
  entrevistar) → `staff_panel_employees` → `staff_panel_hiring` → `staff_panel_org` → `scripts/ui/staff_panel.gd` (cabecera, API).
  La cabecera tiene las pestañas (`show_tab`: `TAB_EMPLOYEES`, `TAB_HIRING`, `TAB_ORG`, esta solo si hay organigrama; sin empleados
  abre en Vacantes y el tutorial señala la pestaña con `get_publish_target_rect`; `tab_shown` avisa el cambio), el resumen (nómina,
  puestos libres, ánimo medio), «?» y Volver al mapa.
  - Empleados: avisos (ofertas de otra empresa con Igualar / Dejar ir, `Staff.match_offer` / `let_go`, y cuántos están cansados,
    molestos… o pueden ascender), filtro por área (`AREAS`), búsqueda, orden (`SORT_NAMES`) y tarjetas (`CardButton`) agrupadas por
    equipo con foto (`EmployeePortrait`), nombre, cargo, barras de ánimo, energía y estrés y el globo de estado. A la derecha queda
    la columna de la ficha: main la pone ahí (`get_body_top` → `EmployeeCard.set_top`, cada vez que se mueve: `body_moved`) y la
    cierra fuera de Empleados; la ficha marca su tarjeta (`EmployeeCard.employee_changed` → `set_selected_employee`).
  - Vacantes: formulario (chips de cargo y botones de nivel que reflejan `_role_option` / `_level_option`, ocultas, que son el
    modelo; sueldo −/+ contra la tabla, Pronóstico, publicidad, Publicar) y cada vacante con sus candidatos en tarjetas: foto (el
    aspecto con que llegan, `Visitor`), edad, lo que piden, cuándo se van, habilidades (rango hasta la entrevista), rasgos, cita,
    oferta −/+ con lo que pasaría (`_offer_hint`) y Entrevistar / Delegar / Ofrecer / contraoferta / Descartar.
  - Organigrama: departamentos con quien los dirige y cuánto rinden, la lista de cada ejecutivo y el árbol CEO → gerentes → líderes
    (con «A cargo de») → caras del equipo; las líneas se dibujan detrás (`_org_links`).
  La foto es el cuadro de pie mirando al frente recortado en cabeza y hombros (`SpriteLibrary.get_portrait`, con la paleta de
  `Employee.look_for`) sobre el color de su área.
  `Staff.employees` son los contratados; cada uno ocupa la silla de un puesto con `assigned_to = Staff.employee_key(id)`.
- Cambiar de puesto: la ficha tiene la fila Puesto con «Cambiar de puesto» (`EmployeeCard.station_change_requested`); main
  cierra Personal y `StationPicker` (`scripts/office/station_picker.gd`, hijo de Main) marca en el mapa los puestos de su lugar de
  trabajo (`Staff.get_station_choices`: verde libres, azul ocupados, ámbar el suyo). Un clic en la silla o el escritorio llama a
  `Staff.move_to_station(employee_id, chair_index)`: pasa la asignación de silla o, si es de otro, intercambian (hace falta tener
  silla; la del CEO no se toma; `station_change_problem`). Clic derecho, Esc (`handle_escape` → "station"), Construir, abrir
  Personal o cambiar de ficha cancelan. Prueba `test_station_change`.
- Nómina (`Staff`): cada empleado gana sueldo/30 por día desde `paid_until`; los días 15 y 30 se paga todo o nada.
  Lo que no alcanza queda en `owed`, baja el ánimo y se paga solo al alcanzar el saldo. Despedir cobra lo ganado más
  lo debido (puede dejar saldo negativo). Los avisos al jugador van por `EventBus.notice` y los muestra el `Hud`.
- Ánimo y estrés (`Staff._update_morale`, cada medianoche después de la nómina; valores en `data/staff.json`, morale): cada día se
  acercan 3 / 5 puntos a su meta. Ánimo: 70 + sueldo frente al de su nivel (≥110 % +15, ≥100 % +5, ≥90 % −10, menos −25) − 15 sin
  contrato (salvo vendedores) − 20 con nómina debida − 10 con estrés ≥70. Estrés: 20 + 30 con contrato atrasado + 20 si la energía
  bajó de 50. Con ánimo <30 o estrés >80 tres días seguidos avisa (`quit_day`) y a los 5 días renuncia (cobra lo ganado + lo debido,
  «Liquidación por renuncia»). `Staff.give_raise` (aumento ≥10 % lo retiene, +25 de ánimo; lo ganado antes queda en `carry`).
  Bajo el 110 % y desde 30 días del último aumento, 2 %/día pide +10 % (`raise_request`, 3 días): aceptar +10, negar o dejarlo pasar −15.
  La ficha (`EmployeeCard`, 460 px) lleva cabecera con la foto, el nivel, qué hace y los rasgos (conocidos y «? N ocultos»), estado y
  habilidades lado a lado (la principal del cargo en ámbar), historial en casillas, equipo, horario, sueldo y días en la empresa, avisos,
  pedido (Dar el aumento / Negar) y las filas Aumento y Ascender (con barra de avance); todo se desplaza si no entra. `get_text` junta
  el texto completo de los datos aunque en pantalla vayan repartidos.
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
- Equipos (`Staff.teams`): `{id, name, members, schedule}`; un empleado está como mucho en un equipo. El turno es hora de entrada
  y días (mínimo 1 de descanso); dura 9 h (8 + almuerzo). El contrato guarda quién lo lleva (`team_id`: equipo, `Projects.CEO_TEAM`
  o `NO_TEAM`); un equipo lleva uno a la vez y el tope de contratos es equipos con miembros + 1 (el CEO). Menú Horarios (`TeamsPanel`, antes Equipos).
  Personal, Proyectos, Horarios, Banco y Empresa ocupan el lado izquierdo: abrir uno cierra los otros.
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
  de un Cuarto de limpieza (`Workstations.CLEANING_ROOM`, uno por armario); en su turno quita 25/h × factor a la habitación más sucia
  (`Staff.get_cleaning_room`). Se ve trapeando por partes (solo visual): `main_characters._cleaning_spot` le da una casilla libre que cambia cada
  `mop_minutes` (20) en esa habitación o, sin nada sucio, recorre las habitaciones (`mop_spots_per_room` casillas en cada una; `is_cleaning_now`,
  `_cleaners_on_duty` hace que `main._process` lo mueva). `OfficeCharacter.cleaning`: camina con el suape (pose `mopwalk`) y en su lugar trapea
  (`mop`, `is_mopping`, mirando a un lado distinto por casilla) con el cubo al lado (pieza hija `Bucket`, `SpriteLibrary.get_bucket_sprite`).
- Turno de limpieza (`test_cleaning_shift`): horario de 7 a 15, almuerzo a las 11. Entra a las 7:20 (`cleaning.arrive_minute`) y limpia desde las
  7:30 (`start_minute`), sin sorteo de llegada ni minutos al salir (`Staff.get_cleaning_minutes`, `get_arrival_offset`, `get_leave_minutes`).
  `get_cleaning_start_minute` solo cuenta al entrar (no al volver del almuerzo); `is_cleaning_now` lo respeta y `main_characters._cleaning_starts`
  hace que `main._process` la mande a trapear a ese minuto. `_update_dirt` limpia la hora de entrada solo `(60 − start)/60` y cada uno ×
  `_trait_product(…, "clean")`. Rasgos por cargo en `traits.pools` (`StaffCatalog.get_trait_ids(role)`; `default` para los demás):
  limpieza tiene Meticuloso (`clean` +25 %), Despistado (−20 %), Madrugador (`early_minutes` 20: 7:00 y 7:10), Alegre (`office_mood` +2 a la
  meta de ánimo de todos, una vez: `get_office_trait_mood`), Impuntual, Leal y Adicto al café. No entra en equipos ni proyectos (`no_teams`
  en el cargo, `StaffCatalog.is_role_without_teams`, `Staff.can_join_teams`): `add_to_team` la rechaza, Horarios no la ofrece, «Sin equipo»
  no la lista y al cargar sale de su equipo. `Staff.cleaning_shift_enabled` (solo pruebas) apaga los minutos fijos y los rasgos propios en las partes anteriores.
  Prueba `test_cleaning_view`. `EventBus.dirt_changed`; `DirtOverlay` dibuja una mancha `dirt_*` por casilla manchada (`get_stains`: tantas casillas como la parte sucia, siempre en el mismo orden por casilla; a `STAIN_ALPHA` hasta `dirty_from`). Botones del modo construcción en filas según el ancho (hito 65).
- Competencia (`competition` en `data/staff.json`): cada medianoche (`Staff._update_morale`) otra empresa puede ofrecerle a un SemiSenior o
  Senior, o a un líder, gerente o ejecutivo (cuentan como Senior), su sueldo +15–30 % (`outside_offer`: `{salary, until_day}`, 5 días).
  `Staff.get_offer_chance`: Senior 1 %/día, SemiSenior 0.5 %, ×3 si gana menos que su nivel, ×0.3 desde el 110 %, leal ×0.25, ambicioso ×2.
  Un aumento que la iguala la cierra (+25 de ánimo; `match_offer`); `let_go` o el plazo lo sacan («Liquidación por irse a otra empresa»).
  La ficha muestra el aviso y «Igualar ($X)» / «Dejar ir».
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
- Candidatos según la empresa (hito 56, `hiring` en `data/staff.json`): el primer día de una vacante (`vacancy["first_done"]`, falta = true)
  llega la primera tanda `Staff.get_first_batch()` = 3 + (estrellas enteras − 3), al menos 1, más 1 con publicidad; después, cada día como antes
  (`_roll_daily`). Calidad (`get_candidate_quality`, ±0.8) = 2.5 × (sueldo ofrecido / tabla − 1) + 0.02 × ambiente medio de las Áreas de trabajo
  (`get_work_area_ambiance`); `quality_position` corre cada habilidad dentro de su rango (0.5 = la mitad de arriba); lo que piden no cambia. El
  «Premio de la industria» (efecto `candidates`, 7 días) suma 1 por día a cada vacante (`Staff.award_until`, guardado). Personal muestra el
  pronóstico bajo el sueldo (`describe_hiring_outlook`). `Staff.company_hiring_enabled` (no se guarda) es solo para pruebas: `test_all` lo apaga
  en las partes anteriores a `candidates` (cuentan candidatos y habilidades exactos; las simulaciones de fase siguen iguales).

## Contratos, producción y productos

- `Projects` guarda reputación (empieza en 1 ★), ofertas y contratos (`data/contracts.json`, `ContractCatalog`). A las 9:00
  caducan las ofertas viejas (5 días) y llega una con 50 % + 25 % por vendedor (bandeja de 6). Tamaños: pequeño siempre,
  mediano desde Startup o con un vendedor, grande desde Mediana empresa con 4 ★ y exige Sala de reuniones (hito 47). Plazo = puntos ÷ `points_per_day` del tamaño
  (17 el CEO, 34 un equipo, 100) × `days_slack` (1.1–1.4), hacia arriba (`ContractCatalog.get_days_range`). Contratos en curso: uno por equipo (mínimo 1).
  Aceptar cobra el anticipo (30 %, si trae). El menú Proyectos (`ProjectsPanel`) no pausa.
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
- Errores (`data/contracts.json`, bugs): programar genera `bugs_hidden` (1 cada 20/30/45/70 puntos por nivel, el doble cansado o con estrés ≥70, sin acumularse);
  cada punto de pruebas encuentra cada oculto con probabilidad cobertura × puntos / pruebas del contrato (QA 3, otros 0.2) y
  pasan a `bugs_found`; programadores o CEO los corrigen a 3 puntos (`bugs_fixed`) antes de programar. Con pruebas al 100 % QA
  sigue revisando. El azar sale de `Projects._rng`; `Production.apply` devuelve qué hizo cada uno.
- Entrega (`Projects.deliver`/`cancel`, `preview_delivery`; valores en `data/contracts.json`, delivery): en cualquier momento,
  pago × hecho × (1 − atraso − errores) − anticipo (mín. 0); penalidades sumadas (3 días + 2 errores = 81 %). Errores entregados =
  ocultos + encontrados; el panel solo muestra los conocidos. Reputación 1–5: limpio +0.3, −0.05/error y −0.1/día (hasta −0.5),
  cancelar −0.5 y devuelve el anticipo. Atrasado, se sortea 3–10 días (`cancel_day`): ese día el cliente cancela sin pagar
  más (el anticipo queda). Estrellas enteras (hacia abajo) + valor, arriba a la izquierda en el `Hud`. `history` y `delivered_count`.
- Contratos grandes y élite (hito 47, `data/contracts.json`): grande (`min_stage` 4 = Mediana empresa, 4 ★) y `elite` «De élite» (`min_stage`
  5 = Corporación, 5 ★, puntos del grande, pago ×1.5, clientes de `elite_clients`); los dos exigen Sala de reuniones que funcione
  (`requires_room`, mesa de reuniones 2×2 $1,200). La Sala de reuniones (`unlocked_by_offer` en `data/rooms.json`) se marca solo desde que
  llega la primera oferta que la exige (`Projects.meeting_room_unlocked`, guardado; `_unlock_room_for` en `_make_offer`, aviso y
  `EventBus.rooms_unlocked`; partidas viejas la habilitan si ya hay una sala u oferta que la pide). `Company.room_lock_reason` da el motivo
  al modo construcción. Pantalla de presentaciones (de pared, $800): en una Sala de reuniones que funciona el peso de esos tamaños ×1.25
  (`Projects.get_size_weight`, `meetings.screen_weight_factor`). La pizarra queda para más adelante.
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

## Banco y empresa

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
  (`ObjectivesPanel`, izquierda bajo el dinero con su mismo borde y ancho, `align_provider`; plegable). Las condiciones miran el estado (habitación, cargos, empleados,
  `Projects.accepted_count`, entregados, equipos, etapa, terreno, estrellas, valor) y se revisan con las señales de esos sistemas;
  al cumplirse uno avisa, paga «Objetivo cumplido» y/o `Projects.add_reputation` una sola vez y entra el siguiente.
  `SaveManager` envuelve preparar/cargar en `Company.begin_load`/`finish_load` para no revisar con el estado a medias; una
  partida sin `objectives_done` marca al cargar los que ya cumple, sin recompensa. `main.gd` pliega la lista mientras hay un
  panel izquierdo abierto y al cerrarlo vuelve como el jugador la tenía. Las pruebas que miden saldo o reputación exactos
  marcan todos los objetivos como cumplidos en su `_new_game`. Una recompensa se paga mientras se avisa otro cambio: quien
  escuche `balance_changed` o `company_value_changed` lee el valor actual (`Economy.balance`, `Company.get_value()`), no el de la señal.
- Corporación y salir a bolsa (hito 48, `ipo` en `data/stages.json`): Corporación pide 4 ejecutivos y 3 productos activos. Siendo
  Corporación con valor de más de $5,000,000 (`Company.ipo_problem`) se avisa una vez (`ipo_announced`) y el menú Empresa ofrece
  «Salir a bolsa» con confirmación. `Company.go_public` no da dinero: guarda `public_day`, avisa y emite `EventBus.went_public(stats)`
  (`get_ipo_stats`); `main.gd` pausa, cierra los paneles y abre `IpoScreen` (estadísticas de 9.5 + empleados de hoy; «Seguir jugando»
  vuelve a la pausa de antes, «Volver al menú»). Después la partida sigue en modo libre y Empresa dice «Cotiza en bolsa desde el día X»;
  no se sale dos veces. El terreno no tiene tope propio: se compra hasta llenar el solar.
- Inversionista (hito 58, `investor` en `data/bank.json` y evento `investor` en `data/events.json`, desde Pequeña empresa): el target `investor`
  pide `Bank.make_investor_offer(rng)` (vacío si `investor_problem()`: ya hay uno, valor ≤ 0 o ingresos de contratos y productos del mes pasado bajo
  $5,000): efectivo 10–25 % del valor (de a $1,000), 12–24 meses y parte `investor_share` = efectivo × 1.6 / (ingreso del mes pasado × meses),
  entre 5 y 40 %. Aceptar (efecto `investor`, `Bank.accept_investor`) cobra «Inversión» (no es ingreso: Empresa lo muestra aparte) y guarda
  `Bank.investor` (`income_before` = lo del mes que no le toca). Cada día 1 `_charge_investor` cobra la parte de los ingresos del mes que terminó
  con `Economy.charge` («Pago al inversionista»), aunque deje el saldo negativo; al cumplir los meses termina con aviso. `get_investor_remaining`
  (parte × ingreso del mes pasado × meses que faltan) resta del valor como una parte más de `Company.get_value_parts`. Empresa y Banco tienen su
  sección. `Bank.investor_enabled` (no se guarda) es solo para pruebas: `test_all` lo apaga antes de `investor` (las simulaciones sortean igual).

## Eventos

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

## Interfaz, menús y guardado

- Tema «Oficina de noche» (`UiTheme`, `scripts/ui/ui_theme.gd`): paleta (`BG`, `PANEL`, `CARD`, `BUTTON`, `OUTLINE`, `TEXT`, `MUTED`,
  `ACCENT`, `POSITIVE`, `NEGATIVE`, `INFO`…), Nunito para el texto y las cifras de la barra (`MoneyLabel` usa `number_font`: gruesa y con cifras de ancho fijo, `tnum`) y Pixelify Sans para botones, pestañas y títulos
  (`assets/fonts/`, licencia OFL al lado; sin ligaduras, Pixelify no trae «fi»). `Settings._ready` llama `UiTheme.apply()`, que mezcla el
  tema en el de Godot (`ThemeDB.get_default_theme()`) para que lo tomen también los nodos bajo un `CanvasLayer`. Cajas con bisel desde una
  imagen chica en nueve partes (borde de 2 px, línea clara arriba, franja oscura abajo y sombra corta en los paneles). Variaciones:
  `TitleLabel`, `HeaderLabel` (títulos de panel), `SectionLabel`, `MoneyLabel`, `CaptionLabel`, `MutedLabel`, `StrongLabel`;
  `PrimaryButton`, `DangerButton`, `QuietButton`, `BarButton`, `PrimaryBarButton`, `SpeedButton`; `DialogPanel`, `CardPanel`,
  `AlertPanel`, `HeaderPanel`, `SidebarPanel`. Un `PanelContainer` sin variación (`Hud.make_panel()`) es la tarjeta que flota sobre la
  oficina. Los colores sueltos de los paneles (`MUTED_COLOR`, `NEGATIVE_COLOR`…) apuntan a la paleta.
- Menú principal: barra lateral (`SidebarPanel`) sobre `assets/ui/bg_menu.png` con título, Continuar en acento y la partida que carga
  (`%ContinueInfo`); Cargar, Ajustes y la pregunta de partida nueva reemplazan a los botones en la misma barra. La pausa lleva cabecera
  con la fecha detenida, Seguir en acento y Salir al menú en rojo.
- Escena inicial: `scenes/main_menu.tscn`; la partida es `scenes/main.tscn`.
  La interfaz superpuesta es `Hud` (dinero y reloj) más `BuildPanel` (botón Construir y herramientas).
  La Tienda se abre desde la barra del mapa (botón Tienda junto a Construir, icono `ui_shop`; `get_shop_button`, `set_shop_open`,
  `is_shop_open`, `get_shop`): `ShopScreen` a pantalla completa, sin pausar; con ella abierta el tutorial va bajo su barra
  (`get_top_bar_rect`). Construir es una bandeja abajo. Arriba: las secciones (`BuildPanel.SECTION_*`: Inventario, Estructura, Habitaciones y Terreno) y, fijos a la derecha,
  Paredes, «?» y Salir; la fila se desplaza si no cabe. Abajo, el estado y Mover, Girar, Mejorar, Guardar y Vender. Solo se ve la sección
  abierta (`set_section`, `get_section_of`); Inventario muestra una tarjeta por mueble guardado con su miniatura
  (`SpriteLibrary.get_furniture_icon`) y «×N», o un aviso de que está vacío; Terreno muestra solo su fila (la herramienta va en un botón
  oculto). La Tienda filtra por `category` de `data/furniture.json` (`set_category`, `FurnitureCatalog.get_category`) y su detalle elige
  cantidad y compra; Esc o «Volver al mapa» la cierran. `select_tool` abre la sección; `get_button_toward(tool)` es el botón a pulsar para
  llegar (sin inventario de ese mueble, Salir y luego la Tienda; con inventario fuera de Construir, Construir; lo resalta el tutorial
  con `tool:`). Prueba `test_build_sections`.
  Todo movimiento de dinero pasa por `Economy` con un concepto (queda en `Economy.movements`, los últimos 200, y en
  `Economy.month_totals`, totales por concepto del mes actual y el anterior). Menú Banco (`BankPanel`): saldo, resumen del
  mes con «<»/«>» y movimientos, los nuevos arriba; no pausa. Los botones de la barra se arman con `Hud.style_bar_button(botón, icono)`:
  miden al menos `Hud.MENU_BUTTON_SIZE`, llevan arriba el icono `ui_<icono>` (`SpriteLibrary.get_ui_icon`, dibujado aparte con el color del
  texto según el estado) y Construir va en acento.
  `SaveManager.new_game()` prepara una partida nueva; la oficina inicial está en `data/starting_office.json` y, con
  `SaveManager.start_with_demo` (false por defecto: el CEO solo; true para probar), `StartingCompany.apply()` la convierte en la empresa de `data/starting_company.json`:
  Mediana empresa, local de 22×18, 40 empleados en 6 equipos con líder, 2 gerentes, 2 ejecutivos, apoyo y 7 contratos en curso
  (`Staff.hire_directly`, `Projects.create_offer`). `test_starting_company` y `test_dev_tools` lo ponen en true un momento.
  Las partidas se guardan en `user://saves/` (`autosave.json` y `slot_1.json` … `slot_5.json`); las pruebas
  ponen `SaveManager.save_dir = "user://test_saves"` para no tocar las del jugador.
- Iconos de estado y avisos con destino (hito 57, `status_icons` en `data/staff.json`): `Staff.get_status_icon(empleado)` da el primero de `order`
  que se cumple: `no_station` (sin silla), `tired` (energía < 30), `upset` (ánimo < 30 o aviso de renuncia), `stressed` (estrés ≥ 70) e `idle`
  (`is_idle`). `main.update_status_icons` lo pone en cada `Employee` (`OfficeCharacter.set_status_icon`, sprite `status_<icono>` de `status_icons` en `data/sprites.json`; sin él, el globo con signo de `STATUS_ICONS`) al
  cambiar la hora, el personal, la oficina o los proyectos; nunca por cuadro. Avisos: `EventBus.send_notice(destino, texto)` emite `notice` con
  `get_notice_target()` válido mientras dura; destinos `target_employee/contract/product/room/menu` ("staff", "projects", "teams", "bank",
  "company"). El `Hud` muestra el aviso con destino en celeste con «›»; un clic (`click_notice`) lo cierra y emite `notice_clicked`, y
  `main.open_notice_target` abre la ficha, Proyectos en su pestaña, el menú o centra la cámara en la habitación. `notice.emit(texto)` sigue
  siendo un aviso sin destino. Llevan destino los avisos del personal (renuncia, aumento, oferta de otra empresa, falta, rasgo, ascenso),
  contratos, productos, Banco, Empresa y la habitación sucia.
- Opciones (`Settings`, hito 60; `data/settings.json`): `user://settings.cfg` (`ConfigFile`, sección `options`), aparte de las partidas;
  `get_value`, `set_value` (valida tipo y rango, aplica, guarda y emite `EventBus.settings_changed`), `load_settings` (lo que falta o no sirve
  vuelve a su valor por defecto) y `reset_to_defaults`. Opciones: `fullscreen` (no hace nada sin ventana), `autosave` (`SaveManager`),
  `start_speed` (`GameClock.new_game`), `pause_on_build` y `pause_on_focus_loss` (`main.gd`, `on_focus_lost`; apagada por defecto: el juego sigue en otra ventana). `test_all` usa
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
  la nómina con la velocidad (`speed_changed`: botón o tecla 1–5; resalta 2x), abrir el Banco (`bank_opened`) y entregar (`projects_deliver` =
  Entregar del primer contrato); termina con la primera entrega. Ayuda: `HelpButton.create(tema)` es el «?» (44 px, tooltip «Ayuda») en la
  cabecera de Personal, Proyectos, Horarios, Banco y Empresa y en la fila de secciones de Construir (`get_help_button()`); emite
  `EventBus.help_requested` y `HelpDialog` (capa 12, en `main.gd`, `get_help_dialog`) muestra el título y el texto de `data/help.json`
  (`topics`) sin pausar; «Entendido» o Esc (lo primero que cierra `handle_escape`) la cierran.
- Interfaz escalable (hito 65): opción `ui_scale` (`ui_scales` 75/90/100/125/150 en `data/settings.json`) que pone `content_scale_factor` de la
  ventana (a 150 % en 1280×720 quedan 853×480). `Settings` sube a `min_button_height` (44) el alto mínimo de todo botón que entra al árbol
  (`node_added`, salvo Panku). `UiLayout`: `bottom_space` (lo mide `BuildPanel` desde la barra de menús, ahora `HFlowContainer` que se
  parte en filas) y `top_space` (lo mide `Hud` desde el dinero y el reloj); `EventBus.ui_layout_changed` hace que los paneles izquierdos
  (`fit_left_panel`: ancho hasta la pantalla y alto sobre la barra), la ficha, la tarjeta de eventos (cuerpo desplazable) y Ajustes (pestañas
  desplazables) se acomoden. Personal desplaza todo bajo la cabecera; Construir parte sus herramientas en filas (`HFlowContainer`) según el
  ancho y las desplaza si no entran entre `top_space` y abajo. La tarjeta del tutorial va entre el dinero y el reloj o, si no entra, bajo el
  reloj (`corners_provider` = `Hud.get_corner_rects`). Los botones sin palabras (−, +, <, >, ?, escala) tienen `tooltip_text`. Las pruebas
  sin ventana simulan 1280×720 con `content_scale_aspect = KEEP` (`test_ui_scale`).

## Arte con sprites (fase 8)

- Sprites conectados (fase 8, `SpriteLibrary`, funciones estáticas; `data/sprites.json` lo escribe `tools/sprites/export_game.py`
  a partir de `tools/sprites/art/` (todo dibujado con Moana: muebles, objetos de pared, paredes, pisos, terreno, árboles y personajes),
  junto con `assets/tiles/ground.png` y `assets/sprites/`; después `Godot --headless --import`):
  los sprites van a 2 px por px del mundo (`GroundPainter.DETAIL` 2) y `SpriteLibrary.draw(canvas, nombre, punto)` los dibuja a la mitad con
  su apoyo en el punto. Suelo: `OfficeGrid._build_sprite_tile_set` arma el TileSet con el atlas (una fila por estilo, 4 variantes;
  `ground.png.import` con mipmaps y capas con `TEXTURE_FILTER_NEAREST_WITH_MIPMAPS`); el piso elige variante al azar fijo y el pasto, además,
  familia por zonas (`MapDecor.get_grass_family`: liso, tupido, manchones y claro); `is_style_row(fila, estilo)` dice si una fila dibuja un
  estilo. Sin atlas se pinta con `GroundPainter` como antes. Paredes: `EdgePieceView` dibuja `<pieza>_<tall|low>_<x|y>` (`get_sprite_name`)
  y, encima, el poste de cada unión de sus puntas (`OfficeGrid._place_corner_posts`, `EdgePieceView.get_corner_sprite(brazos)`: toda unión de dos
  tramos o más, L, T, cruz o cambio de alto, salvo dos del mismo alto en línea; `wall_post_<−x><−y><+x><+y>` con n, l, t, d (puerta baja) o
  h (puerta alta), 208 en total, los genera `walls.post_combos`; `EdgePieceView.get_arm_code`). Un brazo de adelante (+x, +y) que es puerta se
  dibuja en el poste como puerta (jamba, sin la tapa de pared); atrás solo cuenta el alto. Entre dos puertas del mismo alto en línea va un poste de
  pared con su tapa entre las dos jambas (`wall_post_dndn`, `ndnd`, `hnhn`, `nhnh`; `walls.MULLIONS`). El canto de las paredes y los postes van del color de la pared; lo oscuro es solo la tapa.
  Árboles: `TreeView` elige `tree_0`…`tree_7` por la casilla y dibuja su `_shadow` al 30 %. Sin sprite, cada uno cae al arte provisional.
  Muebles de piso: `data/sprites.json` `furniture` (id del juego → base del sprite, `rotated`, `parts`; tabla `FURNITURE` de `export_game.py`),
  `SpriteLibrary.get_furniture_sprite(id, rotación, parte)`; `FurnitureView._draw_sprites` dibuja sombra y mueble con el apoyo en el centro de
  la casilla de anclaje (los chicos, su versión `_q` en el centro del cuarto), la computadora y el segundo monitor sobre el centro del escritorio
  (con monitor la computadora se corre `COMPUTER_SHIFT`) y las sillas en dos piezas (`_seat` y `_back`, la de atrás lleva la sombra).
  Personajes: 72 aspectos (8 conjuntos × 3 formas × 3 paletas) sobre 24 hojas en `assets/sprites/characters/`, una por conjunto y forma con
  la paleta base (fila = dirección, columna = cuadro de `poses`: stand, sit, idle ×4, walk ×8, type ×4). Las paletas `_v1`/`_v2` apuntan a
  la hoja base y las pone el shader `scripts/office/character_palette.gdshader`: cambia cada color exacto de la tabla
  `characters.palettes` (aspecto → `from`/`to` en hex, rampa por rampa, hasta `PALETTE_MAX` = 48; `export_game.py` exige que todo píxel de
  la persona sea de una rampa y que no haya blanco puro). `SpriteLibrary.draw_character` le pone al lienzo el material del aspecto
  (`get_character_material`, uno por aspecto; null con la paleta base) y guarda las texturas por archivo. Las
  formas `_f1`/`_f2` de cada conjunto (`_figure.FORMS`) cambian peinado, barba o bigote, lentes y complexión (`ROBUST`, `SLIM`) y usan las
  paletas del conjunto. El personal de limpieza
  tiene además una hoja `<aspecto>_tools.png` con `mop` ×4 y `mopwalk` ×8 (`characters.tool_poses`/`tool_looks`; `SpriteLibrary.has_tool_look`;
  `draw_character` la usa sola) y el cubo `mop_bucket` (`characters.bucket`). `OfficeCharacter.look`
  (`make_look(mujer, "casual"|"office"|"executive"|"cleaning", número)`: paleta = número % 3, forma = número / 3 % 3;
  `OfficeCharacter.forms_enabled` en false, solo en pruebas anteriores a `sprites`, deja la forma de siempre; CEO de traje, `Employee._look_for` por cargo (el personal de limpieza con su overol verde, `cleaning`), nombre e id, visitas y candidatos
  en `Visitor`); `_animate` elige pose, dirección (0–3 como las rotaciones) y cuadro: camina según lo recorrido (`WALK_CYCLES_PER_CELL`),
  sentado en un asiento mira al escritorio con computadora que lo tiene delante y teclea (`_refresh_seat`, también con `office_changed`;
  `can_type` false en visitas), si no `sit`, y de pie `idle`; sentado en una silla se dibuja junto con ella en un solo cuadro (poses
  `sit_<silla>` y `type_<silla>` de la hoja, `_drawn_pose`): el generador compara la profundidad de silla y persona y guarda qué parte de la
  silla tapa a cada cuadro (`<cuadro>_<silla>` en `tools/sprites/art/characters/`, `build.chair_overlays`), y `export_game.py` compone silla + persona +
  esa parte; mientras tanto la silla no se dibuja aparte (`OfficeCharacter.draws_chair_at`, grupo `FurnitureView.CHAIR_GROUP`), solo su sombra.
  Ningún tono de una silla puede ser de la ropa, la piel o el pelo (`check_chair_colors`); solo redibuja al cambiar de cuadro (`get_sprite_state`). Sin hoja, el muñeco provisional.
  Sentado frente a un escritorio o mostrador (`OfficeState.get_desk_facing(casilla)`: `{direction, computer}`), la silla y quien se sienta se
  dibujan arrimados y mirándolo (`get_sprite_rotation`, `OfficeCharacter._tuck`; `grid_position` no cambia). `FurnitureView.get_seat_offset(casilla)`
  arrima hasta dejar el centro de la silla a `SEAT_REACH` (0.26 casillas) del canto del tablero, según `edges` de `data/sprites.json` (hueco
  entre la planta y el canto por lado del modelo, lo escribe cada `build.py` de mesa; `get_table_edge`), sin pasar de `SEAT_TUCK_MAX`. Una
  silla de costado o de reunión (`get_seat_table`: `front` false) se arrima igual si ya mira a la mesa, sin girar;
  mirando a +x o +y, la pieza hija `Hands` (el personaje tiene `y_sort_enabled`) repite la franja de antebrazos `HANDS_BAND` ordenada tras el
  escritorio. El asiento de las sillas va a 24 px de sprite (la cadera del personaje) y el teclado al borde del escritorio. Un mueble largo
  (1×N) se dibuja en una tira por casilla (`PART_SLICE`, `get_slice_count`) para ordenarse bien con paredes y personas.
  Computadoras (dibujadas con Moana en `tools/sprites/art/furniture/`): sobre el escritorio sencillo o el ejecutivo, un sprite aparte (`computer_basic`, `computer_pro`,
  128×160 con apoyo (64, 128)) en el centro del mueble; el escritorio largo se dibuja entero con lo que lleva (`sets` de su entrada en
  `data/sprites.json`: `desk_long_basic`, `desk_long_pro1`/`pro2`/`pro3` según las pantallas extra; con tres la torre va debajo de la mesa;
  `SpriteLibrary.get_desk_set_sprite`). `seats` dice a qué altura del modelo queda el teclado de cada sprite y `FurnitureView.get_seat_shift(casilla)`
  corre de lado (hasta media casilla) a la silla y a quien se sienta para quedar frente a él; con otra silla frente al mismo escritorio no se
  corre ninguna (cada una frente a su casilla). Prueba: `tests/suites/test_seating.gd`.
  Objetos de pared (`wall_items` en `data/sprites.json`: dibujos y `base_z`; `SpriteLibrary.get_wall_item_sprite(id, eje, elección)`):
  `<dibujo>_x`/`_y` según el eje del borde, con el apoyo en el punto medio del borde en el piso; mirando a +x o +y se ve de frente y a −x o −y
  de espaldas (`<dibujo>_back_x`/`_back_y`, `get_wall_item_sprite(…, back)`: colgado del lado de la pared que no se ve); el cuadro elige uno de sus 3 dibujos fijo por casilla; en pared baja se dibuja a
  `LOW_WALL_SPRITE_SCALE` pegado al piso. La pantalla de presentaciones se dibuja de dos bordes de ancho centrada en el suyo (en el juego ocupa uno);
  un objeto de pared más ancho que su tramo va en tiras (`FurnitureView.get_wall_reach`, `PART_SLICE`), cada una ordenada con su tramo y
  solapadas `WALL_STRIP_OVERLAP_PX`, para que la pared vecina no lo tape.
  Manchas de suciedad (`dirt`) y globos de estado (`status_icons`, `get_status_icon_sprite`) también son sprites.
  Sombra de las paredes (`wall_shadow`, `get_wall_shadow_sprite(eje)`): `WallShadowOverlay`, sobre el piso y las manchas, pone
  `wall_tall_<eje>_shadow` en la casilla de mayor x o y de cada tramo alto si es del local (se rehace con las piezas de borde).
  Puertas que se abren (`doors` en `data/sprites.json`: piezas y cuadros; `get_door_frames(pieza)`, `get_door_frame_sprite`): solo
  la `door` alta; `OfficeGrid.update_doors()` (cada cuadro) abre las que tienen un personaje visible a
  `GameConstants.DOOR_OPEN_REACH` casillas de su medio y cierra las demás; `EdgePieceView.set_door_open` pasa de a un cuadro
  `<pieza>_tall_<eje>_open_<n>` cada `DOOR_FRAME_SECONDS` (tiempo real). Los personajes los anota `OfficeGrid.add_object`.
  Pantalla de presentaciones (`on` y `play_frames` en su `wall_items`; `get_wall_item_on_sprite`): prendida de
  `GameConstants.PRESENTATION_SCREEN_HOURS` (8 a 18) con uno de sus tres dibujos por casilla, y de frente pasa sus 12 cuadros
  `_play_<n>` cada `PRESENTATION_SCREEN_FRAME_SECONDS` mientras corre el reloj (`FurnitureView.set_screen_frame`, 0 = apagada).
  Prueba `test_sprites`.

## Sonido (fase 8)

- Sonido (autoload `Audio`, `scripts/autoload/audio.gd`, va después de `Settings`; `data/audio.json`, la cabecera explica las claves): los
  efectos y las dos pistas son WAV en `assets/sounds/` que genera `tools/sounds/make_sounds.py` por síntesis (numpy, sin muestras de afuera;
  después `Godot --headless --editor --quit`). Las pistas (`music_menu`, `music_office`, 22 kHz) se importan en bucle (`edit/loop_mode=2` en
  su `.import`) y los efectos a 44 kHz; todos con compresión QOA. Buses `Music` y `Sfx` bajo `Master`, creados en `_ready`.
- `Audio.play(id)` suena un efecto en un grupo de `players` reproductores con su `volume_db`, `pitch_jitter` y `min_interval` (dos iguales
  más juntos no suenan: devuelve false). Lo piden `EventBus.sound_requested(id)` (construir/vender/no se pudo desde
  `BuildController._play_result`, contratar desde `Staff._hire`) y las señales de `signals` (aviso, contrato aceptado y entregado, objetivo,
  etapa, bolsa, fin, evento, nómina corta, préstamo de emergencia), que se conectan solas con `unbind` según sus argumentos. `payment_recorded`
  suena a caja con la nómina pagada y a alarma con un pago atrasado. Todo `BaseButton` (y el cambio de pestaña de un `TabBar`) que entra al
  árbol hace `click`, salvo los de Panku.
- Música: `EventBus.music_requested(pista)` («menu» desde `main_menu.gd`, «office» desde `main.gd`, «» calla) cruza las pistas en
  `fade_seconds` con dos reproductores; repetir la que suena no hace nada. `get_music_track`, `get_music_player`.
- Volúmenes: opciones `master_volume`, `music_volume` y `sfx_volume` (0–100, enteros; por defecto 80, 60 y 80) en `data/settings.json`;
  `apply_volumes` las pasa a los buses (`linear_to_db`, 0 silencia) al empezar y con `settings_changed`. `OptionsList` las muestra con
  deslizadores de 5 en 5 (`get_volume_slider`).
- Pruebas (`test_audio`): con el controlador mudo de `--headless` (`Dummy`) no se llama `play()` (sus reproducciones no se liberan al cerrar
  y Godot avisa de recursos en uso); el historial (`get_history`, `clear_history`) y la pista cuentan igual. `_exit_tree` suelta los streams.

## Logo (fase 8)

- El edificio isométrico en pixel art de 32×32 (techo en rombo 2:1 como las casillas, borde ámbar, dos ventanas encendidas). Lo genera
  `tools/logo/make_logo.py` con los colores de `UiTheme`: `assets/ui/logo.png` (32 px, el menú principal lo muestra a 96 px junto al título,
  filtro más cercano), `icon.png` (1024 px en baldosa: `config/icon` y el icono de macOS), `assets/ui/app_icon.ico` (`windows_native_icon`
  y el preset de Windows) y `assets/ui/boot_splash.png` (pantalla de arranque sobre el fondo del juego, `use_filter` apagado).
  `test_export` y `test_main_menu` lo revisan.

## Exportación

- Exportación de escritorio (hito 66): `export_presets.cfg` con macOS (universal, firma ad hoc, `com.quincenaoffice.game`), Windows y Linux
  (x86_64, `.pck` aparte) a `build/`; todos exportan los recursos más `data/*.json` (el juego los lee con `FileAccess`) y excluyen lo de
  desarrollo. macOS universal pide `import_etc2_astc`. Nombre «Quincena Office», `config/version` 0.7.0 (los presets la repiten) e icono
  propio (ver Logo). Un autoload nuevo cuyo archivo no viaja se suma a `DEV_AUTOLOADS` del plugin. `test_export` revisa presets, plugin,
  icono y que ningún archivo que viaja nombre lo excluido; `export_desktop.sh` hace la exportación real. Con `--main-pack` lo que falta en el
  paquete se busca en la carpeta actual: la revisión corre desde una vacía.

## Comprobaciones de fase (simulaciones)

- Comprobación de la fase 3 (`test_phase3`): simula con una política simple (aceptar lo que se pueda, entregar lo terminado, el CEO
  de 8 a 17) un CEO solo 3 meses, el primer equipo con $5,000 a 12 meses durante 6 y una empresa que deja de pagar; imprime un resumen
  por mes. Sirve para ajustar `data/bank.json`, `data/stages.json` y `data/contracts.json`.
- Comprobación de la fase 4 (`test_phase4`): desde el CEO solo, una política de jugador construye por pasos (puestos, Recepción,
  terreno al este, oficinas únicas y Cuarto de limpieza al norte, más terreno), contrata por vacantes una plantilla (4 equipos de
  2 diseñadores, 4 programadores y 2 QA con líder, vendedores, contador, recepcionista, limpieza, gerente y ejecutivo) que rellena
  si alguien se va, le da a cada equipo el contrato más grande y al CEO solo pequeños; guarda 1.5 meses de gastos. Llega a Mediana
  empresa (~mes 13) e imprime un resumen por mes; compara 3 meses con el CEO dirigiendo 4 departamentos contra un ejecutivo.
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
- Comprobación de la fase 7 (`test_phase7`, hito 67): en una pantalla de 1280×720 (`content_scale_aspect = KEEP`), desde el menú principal
  (Nueva partida) hasta la primera entrega siguiendo el tutorial solo con eventos del ratón (clics en lo que resalta, arrastre de la cámara,
  clic en casillas del local con `grid.get_canvas_transform() * cell_to_world`, y si la interfaz las tapa (`gui_get_hovered_control`) arrastra
  la cámara con el clic derecho; clic derecho para girar muebles, rueda para llegar a botones de listas desplazables, «+» si el candidato pide
  más); entre pasos solo deja correr el reloj (`GameClock.advance`, con el reloj detenido para que no salgan eventos). Con ventana el cursor
  real se mezcla con los eventos de la prueba: se corre sin ventana. Comprueba que el marco del tutorial encierra cada botón que pulsa y que no llegó ninguna tecla. Tres semillas; termina
  a tiempo hacia el día 6–9 con unos $22,000. Sin cambios de datos ni de balance.
