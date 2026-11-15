# Estilo de los sprites (referencia: «Isometric Interiors», @pixel_Salvaje)

Pedido del usuario (15-11-2026): los sprites toman los **colores y la forma de dibujar** del paquete
«Isometric Interiors» (https://pixel-salvaje.itch.io/isometric-interiors), pero con las **medidas y reglas de
`docs/sprites_128.md`** (rombo, lienzos, apoyos, 2:1, alfa 0/255, rotaciones, 4 variantes de piso).

**Límite:** es un paquete de pago cuya licencia no permite redistribuirlo. Se copia el **estilo** (paleta, contorno,
proporciones, nivel de detalle, manera de sombrear), no los sprites: cada pieza se diseña de nuevo para nuestro
catálogo y nuestras medidas, sin calcar ni reproducir un dibujo concreto del paquete. Las imágenes de referencia
(capturas públicas de la página) están en el scratchpad de la sesión, no en el repo.

## Rasgos del estilo

1. **Contorno oscuro grueso y continuo** alrededor de cada objeto: 1 px de sprite del tono más oscuro del material
   (marrón casi negro en madera, negro en aparatos), a 2 px donde la silueta da contra el piso. Las aristas
   interiores entre caras van con una línea oscura de 1 px del material, no con el contorno.
2. **Colores saturados y cálidos**, pocos tonos por material (4–5) y bien separados. Nada de grises apagados en
   muebles; la madera es naranja.
3. **Brillo de 1 px** en las aristas superiores que dan a la luz (arriba a la izquierda), un tono más claro que la
   cara de arriba. Sin texturas finas sobre caras grandes: lisas, con algún detalle grande (tablones, paneles,
   tiradores, costuras).
4. **Formas chatas y algo redondeadas**: esquinas del tablero con 1 px recortado, cojines y asientos abultados con
   una sombra de 1 px abajo, patas gruesas de 2–4 px.
5. **Sombras dentro de la planta**: bajo los muebles una mancha de un tono oscuro del piso, sin transparencia en el
   sprite (archivo `*_shadow` aparte, como dice la guía).
6. **Paredes**: cara interior lisa de color pastel frío; tapa de la pared y canto de la losa del piso en ciruela
   oscuro (borde de la «maqueta»). El zócalo bajo repite la tapa ciruela. Sin contorno donde la pared toca el
   piso (la cara llega limpia, `finish(ground_outline=0)`), y donde una pared alta termina sobre una baja el
   corte (el poste de esquina) va entero en ciruela, hasta el piso (el tramo bajo arranca en el borde del poste).
   Cinco colores de cara con la misma tapa ciruela (`WALL_COLORS` en `pieces/walls.py`): fría `899da0` (la de
   siempre, sin color en el nombre), beige `b3a792`, blanco `c8c4bb`, salvia `91a689` y durazno `c69f88`. Cada
   color trae tramos, puertas, ventanas y postes: `wall_<color>_tall_x`, `door_<color>_low_y`,
   `wall_<color>_tall_corner_left`… La sombra de la pared alta es una sola para todos.
7. **Pisos** (como los de la referencia):
   - *Madera*: tablas angostas (8 por casilla) a lo largo de un eje, junta oscura `783a13` de 1 px (en pantalla,
     la escalera 2:1 de trazos de 2 px), cortes escalonados, cada tabla de un tono con un moteado de dominós del
     tono vecino y alguna veta corta `904f25`.
   - *Losas* (cerámica): junta gris (no negra), bisel claro en los cantos de arriba y oscuro en los de abajo,
     esquinas redondeadas (el pixel de la esquina es junta), losas en damero de dos tonos casi iguales y un
     reflejo en diagonal en algunas.
   - *Alfombra*: de pared a pared, ruido de dominós en 4 lilas cercanos (`777a9a` `7d80a0` `8688a4` `8e8fa8`)
     agrupado en manchas suaves; sin juntas ni brillo. Pasto, concreto, grava, acera y calle usan el mismo
     método (receta `Noise` en `pieces/floors.py`) con sus tonos, más formas chicas encima: matas, poros y
     grieta, piedritas con cara clara y sombra; la acera lleva junta y bisel fijos y la calle con línea una
     franja amarilla de 4 celdas con pixeles gastados.
   - *Pasto*: manchas de borde nítido (sin grano suelto) más chicas que la casilla, matas de briznas con
     punta clara y pie oscuro, y mechones oscuros en ^. Para que no se vea un solo dibujo repetido hay 4
     familias (liso, manchones, tupido, claro) con el mismo borde, que el juego mezcla por zonas.

## Paleta (hex sacados de las capturas)

| Material | Contorno | Sombra (−40 %) | Lado (−25 %) | Base (arriba) | Brillo |
| --- | --- | --- | --- | --- | --- |
| Madera naranja (escritorios, mesas) | `3c1300` | `894522` / `743b0e` | `c26b24` | `df823d` | `eda85d` |
| Madera oscura (piso de tablones) | `25241f` | `5b2421` / `783a13` | `9d6035` | `ad6d40` / `a5663a` | `b67647` |
| Tapizado rojo (sillas, sofás, alfombra) | `450e22` | `6d120a` / `7c2323` | `9b323a` | `c03d43` | `bc3f41` |
| Plástico negro (silla de oficina, monitor) | `000000` | `1c1c1c` | `222020` | `313030` | `4f4f4f` |
| Metal claro / electrodoméstico | `3d3b44` | `77888c` | `97a2aa` | `d0e1e0` | `ffffff` |
| Pared fría (cara interior) | — | `899da0` | `899da0` | `96acad` | `a3b6b7` |
| Pared beige (alternativa) | — | `9e9c8d` | `afa08d` | `c2c0b2` | `efdfbd` |
| Tapa de pared y canto de losa | `21161a` | `3e2e33` | `493539` | `584549` | `675a64` |
| Puerta | `2a211b` | `5e3e29` | `8d6e4f` | `afa08d` | `efdfbd` |
| Cerámica blanca | `3e2e33` (junta) | `a4a2a1` | `bbb9b9` | `e8e8e8` | `ffffff` |
| Cerámica azul (cuadros) | `020202` | `3895ca` / `3d90c0` | `479ed1` | `6dacce` | `6eaed4` |
| Hojas | `242f12` | `425423` / `4c6029` | `648132` | `9ecc42` | `cbf166` |
| Maceta / barro | `4e1c05` | `5d3526` | `8e6d53` | `c56a33` | `e2804a` |
| Pantalla encendida | `202020` | `3d90c0` | `479ed1` | `6dacce` | `d0e1e0` |

Los colores de `data/*.json` siguen siendo los del dibujo provisional del juego; los sprites usan esta paleta. Si
un mueble no tiene material aquí, se arma su rampa con el mismo criterio: base saturada, lado −25 %, sombra −40 %,
contorno casi negro del mismo tono y brillo claro.
