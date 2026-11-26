# Genera el logo de Quincena Office (el edificio isométrico en pixel art de 32×32) y lo que sale de él:
# icono del proyecto y de macOS, .ico de Windows, logo del menú y pantalla de arranque.
# Uso: python3 tools/logo/make_logo.py
# Después: Godot --headless --editor --quit para importarlos.
# Python 3.9 del sistema: sin sintaxis de 3.10+.
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
N = 32

# Colores de scripts/ui/ui_theme.gd.
BG = "#1b1d2a"
CARD = "#262a3b"
TEXT = "#f3efe6"
ACCENT = "#f2a541"
COLORS = {
    "ol": "#0f1018",   # contorno
    "hi": "#d9d4e6",   # techo
    "mid": "#6e6a80",  # cara izquierda
    "lo": "#3a4058",   # cara derecha
    "top": ACCENT,     # borde del techo
    "wd": "#2a2e40",   # ventana apagada (cara izquierda)
    "wl": "#6fa3ef",   # ventana con reflejo (cara derecha)
    "acc": ACCENT,     # ventana encendida
}


def _put(grid, x, y, role):
    if 0 <= x < N and 0 <= y < N:
        grid[y][x] = role


def _outline(grid):
    # Contorno por fuera: cada casilla vacía que toca la figura.
    add = []
    for y in range(N):
        for x in range(N):
            if grid[y][x] is not None:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < N and 0 <= ny < N and grid[ny][nx] not in (None, "ol"):
                    add.append((x, y))
                    break
    for x, y in add:
        grid[y][x] = "ol"


ROOF_TOP = 2
ROOF_ROWS = 14
WALL_HEIGHT = 12
# Ventanas: pares de columnas de cada cara (un par comparte el mismo escalón 2:1), filas desde lo alto del muro.
WINDOW_COLUMNS = {"mid": (4, 8, 12), "lo": (18, 22, 26)}
WINDOW_ROWS = (2, 7)
LIT = {("mid", 8, 2), ("lo", 22, 7)}


def _half_width(row):
    return 2 * row + 2 if row < ROOF_ROWS // 2 else 2 * (ROOF_ROWS - 1 - row) + 2


def building():
    """Cuadrícula de 32×32 con el rol de color de cada píxel (None = transparente)."""
    g = [[None] * N for _ in range(N)]
    roof_bottom = {}
    # Techo: rombo 2:1 (dos columnas por fila), como las casillas del juego.
    for row in range(ROOF_ROWS):
        hw = _half_width(row)
        for x in range(16 - hw, 16 + hw):
            _put(g, x, ROOF_TOP + row, "hi")
            roof_bottom[x] = ROOF_TOP + row
    # Muros debajo del borde delantero del techo; el borde queda en ámbar.
    for x, bottom in roof_bottom.items():
        face = "mid" if x < 16 else "lo"
        _put(g, x, bottom, "top")
        for y in range(bottom + 1, bottom + 1 + WALL_HEIGHT):
            _put(g, x, y, face)
    for face, columns in WINDOW_COLUMNS.items():
        for x0 in columns:
            for row in WINDOW_ROWS:
                role = "acc" if (face, x0, row) in LIT else ("wd" if face == "mid" else "wl")
                for x in (x0, x0 + 1):
                    for k in range(3):
                        _put(g, x, roof_bottom[x0] + 1 + row + k, role)
    _outline(g)
    return g


def logo_image(scale):
    grid = building()
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    for y in range(N):
        for x in range(N):
            if grid[y][x] is not None:
                img.putpixel((x, y), Image.new("RGB", (1, 1), COLORS[grid[y][x]]).getpixel((0, 0)) + (255,))
    return img.resize((N * scale, N * scale), Image.NEAREST)


def app_icon(size=1024):
    """Baldosa redondeada con el edificio, para el icono de la app."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    margin = size // 10
    ImageDraw.Draw(img).rounded_rectangle([margin, margin, size - margin - 1, size - margin - 1],
                                          radius=size // 5, fill=CARD)
    art = logo_image((size - 2 * margin) * 3 // 4 // N)
    img.alpha_composite(art, ((size - art.width) // 2, (size - art.height) // 2))
    return img


def ico_images():
    """Tamaños del .ico: baldosa desde 64 px; abajo, el edificio solo para que no se emborrone."""
    images = []
    for size in (256, 128, 64):
        images.append(app_icon(size))
    native = logo_image(1)
    for size in (48, 32):
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        canvas.alpha_composite(native, ((size - N) // 2, (size - N) // 2))
        images.append(canvas)
    images.append(native.resize((16, 16), Image.LANCZOS))
    return images


def _font(name, size, weight):
    font = ImageFont.truetype(os.path.join(ROOT, "assets", "fonts", name), size)
    font.set_variation_by_axes([weight])
    return font


def splash(width=1280, height=720):
    """Pantalla de arranque: edificio y nombre, centrados sobre el fondo del juego."""
    img = Image.new("RGBA", (width, height), BG)
    art = logo_image(6)
    title = _font("pixelify_sans.ttf", 72, 700)
    sub = _font("nunito.ttf", 24, 800)
    draw = ImageDraw.Draw(img)
    title_box = draw.textbbox((0, 0), "QUINCENA", font=title)
    sub_text = "O F F I C E"
    sub_box = draw.textbbox((0, 0), sub_text, font=sub)
    gap = 28
    total = art.height + gap + (title_box[3] - title_box[1]) + 18 + (sub_box[3] - sub_box[1])
    top = (height - total) // 2
    img.alpha_composite(art, ((width - art.width) // 2, top))
    y = top + art.height + gap
    draw.text(((width - (title_box[2] - title_box[0])) // 2 - title_box[0], y - title_box[1]), "QUINCENA", font=title, fill=TEXT)
    y += title_box[3] - title_box[1] + 18
    draw.text(((width - (sub_box[2] - sub_box[0])) // 2 - sub_box[0], y - sub_box[1]), sub_text, font=sub, fill=ACCENT)
    return img


def main():
    ui = os.path.join(ROOT, "assets", "ui")
    logo_image(1).save(os.path.join(ui, "logo.png"))
    icon = app_icon()
    icon.save(os.path.join(ROOT, "icon.png"))
    images = ico_images()
    images[0].save(os.path.join(ui, "app_icon.ico"), sizes=[im.size for im in images], append_images=images[1:])
    splash().save(os.path.join(ui, "boot_splash.png"))
    print("Logo: icon.png, assets/ui/logo.png, assets/ui/app_icon.ico, assets/ui/boot_splash.png")


if __name__ == "__main__":
    main()
