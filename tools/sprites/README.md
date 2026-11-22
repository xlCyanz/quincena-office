# Generador de sprites (piloto)

Dibuja por código, pixel por pixel, los sprites isométricos de `docs/sprites_128.md`. Esa guía manda:
léela entera antes de dibujar. Esta carpeta no es parte del juego (`tools/.gdignore` hace que Godot no la importe).

- Python 3.9 del sistema (`/usr/bin/python3`) con Pillow y numpy. Sin sintaxis de 3.10+ (`match`, `X | Y` en tipos).
- Código en inglés y `snake_case`; comentarios y textos en español.
- Los PNG **no** se escriben en el repositorio: siempre a la carpeta que se pasa con `--out`.

```
python3 tools/sprites/generate.py --out DIR [--only grupo[,grupo]] [--check] [--list]
python3 tools/sprites/check.py DIR [--verbose] [--group grupo[,grupo]]   # RESULTADO: OK o la lista de fallos
python3 tools/sprites/selftest.py --out DIR         # prueba propia del motor (unos 12 s)
```

`generate.py --only decor --check` revisa **solo** los archivos de ese grupo (lo mismo `check.py DIR --group decor`), así
no se mezclan los fallos de lo que otro esté generando en la misma carpeta. `selftest.py` mide el motor (rombo, lienzos,
apoyo, escalera 2:1 de 60 cajas × 4 rotaciones, tonos exactos, giro, texturas 1:1, curvas sin huecos, empalme de
paredes), dibuja piezas de ejemplo con sus hojas `sheet_*.png` y rompe a propósito 36 cosas para comprobar que
`check.py` las detecta. Correrlo después de tocar el motor.

| Archivo | Para qué |
| --- | --- |
| `iso.py` | Motor: lienzos, proyección 2:1, volúmenes con z-buffer, acabado (contorno, brillo, sombras), guardar y manifiesto |
| `palette.py` | Rampas de 8 tonos por material y oscurecer exacto (−25 %, −40 %) |
| `pattern.py` | Patrones periódicos para pisos y texturas: juntas, tablones, vetas, tramas Bayer, manchas, reparto exacto por tono |
| `sheet.py` | Vistas para revisar: ampliar ×N, sobre fondo, sobre piso, hojas de contacto, escenas por casilla |
| `check.py` | Verificador de la sección 11 de la guía |
| `generate.py` | Corre los módulos de `pieces/` y escribe `manifest_<grupo>.json` |
| `pieces/<grupo>.py` | Las piezas. Cada módulo expone `build(out_dir) -> lista de archivos`. Los que empiezan con `_` no se corren (código compartido) |

Una pieza se corre siempre con `generate.py --only <grupo>` (así `import iso` funciona y se escribe su manifiesto).
Dos grupos pueden generar a la vez en la misma carpeta: cada uno escribe su propio manifiesto.

## Convenciones (las del juego)

- Modelo en **casillas** para `x`, `y` y en **px de sprite** para `z` (alto). `height` de `data/*.json` está en px del
  mundo: `z = iso.world_px(height)` (× 2). Una casilla mide 128×64 px de sprite.
- En pantalla `+x` va abajo-derecha (+64, +32), `+y` abajo-izquierda (−64, +32), `+z` arriba.
- **Usar múltiplos de 1/32 de casilla en `x`, `y` y enteros en `z`**: así toda arista cae en la rejilla y sale en
  escalera 2:1 exacta (1/32 de casilla = 2 px de ancho y 1 de alto). Escribirlos como fracción: `5 / 32`, no `0.16`.
  Para un detalle fino valen los múltiplos de 1/64 (la arista sigue 2:1, pero la punta de la cara de arriba puede
  quedar de 4 px en vez de 2). Una caja con otra cosa (`0.3`, `1 / 100`) queda anotada en el manifiesto y
  **`check.py` falla** («cajas en la rejilla»). Cilindros, elipsoides, `sdf` y `panel` no tienen esa regla.
- Una caja que llena la casilla (`0…1`) ocupa las columnas 0 a 127 del lienzo: sus aristas verticales de los lados
  caen 1 px fuera del rombo del piso (que va de la columna 1 a la 126). Es lo normal.
- El modelo se escribe **una vez, con rotación 0**: el frente del mueble mira a `−y` (arriba-derecha, se ve la espalda).
  El lienzo lo gira: `r1` frente a `+x` (abajo-derecha), `r2` a `+y` (abajo-izquierda), `r3` a `−x` (arriba-izquierda).
  Con rotación 1 o 3 un mueble de 2×1 cambia ancho y fondo; el apoyo es siempre la casilla de menor `x`, `y`.
- Caras del modelo: `'top'`, `iso.FRONT` (`'y0'`, −y), `iso.BACK` (`'y1'`, +y), `iso.X0`, `iso.X1`.
- Luz arriba a la izquierda. La cara que queda a la **izquierda en pantalla** (+y del mundo) sale −25 % y la de la
  **derecha** (+x) −40 %, sea cual sea la cara del modelo que caiga ahí con cada rotación: las sombras se rehacen solas.
- Decisiones del piloto: caras lisas con el color base exacto del JSON arriba, −25 % y −40 % a los lados (el corrimiento
  de tono solo en contorno, brillos y detalles); 8–16 colores por material; nada de ruido suelto de 1 px; alfa 0/255.

## Estilo

