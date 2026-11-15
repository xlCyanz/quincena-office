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
| `floor_ceramic_*` | Cerámica | `c9b48a`, `b39c72` | 2×2 losas (cada una un rombo de 64×32) con junta de 2 px un tono más oscuro y bisel de 1 px claro arriba-izquierda, oscuro abajo-derecha. La junta va en el **borde** de la casilla y en el medio, así empalma. |
| `floor_wood_*` | Madera | `8f6b4a`, `7d5c3f` | 4 tablones paralelos a un eje isométrico, separados por una línea oscura de 1 px; veta de 2–3 tonos en trazos largos; cortes de tablón escalonados (no todos en la misma fila). |
| `floor_carpet_*` | Alfombra | `5b6f8a`, `52657e` | 2×2 cuadros de alfombra con borde apenas marcado y trama fina ordenada (dither 2×2), sin brillo. |
| `floor_bare_*` | Sin piso (concreto) | `8c8a86`, `807e7a` | Concreto liso con poros sueltos y alguna grieta fina; muy poco contraste. |
| `ground_grass_<familia>_*` | Pasto del solar | `5f8a4c`, `567e44` | 4 familias (`plain` liso, `patchy` manchones, `lush` tupido, `sunny` claro), cada una con sus 4 variantes y **el mismo anillo del borde en las 16**, así cualquier casilla empalma con cualquier otra. Manchas más chicas que la casilla y matas de briznas más claras arriba. Sin flores (se ven repetidas). El juego elige la familia por zonas (ruido suave sobre el mapa: liso 40 %, tupido 23 %, manchones 22 %, claro 15 %) y la variante al azar: así no se ve un solo dibujo repetido. |
| `ground_outside_<familia>_*` | Pasto fuera del solar | el pasto 15 % más oscuro | Igual que el pasto (mismas familias), más apagado. |
| `ground_path_*` | Camino de grava | grises cálidos | Piedritas de 2×1 a 3×2 px con su sombra de 1 px abajo-derecha. |
| `ground_sidewalk_*` | Acera | grises claros | Losas grandes (1 por casilla) con junta de 2 px en el borde. |
| `ground_road_*` | Calle | asfalto gris oscuro | Granos sueltos de 1 px, 2–3 tonos. |
| `ground_road_line_*` | Calle con línea | igual que la calle | Línea blanca discontinua de 4 px de ancho por el centro, a lo largo de un eje isométrico; el juego corta la línea cada tantas casillas, así que hacer una casilla **con** línea y usar `ground_road_*` donde no va. |

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
- **Computadoras y segundo monitor** van **encima** de un escritorio: lienzo de 128×128 con el apoyo en (64, 96), dibujados
  a la altura de la superficie del escritorio (22 px del mundo = 44 px de sprite sobre el piso).

| Mueble | Planta | Alto (mundo) | Lienzo |
| --- | --- | --- | --- |
| Silla básica / ergonómica, inodoro, microondas, cafetera, impresora | 1×1 | 14–18 | 128×128 |
| Escritorio simple, batería, archivero, lavamanos, planta grande, armario de limpieza | 1×1 | 18–30 | 128×128 |
| Dispensador de agua, lámpara de pie (chicos) | 1×1 | 34 | 128×160 |
| Nevera, máquina expendedora | 1×1 | 40 | 128×160 |
| Rack de servidores | 1×1 | 44 | 128×160 |
| Escritorio ejecutivo / amplio, mostrador, sofás, mesa de comedor, pecera | 2×1 | 12–26 | 192×160 (o 192×128 si `height` ≤ 16) |
| Mesa de reuniones, ping pong | 2×2 | 12–20 | 256×192 |
| Alfombra | 2×2 | 1 | 256×128 (solo el rombo, como un piso) |

## 7. Objetos de pared

Cuadro, reloj, pizarra, pantalla de presentaciones y aire acondicionado se cuelgan en una cara de pared.

- Dos versiones: para pared a lo largo de `x` y a lo largo de `y` (ver 8), dibujados **sobre** el plano de la pared,
  inclinados 2:1 como ella.
- Lienzo 64×128, base del objeto a 24 px del mundo (48 px de sprite) sobre el piso.
- En las paredes bajas el juego los dibuja chicos y pegados abajo: no hace falta otra versión.
- Nombres: `painting_x` (paisaje), `painting_abstract_x` y `painting_sea_x` (tres dibujos del cuadro),
  `wall_clock_x`, `whiteboard_x`, `presentation_screen_x` (dibujada como un televisor sobre una repisa, 36 px de alto: más que su `height`) y
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
- Animaciones (solo las piezas altas; el cuadro 0 es la pieza cerrada): `<pieza>_tall_<eje>_open_1` a `_3` en las
  puertas (la hoja gira 30°, 60° y 90° hacia adentro; la de vidrio tiene dos hojas que abren hacia afuera)
  y `window_tall_<eje>_blind_1` a `_3` (la persiana baja hasta cerrar). La hoja abierta sale del tramo, así que
  los cuadros de una animación van en un lienzo propio, igual para los tres; el manifiesto da `anchor` (el mismo
  punto del piso que la pieza), `base` y `base_offset` (dónde cae el lienzo de la pieza en el cuadro).

## 9. Personajes

- De pie miden unos **50 px del mundo = 100 px de sprite**: lienzo 128×128, pies en (64, 112).
- 4 direcciones (como las rotaciones), animaciones: parado (1–2 cuadros), caminar (4–6), sentado (1), sentado
  trabajando (2). Sentado, la cadera a 24 px de sprite sobre el piso.
- Piezas intercambiables (pelo, piel, camisa, pantalón) en capas aparte ayudan a tener muchos empleados distintos.

## 10. Árboles y otros

- Árbol: planta 1×1, lienzo 128×256, apoyo en (64, 224). 3–4 variantes de copa.
- Manchas de suciedad: 128×128, solo dentro del rombo, 3 variantes.

## 11. Lista de revisión

- [ ] Rombo exacto (sección 3) y prueba de desplazar ±64/±32 sin huecos ni encimados.
- [ ] Cada piso empalma consigo mismo y con sus 4 variantes en los 4 lados.
- [ ] Mismo brillo medio entre variantes.
- [ ] Alfa solo 0/255; sin antialias contra lo transparente.
- [ ] Luz desde arriba a la izquierda; caras −25 % y −40 %.
- [ ] Apoyo en el centro del rombo de abajo; nada se sale del lienzo.
- [ ] Líneas en escalera de 2:1.
