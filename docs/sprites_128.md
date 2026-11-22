# Guía de sprites a 128 px (Quincena Office)

Instrucciones para quien genere el arte pixel por pixel (persona o IA). Todo sale de cómo dibuja hoy el juego
(`data/construction.json`, `data/furniture.json`, `data/map.json`, `GroundPainter`, `IsoBox`).

## 1. Escala y formato

- El mundo usa casillas isométricas de **64×32 px** (1 casilla = 1 m²). Los sprites se dibujan al **doble**:
  **1 px del mundo = 2 px del sprite**. Una casilla de piso mide entonces **128×64 px** de sprite.
- Con el zoom de referencia del juego (2.0) cada pixel del sprite cae en 1 pixel de pantalla: pixel art 1:1.
- PNG RGBA de 8 bits, sRGB, fondo transparente. Alfa solo **0 o 255** (sin bordes semitransparentes ni antialias).
- Nada de suavizado, desenfoque, degradados continuos ni ruido fino de 1 px por todo: usar bloques, tramas
  ordenadas (dither) y paletas cortas (8–16 colores por material o mueble).
- Nombres en inglés y `snake_case`: `floor_ceramic_0.png`, `desk_simple_r1.png`, `wall_tall_x.png`…

## 2. Lienzo de 128×128 y punto de apoyo

- Lienzo estándar: **128×128**. La planta (el rombo de la casilla) ocupa la **mitad de abajo**: filas 64–127.
- **Punto de apoyo** (lo que el juego pone en el centro de la casilla): **(64, 96)**, centro del rombo.
- Todo lo que tiene altura crece hacia arriba desde el rombo. En 128×128 cabe una altura de **64 px de sprite**
  (32 px del mundo) sobre el piso.
- Lo que no entra usa un lienzo más alto o más ancho con la **misma regla**: rombo pegado abajo y apoyo en el
  centro del rombo (ver tablas de muebles y paredes).

## 3. El rombo exacto

Un pixel `(x, y)` del lienzo de 128×128 es parte del rombo si, con `cy = y − 64`:

```
|x + 0.5 − 64| / 64 + |cy + 0.5 − 32| / 32 ≤ 1
```

- Fila de arriba del rombo (y = 64): 2 px (x 63–64). Las filas del medio (y = 95 y 96): 126 px (x 1–126).
  Abajo es simétrico. Total 4,096 px pintados.
- Los bordes van en escalera de **2 px horizontales por 1 vertical** (línea isométrica 2:1 limpia, sin saltos de 1 o 3).
- Prueba obligatoria: copiar el rombo desplazado (±64, ±32) en una imagen grande; **no debe quedar ni un hueco ni un pixel encimado**.

## 4. Luz y caras

- Luz desde **arriba a la izquierda**, la misma en todo el juego.
- Cara de arriba: color base. Cara izquierda: base **−25 %** de brillo. Cara derecha: base **−40 %**.
- Contorno: 1 px de un tono **más oscuro del mismo color** (no negro puro). Brillo de 1 px en la arista superior izquierda.
- Sombra en el piso: opcional, mancha de 1 tono oscuro con alfa 255 dentro del rombo, hacia abajo a la derecha.
  Mejor en un archivo aparte (`*_shadow.png`) para que el juego la ponga con transparencia.

## 5. Pisos y terreno (lo más importante)

Cada material es **una casilla de 128×64** (o en el lienzo de 128×128 con el rombo abajo y la mitad de arriba vacía).

### Reglas para que se repitan sin costuras

- Cada casilla debe empalmar con **sí misma** y con **todas sus variantes** en los 4 lados.
- Lo que cruza el borde (vetas, juntas, manchas) se dibuja **periódico**: lo que sale por un lado entra por el lado opuesto.
- **4 variantes** por material (`_0` a `_3`): mismo borde y mismo color medio, cambia solo el interior (vetas,
  piedritas, briznas). El juego elige una por casilla con un azar fijo.