El estilo de los sprites está en `STYLE.md` (paleta y 7 rasgos tomados del paquete «Isometric Interiors»: se copia el
estilo, nunca un sprite). Las medidas siguen siendo las de `docs/sprites_128.md`. El motor lo da hecho:

- **Rampas con nombre** (`palette.py`), una por fila de la tabla de `STYLE.md`, con sus hex exactos:
  `pal.WOOD_ORANGE`, `WOOD_FLOOR`, `UPHOLSTERY_RED`, `PLASTIC_BLACK`, `METAL_LIGHT`, `WALL_COOL`, `WALL_BEIGE`,
  `WALL_CAP`, `DOOR`, `CERAMIC_WHITE`, `CERAMIC_BLUE`, `LEAVES`, `CLAY`, `SCREEN` (todas en `pal.STYLE_RAMPS`; los hex
  crudos en `pal.STYLE_TABLE`). Contorno → `OUTLINE`, la sombra más clara → `RIGHT` y la más oscura → `DEEP`, lado →
  `LEFT`, base → `BASE`, brillo → `LIGHT`; `SOFT` y `SHINE` se calculan. Una segunda base (piso de tablones) queda como
  tono propio `ramp.index("base2")`. Cambios a la tabla por la guía: un contorno negro puro (plástico, cerámica azul)
  sube a `0c0c0c`. El brillo del tapizado rojo (`bc3f41`) casi no se distingue de su base, como en la referencia: para
  un reflejo visible usar `SHINE`.
- **Caras declaradas**: los lados de la tabla no son el −25 % / −40 % calculado. Esas rampas llevan `ramp.declared =
  True`; el manifiesto anota `"declared": true` y `"faces": {top, left, right}` y `check.py` exige esos tonos en vez del
  −25 / −40, más que la luz siga arriba a la izquierda (brillo de arriba > izquierda ≥ derecha, `pal.light_order_ok`).
- **Material nuevo** (sin fila en la tabla): `pal.style_ramp(base_saturado)` da la rampa con el mismo criterio y las
  caras exactas de la guía (−25 % / −40 %, `declared = False`). `side=` / `shadow=` fijan a mano la cara izquierda /
  derecha (queda `declared`); `outline`, `deep`, `soft`, `light`, `shine` también se pueden fijar.
  `pal.style("wood_orange", declared=False)` da una fila de la tabla con las caras de la guía.
- **Acabado `'salvaje'`** (el de por defecto, `iso.DEFAULT_STYLE`): contorno de 1 px del `OUTLINE` de cada material en
  toda la silueta, **2 px** donde una cara lateral toca el piso (z ≤ `iso.GROUND_Z`); **línea oscura de 1 px** (`DEEP`
  del material) en el borde de una pieza donde tapa a otra o se apoya sobre ella (la lleva la más cercana; a igual
  profundidad, la agregada después: dibujar el mueble antes que lo que va encima); **brillo `LIGHT` de 1 px** en las
  aristas que dan a la luz (arriba contra los dos lados y la vertical del frente) y por dentro del contorno arriba a la
  izquierda; **esquinas del tablero recortadas 1 px** (las puntas izquierda y derecha de cada cara de arriba; no en un
  lienzo plano). `c.finish(style="classic")` vuelve al acabado del piloto; cada opción que se pasa cambia la del preset.
  Una pieza que no debe llevar la línea interior: `c.style_part("pieza", rim="none")`; con el contorno entero:
  `rim="full"`.

```python
import iso
import palette as pal

WOOD = pal.WOOD_ORANGE                       # caras de STYLE.md (declaradas)
SEAT = pal.style_ramp("2e86c1")              # material nuevo: −25 % / −40 % exactos


def model(c):
    for x, y in ((3 / 32, 5 / 32), (57 / 32, 5 / 32), (3 / 32, 25 / 32), (57 / 32, 25 / 32)):
        c.box(x, x + 3 / 32, y, y + 3 / 32, 0, 38, WOOD, name="leg")          # patas de 6 px
    c.box(1 / 32, 63 / 32, 3 / 32, 29 / 32, 38, 44, WOOD, name="top")       # tablero (puntas recortadas)
    c.soft_box(30 / 32, 40 / 32, 8 / 32, 18 / 32, 44, 50, 3, SEAT, name="cushion")   # encima: después


c = iso.Canvas.furniture((2, 1), 36, 0)
model(c)
iso.save(c, out_dir, "table_r0")             # finish() por defecto = 'salvaje'
# c.finish(style="classic") o c.finish(ground_outline=1, corners=False) para cambiar el preset
```

`selftest.py` dibuja `style_test_r0…r3` (escritorio con las rampas de la tabla) y la hoja `sheet_style.png`.

## palette.py

```python
OUTLINE, DEEP, RIGHT, LEFT, SOFT, BASE, LIGHT, SHINE = range(8)   # índices de una rampa, de oscuro a claro
ramp(base, outline=None, deep=None, soft=None, light=None, shine=None, name=None, shift=1.0) -> Ramp
darken(color, amount) -> (r, g, b)       # exacto, como Color.darkened de Godot
lighten(color, amount), mix(a, b, weight), adjust(color, value, saturation, hue_toward, hue_amount, tint)
darker(index, steps=1), lighter(index, steps=1)   # un paso de sombra / luz; aceptan arreglos
tones(base, factors) -> Ramp             # paleta libre para pisos: 1.0 = base, 0.9 = −10 %, 1.08 = +8 %
palette(colors) -> Ramp                  # paleta libre con los colores dados
face_colors(base) -> {'top', 'left', 'right'}
hex_to_rgb, rgb_to_hex, luminance, mean_luminance(indices, colors, mask)
style_ramp(base, side=None, shadow=None, outline=None, deep=None, soft=None, light=None, shine=None, name=None) -> Ramp
style(key, declared=True, name=None) -> Ramp   # rampa nueva de una fila de STYLE_TABLE
WOOD_ORANGE, WOOD_FLOOR, … SCREEN; STYLE_RAMPS; STYLE_TABLE
ramp.declared, ramp.faces() -> {'top', 'left', 'right'} hex; light_order_ok(ramp_o_caras)
```

