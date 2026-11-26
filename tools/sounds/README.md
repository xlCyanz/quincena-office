# Sonidos

Efectos y música del juego generados por síntesis con numpy, sin muestras de terceros. `make_sounds.py` escribe los WAV en
`assets/sounds/` (efectos a 44.1 kHz, música a 22.05 kHz, mono); después `Godot --headless --editor --quit` los importa.
Las pistas de música se importan en bucle (`edit/loop_mode=2` en su `.import`). Qué suena con qué y a qué volumen está en
`data/audio.json` (ver `docs/sistemas.md`, Sonido).

```
python3 tools/sounds/make_sounds.py                 # todos
python3 tools/sounds/make_sounds.py --only click,build
afplay assets/sounds/music_office.wav               # escuchar en macOS
```

- Python 3.9 del sistema (`/usr/bin/python3`) con numpy. Sin sintaxis de 3.10+.
- Un efecto nuevo: una función `sfx_<id>(rate)` en `SOUNDS` y su entrada en `data/audio.json`.
- La música se arma con `mix_wrap` y `reverb(..., wrap=True)` para que el final empalme con el principio sin corte.