- Cada variante, vista de lejos, debe tener **el mismo brillo medio**: si no, se ve un tablero de ajedrez.
- Los dibujos siguen los **ejes isométricos** (líneas a 2:1), nunca horizontales ni verticales de pantalla.

### Materiales

| Archivo | Material | Colores base (hex) | Dibujo dentro de la casilla |
| --- | --- | --- | --- |
| `floor_ceramic_*` | Cerámica | blancos `e8e8e8`, `e1e1e1`; junta `a3a1a0` | 2×2 losas en damero de dos blancos con junta gris de 1 celda (más honda en el cruce), esquinas redondeadas, bisel claro arriba y en sombra abajo, nubes muy suaves en el esmalte y un reflejo en diagonal que cambia de losa con la variante. La junta va en el **borde** de la casilla y en el medio, así empalma. |
| `floor_wood_*` | Madera | naranjas `ad6d40`, `a5663a`; junta `783a13` | 8 tablas angostas a lo largo de un eje con dos cortes por fila escalonados; cada tabla con su tono, canto de arriba con luz, punta en sombra, vetas largas en dos tonos, moteado y algún nudo. La tabla que cruza el borde es igual en las 4 variantes. |
| `floor_carpet_*` | Alfombra | lilas `7d80a0`, `8688a4` | De pared a pared: 4 lilas cercanos en manchas suaves con el borde tramado y fibras sueltas más oscuras y más claras; sin juntas ni brillo. |
| `floor_bare_*` | Sin piso (concreto) | grises cálidos `878581`, `8b8985` | Concreto de muy poco contraste con manchas de llana, árido suelto, poros con labio claro y una grieta fina en escalera 2:1. |
| `ground_grass_<familia>_*` | Pasto del solar | `81a73a`, `719236`, briznas `9ecc42`/`cbf166` | 4 familias (`plain` liso, `patchy` manchones, `lush` tupido, `sunny` claro), cada una con sus 4 variantes y **el mismo anillo del borde en las 16**, así cualquier casilla empalma con cualquier otra. Manchas suaves (suma de ondas periódicas, sin rombos), borde de cada mancha tramado y matas de briznas con su sombra de 1 px. Sin flores (se ven repetidas). El juego elige la familia por zonas (ruido suave sobre el mapa: liso 40 %, tupido 23 %, manchones 22 %, claro 15 %) y la variante al azar. |
| `ground_outside_<familia>_*` | Pasto fuera del solar | el pasto 15 % más oscuro | Igual que el pasto (mismas familias y anillo propio común a las 16), más apagado. |
| `ground_path_*` | Camino de grava | grises cálidos `afa38c`, `bcb19b` | Piedras de 2×1 a 6×3 px con luz arriba y sombra de 1 px abajo, sobre grava fina en 4 tonos. |
| `ground_sidewalk_*` | Acera | grises claros `a8a7a1` | Una losa por casilla: junta de 2 px en el borde, bisel claro arriba y sombra abajo, moteado de áridos. |
| `ground_road_*` | Calle | asfalto `494c52`, `44474d` | Asfalto en 4 tonos con granos de árido claros y manchas de alquitrán. |
| `ground_road_line_*` | Calle con línea | igual que la calle; línea `e0cf78` | Línea amarilla de 4 px de ancho por el centro, a lo largo del eje (`_x` o `_y`), algo gastada; el juego la corta cada tantas casillas usando `ground_road_*` donde no va. |

Todos los suelos (`floor_*` y `ground_*`) se dibujan con Moana en `tools/sprites/art/ground/` (`_ground_kit.py`:
rejilla isométrica periódica, anillo común, mezcla de cortes y comprobaciones de brillo y de anillo).

## 6. Muebles

- Tamaño del lienzo según su planta (ancho × fondo en casillas) y su alto (`height` en `data/furniture.json`, en px del mundo):
  - ancho del lienzo = (ancho + fondo) × 64
  - alto del rombo de la planta = (ancho + fondo) × 32
  - alto del lienzo = alto del rombo + `height` × 2, redondeado hacia arriba a múltiplo de 32
  - apoyo = centro del rombo de la **casilla de anclaje** (la primera); dibujar la planta completa pegada abajo.