| Índice | Tono | Uso |
| --- | --- | --- |
| `OUTLINE` | base × 0.40, tono corrido al frío | contorno |
| `DEEP` | base × 0.50 | rendijas, huecos, sombra sobre la cara derecha |
| `RIGHT` | base −40 % **exacto** | cara derecha |
| `LEFT` | base −25 % **exacto** | cara izquierda |
| `SOFT` | base −12 % | detalle suave sobre la cara de arriba (vetas) |
| `BASE` | base **exacto** | cara de arriba |
| `LIGHT` | aclarado, tono corrido al cálido | brillo de arista |
| `SHINE` | más claro | reflejos de metal, vidrio, pantallas |

`ramp.add(color, name=None)` suma un tono propio (índice 8, 9…) y `ramp.replace(indice, color)` cambia uno.
`darker`: SHINE→LIGHT→BASE→LEFT→RIGHT→DEEP→OUTLINE (SOFT→LEFT). `lighter`: …RIGHT→LEFT→SOFT→BASE→LIGHT→SHINE.
Crear cada rampa **una vez** (constante del módulo) y reutilizarla: el lienzo las distingue por objeto.

## iso.py: lienzos

```python
Canvas.furniture(size=(1, 1), height=22, rotation=0, canvas=None, flat=False)   # mueble (sección 6)
Canvas.tile(rotation=0)          # 128×128, apoyo (64, 96): 1×1 hasta z = 64 y muebles chicos
Canvas.on_desk(rotation=0)       # 128×128 para computadoras; dibujar desde z = iso.DESK_TOP (44)
Canvas.wall(axis='x'|'y', tall=True, joins=True)   # 72×160 o 72×64, apoyo (36, alto − 18)
Canvas.wall_item(axis)           # 64×128, apoyo (32, 112); base del objeto en z = iso.WALL_ITEM_BASE (48)
Canvas.character(rotation=0)     # 128×128, pies en (64, 112); el modelo se para en (0.5, 0.5)
Canvas.tree()                    # 128×256, apoyo (64, 224)
Canvas.custom(width, height, origin, size=(1, 1), rotation=0, kind='custom', anchor=None)
canvas_size(size, height, flat=False) -> (ancho, alto)    # fórmula y mínimos de la tabla de la guía
world_px(height), rhombus_mask(width=128, height=128), footprint_mask(width, height, size), load_json(ruta)
```

- `Canvas.furniture`: `size` y `height` son los de `data/furniture.json` (planta con rotación 0 y alto en px del
  mundo). Si el dibujo es más alto que ese `height` (hojas de una planta, respaldo de una silla), pasar el alto real:
  el lienzo crece según la guía. Lo que se salga queda marcado como recorte y `check.py` falla.
- **Muebles chicos** (`small`): se dibujan como si ocuparan la casilla entera. Hasta 64 px de sprite de alto,
  `Canvas.tile()` (128×128); el dispensador de agua y la lámpara de pie (`height` 34) van en 128×160 como dice la
  tabla de la guía: `Canvas.furniture((1, 1), 34)`.
- **Paredes**: el modelo es siempre `x` de 0 a 1 a lo largo del borde, `y` de −1/16 a +1/16 (grosor de 8 px,
  `iso.WALL_THICKNESS`), `z` hacia arriba. La cara larga que se ve es `iso.BACK`, el canto `iso.X1`. `axis='x'` es
  el borde entre (x, y) y (x+1, y), se ve «/» y su cara larga cae a la derecha (−40 %); `axis='y'` se ve «\» y cae a
  la izquierda (−25 %). Con `joins=True` el acabado se calcula con el tramo anterior y el siguiente puestos: no queda
  contorno ni brillo en la unión. Para textura continua entre tramos usar `ctx.x` (0–1 a lo largo), que es igual en
  los dos ejes. Altas: pared 120, puerta 92, ventana 120, puerta de vidrio 100; baja: `iso.WALL_LOW_HEIGHT` (20).
- **Objetos de pared**: como una pared, con el plano en `y = 0` y el objeto hacia `+y`; no usar `x < 0.1` ni `x > 0.9`.

## iso.py: volúmenes

Todos reciben coordenadas del modelo, una `Ramp`, y devuelven el id de la pieza. Parámetros comunes:
`tex`, `shade` (−1 = toda la pieza un paso más oscura), `name` (para `select`; varias piezas pueden llevar el mismo
nombre y `select` / `style_part` / `layer` las toman todas), `part` (id o nombre de otra pieza para fundirse con ella,
sin contorno ni arista entre las dos), `outline`, `shadow`.

```python
c.box(x0, x1, y0, y1, z0, z1, ramp, tex=None, shade=0, faces=None, name=None, part=None, outline=True, shadow=True, flat=True)
c.slab(x0, x1, y0, y1, z, ramp, tex=None)                       # parche plano horizontal (tapete, papel)
c.cylinder(cx, cy, radius, z0, z1, ramp, radius_top=None, tex=None, cap=True, open_top=False, bands=None)
c.ellipsoid(cx, cy, cz, rx, ry, rz, ramp, tex=None, bands=None, dither=0.0, clip_z=None)
c.sphere(cx, cy, cz, radius, ramp, **kw)                        # se ve redonda (rz = radio × iso.Z_METRIC)
c.rounded_box(x0, x1, y0, y1, z0, z1, radius, ramp, tex=None)   # aristas verticales redondas, caras exactas
c.soft_box(x0, x1, y0, y1, z0, z1, radius_px, ramp, **kw)       # todas las aristas redondas (cojines)
c.capsule((x, y, z), (x, y, z), radius_px, ramp, **kw)          # tubo de puntas redondas (brazos, tallos)
c.panel(origin, edge_a, edge_b, ramp, tex=None, index=None)     # paralelogramo inclinado (respaldos, pantallas)
c.sdf(fn, bounds, ramp, tex=None, bands=None, dither=0.0)       # forma libre por campo de distancia
c.stamp(pattern, x, y, z, ramp, hot=None, depth_bias=0.0)       # dibujo a mano (filas de índices, −1 = vacío)
```

- Radios horizontales en casillas (0.5 llena la casilla: 90 px de ancho); radios de `soft_box`, `capsule` y `rz` en px.
- `cylinder(open_top=True)` deja ver la pared de adentro (macetas, zafacones): el contenido es otro cilindro más
  angosto adentro. `radius_top` hace conos y macetas.
- Curvas: se sombrean por **bandas** (`iso.LIGHT_BANDS` por luz, `iso.CYLINDER_BANDS` por posición); `bands=` las
  cambia y `dither=0.08` pone una trama Bayer ordenada entre bandas. Sin textura ni `dither`, el acabado les quita los
  pixeles sueltos (una banda de menos de 1 px junto a un borde inclinado).
- Campos de distancia: `sdf_round_box`, `sdf_capsule`, `sdf_ellipsoid`, `sdf_torus`, `sdf_union`,
  `sdf_smooth_union(a, b, blend)`, `sdf_subtract`, `sdf_intersect`. `fn(x, y, z)` con x, y en casillas y z en px.
- Dos cajas con caras en el mismo plano: gana la que se dibuja después (sirve de calcomanía).
- **Piezas finas**: el contorno ocupa 1 px por lado. Una pata o un tirador de menos de 4 px de ancho en pantalla
  (una caja de 1/32 de casilla de lado mide 2 px) queda toda del color del contorno: darle `outline=False`, o hacerla
  de 1/16 o más.
- **Caras lisas**: en una caja, cada lado sin `shade` ni `paint()` cuenta como «cara lisa» de su rampa. La textura debe
  dejar en el tono exacto (base, −25 %, −40 %) **más de la mitad** de cada lado (`check.py` falla si no): el detalle
  va encima del tono de la cara, no en su lugar. Una pieza que a propósito no es lisa (una rejilla, una pantalla hecha
  con textura) lleva `flat=False`; lo pintado con `paint()` y las piezas con `shade` no cuentan.

### Texturas: `tex(ctx) -> índices de rampa`

`tex` es una función, o un dict por cara: `{'top': f, iso.FRONT: g, 'sides': h, 'all': k}` (en cilindros `'side'`,
`'cap'`, `'inner'`; en elipsoides, sdf y paneles `'surface'`). Devuelve un arreglo de índices de rampa (o `None`).

| Campo de `ctx` | Qué es |
| --- | --- |
| `face`, `side` | cara del modelo y lado de pantalla (`'top'`, `'left'`, `'right'`, `'curved'`) |
| `base` | índice que le toca a cada pixel sin textura (BASE, LEFT, RIGHT o la banda): partir de aquí |
| `a`, `b` | px dentro de la cara. Lateral: `a` de izquierda a derecha vista de frente desde afuera, `b` alto desde la base de la pieza. Arriba: `a` a lo largo de x, `b` a lo largo de y. Giran con el modelo |
| `w`, `h` | tamaño de la cara en esas unidades |
| `x`, `y`, `z` | punto del modelo (casillas, casillas, px) |
| `sx`, `sy` | pixel del lienzo (para tramas: `pattern.bayer(ctx.sx, ctx.sy)`) |
| `light`, `nx`, `ny`, `nz`, `t` | en curvas: n·luz, normal y posición −1…+1 a lo ancho del cilindro |

```python
def drawers(ctx):
    line = pattern.frame(ctx.a, ctx.b, 1, ctx.w - 1, 2, 13, 1)
    return np.where(line, pal.darker(ctx.base), ctx.base)
```

### Retoque y acabado

```python
c.select(part=None, face=None, side=None) -> máscara      # pixeles visibles de una pieza (id, nombre o lista) / cara / lado
c.paint(mask, index, ramp=None)                           # cambia tono (y rampa) de pixeles ya dibujados
c.style_part(part, outline=None, rim=None)                # rim: 'line', 'full', 'soft', 'left', 'none'
c.no_outline(mask); c.no_finish(mask); c.open_ends()      # quitar contorno / todo el acabado en una zona
c.edges() -> dict de máscaras                             # silhouette, upper_left, crease_left, occluded, contact…
c.finish(style=None, outline=, highlight=, crease=, occlusion=, inner_outline=, outline_index=,
         ground_outline=, corners=, line_index=) -> imagen PIL   # sin argumentos: preset iso.DEFAULT_STYLE
iso.STYLES                                                # {'salvaje': {...}, 'classic': {...}}
c.final_shade, c.final_alpha                              # índices y alfa después del acabado
c.image                                                   # la imagen terminada (finish() por defecto)
c.layer(parts=None, mask=None) -> imagen                  # capa aparte con solo esas piezas (respaldo, pelo…)
c.ground_shadow(shift=(0.10, 0.03), color=(26, 28, 38)) -> imagen     # para *_shadow.png
c.project(x, y, z) -> (px, py); c.to_world(x, y); c.to_model(u, v); c.face_side(face)
```