- **4 rotaciones** por mueble (`_r0` a `_r3`), el frente mira a:
  - `r0`: arriba-derecha (se ve la espalda) · `r1`: abajo-derecha · `r2`: abajo-izquierda · `r3`: arriba-izquierda (espalda).
  - Como la luz viene de la izquierda **no se puede espejar** una rotación para sacar otra sin rehacer las sombras.
  - Muebles simétricos (planta, zafacón, lámpara, rack…) pueden tener una sola imagen.
- **Muebles chicos** (`small`: planta pequeña, zafacón, dispensador de agua, lámpara de pie): el juego los dibuja al 60 %
  en un cuarto de la casilla. Dibujarlos en 128×128 como si ocuparan la casilla entera; el juego los achica.
- **Sillas de oficina** (con Moana en `tools/sprites/art/furniture/chair_basic/` y `chair_ergonomic/`, kit `_chair_kit.py`):
  `chair_basic` (roja, respaldo acolchado con panel) y `chair_ergonomic` (azul, apoyabrazos y respaldo alto de malla), sobre base de
  estrella con ruedas y columna de metal; asiento a 24 px (la cadera del personaje sentado). Cada rotación va entera, en capas
  `_seat_r<n>` y `_back_r<n>` (el juego dibuja el respaldo encima en r0 y r3, debajo en r1 y r2) y con `_r<n>_depth.png`, la
  profundidad por pixel que usa `character.py` para la parte de la silla que tapa a quien se sienta.
- **Computadoras** (dos niveles; con Moana en `tools/sprites/art/furniture/`, como los escritorios): `computer_basic` (todo en uno crema, teclado y ratón crema) y `computer_pro` (monitor plano negro de
  34×25 px con pie de 8, torre negra con luz azul, teclado y ratón negros) van **encima** de un escritorio: lienzo de 128×160 con el apoyo
  en (64, 128), dibujados a la altura de la superficie del escritorio (22 px del mundo = 44 px de sprite sobre el piso).
- **Escritorio largo** (`desk_long_r0`–`_r3`, 2×1, tablero de 92 px centrado en sus dos casillas): se dibuja entero con lo que lleva encima,
  un sprite por conjunto: `desk_long_basic`, `desk_long_pro1` (torre y pantalla), `desk_long_pro2` (la segunda pantalla girada hacia quien se
  sienta) y `desk_long_pro3` (tres en alas y la torre en el piso, debajo de la mesa). Las pantallas extra no tienen sprite propio.

| Mueble | Planta | Alto (mundo) | Lienzo |
| --- | --- | --- | --- |
| Silla básica / ergonómica, inodoro, microondas, cafetera, impresora | 1×1 | 14–18 | 128×128 |
| Escritorio simple, batería, archivero, lavamanos, planta grande, armario de limpieza | 1×1 | 18–30 | 128×128 |
| Dispensador de agua, lámpara de pie (chicos) | 1×1 | 34 | 128×160 |
| Nevera, máquina expendedora | 1×1 | 40 | 128×160 |
| Rack de servidores | 1×1 | 44 | 128×160 |
| Escritorio ejecutivo, mostrador, sofás, mesa de comedor, pecera | 2×1 | 12–26 | 192×160 (o 192×128 si `height` ≤ 16) |
| Mesa de reuniones, ping pong | 2×2 | 12–20 | 256×192 |
| Alfombra | 2×2 | 1 | 256×128 (solo el rombo, como un piso) |

- **Laptop** (`computer_laptop_r0`–`_r3`, Moana, `_laptop.py`): sigue una laptop isométrica de pixel art clásica, con sus
  colores: base gris claro de 22×15 unidades y 3 px con cantos oscuros y brillo blanco arriba, teclado como bloque oscuro con
  una rejilla clara de 1 px, touchpad grande con la mitad de adelante en sombra, y la tapa recta (vertical, para que sus
  aristas queden en escalera 2:1 limpia) de 30 px con bisel claro fino, línea oscura y pantalla azul petróleo lisa. Mismo
  lienzo y apoyo que las otras computadoras. Solo va sobre el escritorio ejecutivo.