Búferes (arreglos del lienzo con un margen de `iso.PAD` px; `c.X`, `c.Y` dan el pixel final): `alpha`, `depth`, `part`,
`face`, `side`, `shade`, `ramp_id`, `u`, `v`, `z` (punto del mundo) y `a`, `b` (coordenadas de cara). Ejemplo:
`c.paint(c.select(part='screen', face=iso.FRONT) & (c.a > 2) & (c.a < 30) & (c.b > 2), pal.SHINE)`.

El acabado `'classic'` (el del piloto; el de por defecto ahora es `'salvaje'`, ver «Estilo») pone: contorno de 1 px en la silueta con el tono `OUTLINE` de cada material (nunca negro
puro); brillo de 1 px en la arista superior izquierda de cada cara de arriba (por dentro del contorno); un paso de luz
en la arista entre la cara de arriba y la izquierda y en la arista vertical del frente; un paso de sombra bajo los
vuelos, a la derecha de lo que sobresale y al pie de lo que está apoyado (nunca en pixeles sueltos: junto a una arista
inclinada no queda una línea punteada); un paso de sombra en el borde izquierdo de una pieza que tapa a otra y en la
arista superior derecha de una cara de arriba que tiene justo detrás otra del mismo tono (para que no se fundan).
`highlight`: `'inner'`, `'edge'`, `'upper'` o `None`. `finish()` recuerda sus opciones: si después se retoca algo,
`c.image` e `iso.save` vuelven a aplicar las mismas.

## iso.py: pisos

```python
grid = iso.tile_grid()             # 128×128 con el rombo exacto abajo; tile_grid((2, 2)) = alfombra 256×128
grid.mask, grid.x, grid.y          # rombo y pixel
grid.u, grid.v                     # coordenadas de casilla (periodo 1: lo periódico empalma solo)
grid.U, grid.V                     # «px de eje» (u × 64): una banda de 1 es una línea 2:1 de 1 px de alto
grid.iu, grid.iv, grid.domino      # rejilla isométrica: cada (iu, iv) con suma par son 2 px seguidos
grid.pixel_of(iu, iv); grid.wrap(x, y)
grid.image(indices, colores) -> imagen RGBA
```

Las 4 variantes deben compartir el **anillo del borde** (`iu` o `iv` igual a 0 o 63) y el **brillo medio**: variar solo
el interior y repartir con `pattern.exact_levels` / `pick_exact` para que cada tono tenga la misma cantidad de pixeles.
Lo que cruza el borde (una brizna, una veta, una mancha) tiene que ser **igual en las 4 variantes** o quedará cortado
cuando la vecina sea otra variante: lo propio de cada variante va con un margen (`scatter(…, margin=4)`) o se apaga
cerca del borde. Usar siempre `grid.u`, `grid.v` con periodos enteros (`value_noise`, `blobs`) y cantidades que entren
justo en 64 (4 tablones de 16, no 6 de 10).

Alfombra (2×2, 256×128, «como un piso»): `grid = iso.tile_grid((2, 2))`, pintar y guardar con
`iso.save(img, out_dir, "rug", kind="furniture", footprint=[2, 2], anchor=[128, 32], flat=True)`.

## pattern.py

```python
bayer(x, y, size=4); dither(value, x, y, levels=2, size=4); checker(x, y, size=1)
hash2(i, j, seed=0)                                  # azar fijo 0–1 por par de enteros
value_noise(u, v, period=4, seed=0); blobs(u, v, seed=0, periods=(2, 4), weights=(0.65, 0.35))   # periódicos
joints(U, V, period=64, width=2, axis='both')        # juntas centradas en el borde: 1 px por lado
bevel(U, V, period=64, joint=2, width=1) -> (claro, oscuro)
planks(U, V, count=4, axis='u', joint=1, length=64, seed=0) -> dict(index, piece, seam, cut, along, across, width)
grain(along, across, seed, density=0.45, length=16, row=3, period=None, row_period=None) -> máscara de vetas
                                                     # en pisos: row que divida a 64 (4, 8), period=64, row_period=64 / row
grain_value(along, across, seed, length=16, row=3, period=None, row_period=None) -> prioridad (para pick_exact)
scatter(count, seed, period=64, min_distance=4, margin=0) -> [(U, V)]; stamp_points(iu, iv, points, shape)
pixel_points(grid, count, seed, min_distance=4, margin=0) -> [(x, y)]; stamp_pixels(grid, points, shape)
exact_levels(value, mask, counts, group=None, tie=None) -> nivel por pixel   # cantidad EXACTA por tono
pick_exact(value, mask, count, group=None, tie=None) -> máscara
frame(a, b, a0, a1, b0, b1, width=1); rect(a, b, a0, a1, b0, b1); stripes(value, period, width)
isolated_pixels(levels, mask) -> cuántos pixeles sueltos hay
```