- **Mesa de reuniones de vidrio** (`glass_meeting_table_r0`–`_r3`, Moana, 2×2, lienzo 256×192 con apoyo (128, 96)): tablero
  aguamarina sobre marco y patas de cromo; como el PNG no admite transparencia a medias, el marco que se ve a través del vidrio
  va pintado encima en un tono más oscuro.
- Decoración (`tools/sprites/pieces/decor.py`): `floor_lamp` y `floor_lamp_q` (la lámpara chica ya al 60 %), una sola
  imagen por ser simétrica; `rug` (2×2, una sola imagen); `aquarium_r0`–`_r3` (mueble con puertas al frente y tanque
  encima, 56 px de sprite de alto: más que su `height` de 20, para que se lea como pecera). Cada uno con su `_shadow`
  salvo la alfombra.
- Recepción (`tools/sprites/pieces/reception.py`): `reception_counter_r0`–`_r3` (2×1: mesa de trabajo sobre dos
  cajoneras de metal del lado de la recepcionista, que es el frente, y panel alto con mesón crema del lado del
  cliente); `waiting_sofa_r0`–`_r3` (2×1, respaldo de 38 px: más que su `height` de 12); `water_dispenser_r0`–`_r3`
  y `water_dispenser_q_r0`–`_r3` (chico: grifos solo al frente); `trash_can` y `trash_can_q` (chico y simétrico, 26 px de alto: más que su `height` de 10). Cada
  uno con su `_shadow`.
- Trabajo: `executive_desk_r0`–`_r3` (Moana, `tools/sprites/art/furniture/executive_desk/`; 2×1, superficie
  en z = 44 como el escritorio sencillo para que las computadoras se apoyen igual, aunque el ejecutivo tenga `height` 26);
  en `tools/sprites/pieces/office_extra.py`, `printer_r0`–`_r3` (impresora sobre un mueble bajo), `filing_cabinet_r0`–`_r3`, `backup_battery_r0`–`_r3` y
  `meeting_table` (2×2, redonda: una sola imagen).
- Sala de descanso (`tools/sprites/pieces/break_room.py`): `sofa_r0`–`_r3` (2×1), `fridge_r0`–`_r3`,
  `microwave_r0`–`_r3` y `coffee_maker_r0`–`_r3` (cada uno sobre su mueble bajo de cocina, que ocupa la casilla),
  `vending_machine_r0`–`_r3`, `ping_pong_r0`–`_r3` (2×2) y `dining_table_r0`–`_r3` (2×1, con un banco a cada lado).
- Baño, limpieza y servidores (`tools/sprites/pieces/services.py`): `toilet_r0`–`_r3`, `sink_r0`–`_r3`,
  `cleaning_closet_r0`–`_r3` (con balde y trapeador al lado) y `server_rack_r0`–`_r3`. Todos con su `_shadow`.

## 7. Objetos de pared

Cuadro, reloj, pizarra, pantalla de presentaciones y aire acondicionado se cuelgan en una cara de pared.

- Dos versiones: para pared a lo largo de `x` y a lo largo de `y` (ver 8), dibujados **sobre** el plano de la pared,
  inclinados 2:1 como ella.
- Lienzo 64×128, base del objeto a 24 px del mundo (48 px de sprite) sobre el piso.
- En las paredes bajas el juego los dibuja chicos y pegados abajo: no hace falta otra versión.
- Nombres: `painting_x` (paisaje), `painting_abstract_x` y `painting_sea_x` (tres dibujos del cuadro),
  `wall_clock_x`, `whiteboard_x`, `presentation_screen_x` (dibujada como un televisor grande colgado, de marco negro delgado, que ocupa dos bordes seguidos de la misma pared, de media pared a casi el techo: lienzo de 128×192, x de 0 a 2, con el apoyo en (64, 160), el punto medio de los dos bordes en el piso; en el juego ocupa un solo borde (decidido al conectar los sprites): se dibuja centrada en él y sobresale medio borde a cada lado; variantes encendidas con una presentación para la Sala de reuniones: `presentation_screen_chart_x`, `_pie_x` y `_title_x`) y
  `air_conditioner_x`, más sus `_y`. Apoyo (32, 112), el
  punto medio del borde en el piso como en los tramos; el objeto sale de la cara de la pared (4 px de la línea del
  borde) y mide de alto el `height` de `data/furniture.json` × 2. En las paredes `_x` los dibujos van espejados
  para leerse igual que en las `_y`.

## 8. Paredes, puertas y ventanas

La vista es fija desde una esquina. Las paredes del **fondo** del local se ven a su alto; todas las demás (frente e
interiores) van **bajitas** para ver adentro.

- Una pared ocupa el **borde** de una casilla, no la casilla: un tramo es la diagonal de un lado del rombo, **64×32 px** de sprite.
- Dos orientaciones: `_x` (la línea va de arriba-derecha a abajo-izquierda, «/») y `_y` (de arriba-izquierda a abajo-derecha, «\»).
- Grosor: 8 px de sprite, con la cara de arriba visible.

| Pieza | Alto alto (mundo → sprite) | Alto bajo | Color base | Lienzo alto / bajo |
| --- | --- | --- | --- | --- |
| Pared | 60 → 120 | 10 → 20 | `d8d0c4` | 72×160 / 72×64 |
| Puerta | 46 → 92 | 10 → 20 | `8a5a34` | 72×160 / 72×64 |
| Ventana | 60 → 120 | 10 → 20 | vidrio `9fc7dc` | 72×160 / 72×64 |
| Puerta doble de vidrio | 50 → 100 | 10 → 20 | vidrio `a9d4e6`, marco `4f5862` | 72×160 / 72×64 |

- La pieza baja es el **zócalo** de la alta: mismo color y misma cara de arriba.
- Colores de pared: cada pieza (tramo, puerta, ventana y poste de esquina) viene en varios colores de cara con la
  misma tapa: sin color en el nombre la de siempre, y `wall_<color>_tall_x`, `door_<color>_low_y`… para las demás
  (beige, white, sage, peach). Un tramo empalma con los de su mismo color.
- Los tramos se ponen uno al lado del otro: el extremo de uno debe empalmar con el siguiente (y con una esquina en L).
- Variantes de puerta, con las mismas medidas: `door_*` (beige), `door_wood_*` (madera) y `door_office_*` (lisa
  con mirilla y marco de aluminio). La puerta doble de vidrio es `glass_door_*`; la ventana, de oficina (aluminio y
  persiana veneciana). Para la Recepción hay también una doble de vidrio **sin marco** que ocupa **dos bordes
  seguidos**: dos hojas de 48 px (hueco de 96 px, 16 px de pared a cada lado), en dos mitades
  `glass_door_double_a_*` (el borde de menor x o y) y `glass_door_double_b_*`, que solo empalman entre sí.
- Presentaciones del televisor (Sala de reuniones): `presentation_screen_<chart|pie|title>_<eje>_play_1` a `_12`
  (kind `wall_item_frame`): la diapositiva se arma de a poco (las barras suben, la torta se dibuja en un barrido,
  la portada se escribe) con una curva suave; mismo lienzo, apoyo y silueta que la pieza y el `_12` es la pieza
  quieta. El manifiesto da `base`, `frame` y `frames`.
- Animaciones (solo las piezas altas; el cuadro 0 es la pieza cerrada): `<pieza>_tall_<eje>_open_1` a `_6` en las
  puertas (la hoja gira de 15° en 15° hasta 90° hacia adentro; la de vidrio tiene dos hojas que abren hacia afuera)
  y `window_tall_<eje>_blind_1` a `_6` (la persiana baja hasta cerrar). La hoja abierta sale del tramo, así que
  los cuadros de una animación van en un lienzo propio, igual para los tres; el manifiesto da `anchor` (el mismo
  punto del piso que la pieza), `base` y `base_offset` (dónde cae el lienzo de la pieza en el cuadro).