`group=grid.domino` reparte de a 2 px (un dominó), así no quedan pixeles sueltos.

## Guardar, manifiesto y check

```python
iso.save(sprite, out_dir, name, **meta) -> ruta    # sprite = Canvas o imagen PIL; name sin o con .png
```

Con un `Canvas` el manifiesto sale solo (tipo, lienzo, apoyo, planta, rotación, alto, recorte, caras lisas). Con una
imagen PIL (pisos, sombras) el tipo sale del nombre (`floor_*`, `ground_*`, `*_shadow`, `tree_*`, `dirt_*`) o se pasa
`kind=`; en sombras pasar también `footprint=list(c.world_size)` y `anchor=list(c.anchor)`.

`check.py DIR` revisa: nombre en `snake_case`; PNG RGBA con alfa 0/255; sin negro puro; cantidad de colores (aviso si
pasa de 16 en pisos o 32 en lo demás); lienzo según la guía; recortes (los marca el motor); cajas fuera de la rejilla
(sus aristas no saldrían 2:1); **pisos**: rombo exacto de 4,096 px, desplazar ±64/±32 sin huecos ni encimados, mismo
anillo de borde entre variantes, sin costura medible ni salto de color al cruzarla en las 16 parejas × 2 ejes, mismo
brillo medio (tolerancia 0.25 de 255) y color medio por canal (0.5), y aviso si más del 4 % son pixeles sueltos (ruido
de 1 px); **muebles**: lienzo de la tabla, apoyo, nada por debajo de la planta, la pieza se apoya en el piso, tonos
exactos base / −25 % / −40 % en las caras lisas (los pixeles que declara el manifiesto están en el PNG y la textura
deja en ese tono más de la mitad de cada lado); **paredes**: lienzo, apoyo, alto de la tabla (120 / 92 / 100 y 20),
empalme con el tramo vecino sin hueco ni línea, y que la baja tenga la misma cara de arriba que la alta. No revisa los
archivos `sheet_*`, `scene_*`, `preview_*` ni `_*`. Un fallo se arregla en la pieza, no bajando la tolerancia.

## sheet.py: mirar antes de entregar

```python
sheet.on_background(img, scale=4); sheet.on_floor(img, piso_o_variantes=None, anchor=None, scale=4)
sheet.plain_tile(base="c9b48a")                    # casilla lisa de prueba (on_floor la usa si no se pasa piso)
sheet.contact_sheet(items, columns=4, scale=3); sheet.tile_mosaic(variantes, cols=4, rows=4, seed=0, scale=3)
scene = sheet.Scene(cols, rows); scene.fill_floor(variantes, seed); scene.add(img, x, y, anchor=None, size=(1, 1))
scene.add_wall(img, x, y, axis); scene.add_wall_item(img, x, y, axis)     # el objeto, sobre la pared de ese borde
scene.add_shadow(img, x, y, anchor=None, opacity=0.3); scene.render(scale=3)
sheet.manifest(directorio) -> {archivo: datos}     # apoyo y planta de un PNG ya guardado
```

Un mueble de 2×1 o 2×2 va con su apoyo y su planta girada: `scene.add(img, x, y, anchor=c.anchor, size=c.world_size)`
(o los de `sheet.manifest`). Un personaje, con `anchor=(64, 112)`. Las paredes altas son las del fondo:
`add_wall(alta_y, i, -1, "y")` y `add_wall(alta_x, -1, i, "x")`; las bajas, `add_wall(baja_y, i, filas - 1, "y")` y
`add_wall(baja_x, columnas - 1, i, "x")`.

Guardar las vistas con nombre `sheet_*.png` y abrirlas con la herramienta Read. Mirar siempre ampliado ×3 o ×4, sobre
un piso, y corregir lo que se vea mal.

## Ejemplo completo: un mueble de 1×1

El escritorio ya no sale de este generador (se dibuja con Moana, ver `art/`); queda como ejemplo de la API.

```python
# Escritorio simple en sus 4 rotaciones.
import numpy as np

import iso
import palette as pal
import pattern

ITEM = iso.load_json("data/furniture.json")["items"]["simple_desk"]
WOOD = pal.ramp(ITEM["color"])  # 9a7048: arriba exacto, −25 % izquierda, −40 % derecha
METAL = pal.ramp("b9bcc2")
TOP = iso.world_px(ITEM["height"])  # 22 px del mundo -> z = 44
SLAB = 6  # grosor del tablero


def top_grain(ctx):
    """Veta larga a lo largo de x (ctx.a) en la cara de arriba, un tono suave más abajo."""
    veins = pattern.grain(ctx.a, ctx.b, seed=7, density=0.5, length=18, row=4)
    return np.where(veins, pal.SOFT, ctx.base)


def side_grain(ctx):
    """Veta horizontal en los costados: un paso de sombra sobre el tono de la cara."""
    veins = pattern.grain(ctx.a, ctx.b, seed=3, density=0.3, length=14, row=5)
    return np.where(veins, pal.darker(ctx.base), ctx.base)


def drawer_front(ctx):
    """Frente de la cajonera: tres cajones separados por una rendija oscura."""
    index = ctx.base
    for b0 in (2, 14, 26):
        index = np.where(pattern.frame(ctx.a, ctx.b, 1, ctx.w - 1, b0, b0 + 11, 1), pal.darker(ctx.base), index)
    return index


def model(c):
    """El modelo se escribe UNA vez con rotación 0: el frente (donde va la silla) mira a −y."""
    legs = TOP - SLAB
    # Cajonera, panel lateral del otro lado y faldón atrás.
    c.box(20 / 32, 30 / 32, 4 / 32, 26 / 32, 0, legs, WOOD, tex={iso.FRONT: drawer_front, "sides": side_grain},
          name="drawers")
    for z in (7, 19, 31):
        c.box(23 / 32, 27 / 32, 7 / 64, 4 / 32, z, z + 2, METAL, name="handle%d" % z)
    c.box(2 / 32, 4 / 32, 4 / 32, 26 / 32, 0, legs, WOOD, tex=side_grain, name="panel")
    c.box(4 / 32, 20 / 32, 24 / 32, 25 / 32, 12, legs, WOOD, shade=-1, name="skirt")
    # Tablero con vuelo de 2 px por lado.
    c.box(1 / 32, 31 / 32, 3 / 32, 27 / 32, legs, TOP, WOOD, tex={iso.TOP: top_grain, "sides": side_grain}, name="top")


def build(out_dir):
    files = []
    for rotation in range(4):
        c = iso.Canvas.furniture(ITEM["size"], ITEM["height"], rotation)
        model(c)
        files.append(iso.save(c, out_dir, "desk_simple_r%d" % rotation))
        files.append(iso.save(c.ground_shadow(), out_dir, "desk_simple_r%d_shadow" % rotation, kind="shadow",
                              footprint=list(c.world_size), anchor=list(c.anchor)))
    return files
```

```
python3 tools/sprites/generate.py --out DIR --only <grupo> --check
```

Un piso (las 4 variantes comparten juntas y bisel; solo cambian las manchas, con la misma cantidad por tono):

```python
def tile(variant):
    grid = iso.tile_grid()
    colors = pal.palette([pal.darken("b39c72", 0.28), "b39c72", pal.darken("c9b48a", 0.06), "c9b48a",
                          pal.lighten("c9b48a", 0.10)])
    joint = pattern.joints(grid.U, grid.V, 32, 2)                 # 2×2 losas, junta de 2 px
    lit, dark = pattern.bevel(grid.U, grid.V, 32, 2, 1)
    inner = grid.mask & ~joint & ~lit & ~dark
    stains = pattern.pick_exact(pattern.blobs(grid.u, grid.v, seed=40 + variant), inner, 300, group=grid.domino)
    index = np.full(grid.mask.shape, 3, dtype=np.int16)
    index[stains] = 2
    index[lit] = 4
    index[dark] = 1
    index[joint] = 0
    return grid.image(index, colors)

iso.save(tile(0), out_dir, "floor_ceramic_0", material="ceramic", variant=0, base_colors=["c9b48a", "b39c72"])
```

## Limitaciones conocidas

- `check.py` no detecta todo en los pisos: manchas de borde duro que no se repiten, o tablones que no entran justo en
  la casilla, pasan sus medidas si la casilla ya tiene juntas igual de marcadas. Mirar siempre `sheet.tile_mosaic`.
- Esquinas de pared: cada tramo es una caja de 64 px de largo sobre su borde (igual que hoy en el juego), así que en
  una esquina en L falta el cuadradito de 8×8 px de afuera y los dos cantos se cruzan. No se arregla en el sprite
  (el lienzo de 72 px no deja alargar el tramo): es una decisión de la integración (un poste de esquina o el orden).
- Un tramo de pared con `joins=True` no lleva contorno ni brillo en sus extremos aunque al lado haya una puerta más
  baja o nada; la puerta (`joins=False`) sí lleva los suyos.

- Solo las **cajas** (y las caras rectas de `rounded_box`) garantizan la escalera 2:1 y los tonos exactos. Cilindros,
  elipsoides, `soft_box`, `capsule`, `sdf` y `panel` tienen bordes curvos o inclinados y se sombrean por bandas.
- No hay cajas giradas en ángulos que no sean de 90°; lo inclinado se hace con `panel` o `sdf`.
- Dos piezas curvas distintas que se cruzan casi en el mismo plano pueden dejar un borde irregular en el cruce:
  separarlas 2 px o más, o fundirlas con `part=` / `sdf_smooth_union`. (El acabado ya quita los pixeles sueltos del
  sombreado por bandas en curvas sin textura ni `dither`.)
- `stamp` no gira con el modelo (es un dibujo de pantalla): hacer uno por rotación.
- El contorno usa 4 vecinos: en curvas cerradas queda con esquinas en «L» (2 px en la diagonal).
- La sombra del piso es la planta de las piezas corrida, sin forma exacta; es una mancha para poner con transparencia.
- El acabado de las paredes supone que el tramo vecino es igual a este; las esquinas en L se revisan a ojo en una
  escena (`Scene.add_wall`), `check.py` solo mide la unión en línea recta.
- `check.py` no puede decir si algo «se ve bien»: mide formato, geometría, tonos y costuras. Mirar siempre los PNG.
- Las alturas de pared (120, 92, 100, 20), el apoyo de pared (36, alto − 18) y el del objeto de pared (32, 112) salen
  de la tabla de la guía y de la regla «planta pegada abajo y apoyo en su centro»; la guía no los escribe uno por uno.

## Sprites dibujados aparte (`art/`)

`art/<categoría>/<pieza>/` guarda los sprites que no salen de `generate.py`: sus PNG, el documento editable de
cada uno (`.moana.json`, del motor Moana), el `build.py` que los genera y un `manifest.json` con el apoyo de
cada PNG. `export_game.py` los usa en lugar del de `generate.py` con el mismo nombre.