## 9. Personajes

- De pie miden unos **50 px del mundo = 100 px de sprite**: lienzo 128×128, pies en (64, 112).
- 4 direcciones (como las rotaciones), animaciones: parado (1–2 cuadros), caminar (4–6), sentado (1), sentado
  trabajando (2). Sentado, la cadera a 24 px de sprite sobre el piso.
- Piezas intercambiables (pelo, piel, camisa, pantalón) en capas aparte ayudan a tener muchos empleados distintos.
- Hechos (`tools/sprites/pieces/character.py`): cabeza grande, cuerpo robusto y dos ojos oscuros; de pie y sentado en 4
  direcciones con 8 conjuntos: `character_` (casual), `character_office_`, `character_executive_`, `character_woman_`,
  `character_woman_office_`, `character_woman_executive_`, `character_cleaning_` y `character_woman_cleaning_` (overol verde de
  limpieza; solo ellos tienen además `_mop_r<n>_1`…`_4`, trapeando con el suape, y `_mopwalk_r<n>_1`…`_8`, caminando con él: capas
  `stick` y `mop`; el cubo es `mop_bucket` en `services.py`); cada uno con `_v1` (piel oscura) y `_v2` (piel clara) en `r1`,
  que solo cambian la paleta. Animaciones por conjunto y dirección: `_walk_r<n>_1`…`_8`, `_idle_r<n>_1`…`_4` y
  `_type_r<n>_1`…`_4` (sentado tecleando). Por cada cuadro sentado y cada silla, `character_chairs/<cuadro>_<silla>.png` es la parte de la
  silla que queda delante de la persona (comparando su profundidad con la de `<silla>_r<n>_depth.png`): con ella se arma el cuadro «sentado en su silla» (silla entera + persona + esa parte). El juego las usa en hojas (`tools/sprites/export_game.py`), con las tres paletas.

## 10. Árboles y otros

- Árbol: planta 1×1, lienzo 128×256, apoyo en (64, 224). 3–4 variantes de copa.
- Manchas de suciedad: 128×128, solo dentro del rombo, 3 variantes.
- Hechos (`tools/sprites/pieces/trees.py`, `bushes.py` y `dirt.py`): ocho árboles de copas de bultos redondos, verde
  claro: `tree_0` (roble con horqueta), `tree_1` (copa en gota), `tree_2` (abeto de pisos), `tree_3` (cerezo con flores),
  `tree_4` (copa de bola), `tree_5` (ciprés), `tree_6` (árbol joven) y `tree_7` (pirámide ancha), cada uno con su
  `_shadow` y su animación `tree_<n>_fall_1` a `_16` (kind `tree_frame`: hojas o pétalos que caen meciéndose y quedan un
  momento en el piso; ciclo que empalma, mismo lienzo y apoyo; el manifiesto da `base`, `frame` y `frames`). Arbustos y
  setos (kind `bush`, lienzo de mueble según su planta): `bush_0` a `bush_2` (redondo, chico y bajo), `bush_3` a `bush_5`
  (los mismos con frutos rojos, frutos azules y flores naranjas), `hedge_cube` (1×1), `hedge_long_r0`/`_r1` (2×1) y
  `hedge_corner_r0` a `_r3` (L en 2×2), con su `_shadow`; `dirt_0` (barro y huellas),
  `dirt_1` (café derramado) y `dirt_2` (migas y papelitos), kind `overlay`.

## 11. Lista de revisión

- [ ] Rombo exacto (sección 3) y prueba de desplazar ±64/±32 sin huecos ni encimados.
- [ ] Cada piso empalma consigo mismo y con sus 4 variantes en los 4 lados.
- [ ] Mismo brillo medio entre variantes.
- [ ] Alfa solo 0/255; sin antialias contra lo transparente.
- [ ] Luz desde arriba a la izquierda; caras −25 % y −40 %.
- [ ] Apoyo en el centro del rombo de abajo; nada se sale del lienzo.
- [ ] Líneas en escalera de 2:1.