| Carpeta | Qué tiene |
| --- | --- |
| `art/furniture/desk_simple/` | Escritorio sencillo: `desk_simple_r0`–`_r3` y sus `_shadow` |
| `art/furniture/desk_long/` | Escritorio largo (2×1): `desk_long_r0`–`_r3` y sus `_shadow` |
| `art/furniture/executive_desk/` | Escritorio ejecutivo (2×1, nogal): `executive_desk_r0`–`_r3` y sus `_shadow` |
| `art/furniture/computer_basic/` | Computadora básica (todo en uno crema): `computer_basic_r0`–`_r3` y sus `_shadow` |
| `art/furniture/computer_pro/` | Computadora pro (pantalla plana y torre): `computer_pro_r0`–`_r3` y sus `_shadow` |
| `art/furniture/desk_long_basic/`, `desk_long_pro1/`–`pro3/` | Escritorio largo con su computadora en un solo sprite (`_desk_sets.py`): `desk_long_<conjunto>_r0`–`_r3` y sus `_shadow` |
| `art/furniture/computer_laptop/` | Laptop plateada (solo sobre el escritorio ejecutivo): `computer_laptop_r0`–`_r3` y sus `_shadow`; su modelo en `_laptop.py` |
| `art/furniture/glass_meeting_table/` | Mesa de reuniones de vidrio (2×2): `glass_meeting_table_r0`–`_r3` y sus `_shadow` |
| `art/ground/ceramic/`, `wood/`, `carpet/`, `bare/` | Pisos de adentro: `floor_ceramic_0`–`_3`, `floor_wood_*`, `floor_carpet_*` y `floor_bare_*` (concreto) |
| `art/ground/grass/` | Pasto del solar y de fuera: `ground_grass_<familia>_0`–`_3` y `ground_outside_<familia>_0`–`_3` (familias `plain`, `patchy`, `lush`, `sunny`) |
| `art/ground/path/`, `sidewalk/`, `road/` | Camino de grava, acera y calle (`ground_road_*`, `ground_road_line_x_*`, `ground_road_line_y_*`) |
| `art/ground/_ground_kit.py` | Lo común del terreno: rejilla isométrica periódica, anillo del borde compartido, documento Moana por tonos y las comprobaciones de costura y brillo |
| `art/furniture/chair_basic/`, `chair_ergonomic/` | Sillas de oficina: `<silla>_r0`–`_r3`, sus capas `_seat_r<n>` y `_back_r<n>`, `_shadow` y `_r<n>_depth.png` (profundidad para el personaje sentado, no es sprite) |
| `art/furniture/_chair_kit.py`, `_chairs.py` | Sillas: sólidos convexos (cojín redondeado, cilindros, barras) rasterizados con z-buffer, contorno, capas asiento/respaldo y profundidad; `_chairs.py` tiene base, cojín, soporte y respaldos |
| `art/furniture/plant_small_q/`, `plant_large/` | Plantas chica (mueble chico, ya a su tamaño) y grande, con `_shadow`; piezas en `_plants.py` (hoja, maceta) sobre `_chair_kit.py` |
| `art/nature/trees/` | Árboles del mapa: `tree_0`–`tree_7` y sus `_shadow` |
| `art/nature/bushes/` | Arbustos y setos (aún no los usa el juego): `bush_0`–`_5`, `hedge_cube`, `hedge_long_r0`/`_r1`, `hedge_corner_r0`–`_r3` y sus `_shadow` |
| `art/nature/_tree_kit.py` | Árboles: trazado de rayos sobre bultos de hojas, cápsulas y conos con borde rizado por ruido; luz por bulto y por copa, sombra bajo lo que tapa, contorno y documento Moana en orden de pintor (`art/_painter.py`) |
| `art/furniture/floor_lamp_q/` | Lámpara de pie (mueble chico, ya a su tamaño) y su `_shadow`, sobre `_chair_kit.py` |
| `art/furniture/aquarium/` | Pecera (2×1): `aquarium_r0`–`_r3` y sus `_shadow`, sobre `_chair_kit.py` (`PieceSpec` con planta, lienzo y giros) |
| `art/furniture/rug/` | Alfombra (2×2, plana): `rug`; el diseño se pinta por coordenadas de la planta |
| `art/_painter.py` | Documento Moana en orden de pintor (cada color tapa a los que van debajo): para piezas con mucha textura que no caben en el límite de nodos de Moana |
| `art/furniture/printer/`, `filing_cabinet/`, `backup_battery/` | Impresora, archivero y baterías de respaldo: `<pieza>_r0`–`_r3` y sus `_shadow` |
| `art/furniture/meeting_table/` | Mesa de reuniones redonda (2×2): `meeting_table` y su `_shadow` |
| `art/furniture/_boxes.py` | Muebles de cajas sobre `_chair_kit.py`: material desde una rampa, caja y caras con coordenadas en px para pintar puertas, cajones y luces |
| `art/furniture/_desk_kit.py` | Modelo común de los escritorios; cada `build.py` da planta y lienzo, y si hace falta su propio modelo y paleta |
| `art/furniture/_computer_kit.py`, `_computers.py` | Lo que va encima de un escritorio: documento de piezas sueltas, sombra de contacto y las piezas de cada computadora |

`build.py` corre con el Python de Moana, no con el del sistema (ver su cabecera).
