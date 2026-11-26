# Genera los efectos y la música del juego por síntesis (numpy), sin muestras de afuera.
# Uso: python3 tools/sounds/make_sounds.py [--out assets/sounds] [--only id,id]
# Después: Godot --headless --editor --quit para importarlos.
# Python 3.9 del sistema: sin sintaxis de 3.10+.
import argparse
import os
import wave

import numpy as np

SFX_RATE = 44100
MUSIC_RATE = 22050
PEAK = 0.89  # -1 dBFS


# --- Utilidades -----------------------------------------------------------------------------

def note(name):
    """Frecuencia de una nota como 'A4', 'C#5' o 'Bb3'."""
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    semis = names[name[0]]
    rest = name[1:]
    if rest.startswith("#"):
        semis += 1
        rest = rest[1:]
    elif rest.startswith("b"):
        semis -= 1
        rest = rest[1:]
    octave = int(rest)
    return 440.0 * 2.0 ** ((semis + (octave - 4) * 12) / 12.0)


def times(seconds, rate):
    return np.arange(int(seconds * rate)) / float(rate)


def env(n, rate, attack=0.005, decay=0.2, sustain=0.0, release=0.05, hold=0.0):
    """Envolvente ADSR de n muestras (decaimiento exponencial hasta sustain)."""
    t = np.arange(n) / float(rate)
    out = np.empty(n)
    a = t < attack
    out[a] = t[a] / max(attack, 1e-6)
    rest = ~a
    tr = t[rest] - attack
    out[rest] = sustain + (1.0 - sustain) * np.exp(-tr / max(decay, 1e-6))
    if hold > 0.0:
        end = t > attack + hold
        out[end] *= np.exp(-(t[end] - attack - hold) / max(release, 1e-6))
    # Fundido final corto para que no haga clic.
    fade = min(n, int(0.004 * rate))
    if fade > 0:
        out[-fade:] *= np.linspace(1.0, 0.0, fade)
    return out


def sine(freq, t, phase=0.0):
    return np.sin(2.0 * np.pi * freq * t + phase)


def soft_square(freq, t, harmonics=7):
    out = np.zeros_like(t)
    for k in range(1, harmonics * 2, 2):
        out += np.sin(2.0 * np.pi * freq * k * t) / k
    return out * 0.8


def saw(freq, t, harmonics=10):
    out = np.zeros_like(t)
    for k in range(1, harmonics + 1):
        out += np.sin(2.0 * np.pi * freq * k * t) / k
    return out * 0.6


def lowpass(signal, cutoff, rate):
    """Filtro de un polo, suficiente para suavizar ruido."""
    alpha = 1.0 - np.exp(-2.0 * np.pi * cutoff / rate)
    out = np.empty_like(signal)
    acc = 0.0
    for i in range(len(signal)):
        acc += alpha * (signal[i] - acc)
        out[i] = acc
    return out


def highpass(signal, cutoff, rate):
    return signal - lowpass(signal, cutoff, rate)


def noise(n, seed):
    return np.random.RandomState(seed).uniform(-1.0, 1.0, n)


def bell(freq, seconds, rate, decay=0.5, ratio=3.5, index=2.0):
    """Campana FM: brillo que se apaga antes que el tono."""
    t = times(seconds, rate)
    mod_env = np.exp(-t / (decay * 0.35))
    mod = index * mod_env * sine(freq * ratio, t)
    return np.sin(2.0 * np.pi * freq * t + mod) * env(len(t), rate, 0.002, decay)


def marimba(freq, seconds, rate, decay=0.25):
    t = times(seconds, rate)
    tone = sine(freq, t) + 0.35 * sine(freq * 4.0, t) * np.exp(-t / 0.03)
    return tone * env(len(t), rate, 0.001, decay)


def epiano(freq, seconds, rate, decay=1.2):
    """Piano eléctrico: FM suave con un golpe de púa al empezar."""
    t = times(seconds, rate)
    tine = 1.4 * np.exp(-t / 0.08) * sine(freq * 14.0, t)
    body = np.sin(2.0 * np.pi * freq * t + 0.6 * np.exp(-t / 0.5) * sine(freq, t) + tine * 0.15)
    return body * env(len(t), rate, 0.003, decay, 0.0)


def pluck(freq, seconds, rate, seed=0, damping=0.996):
    """Cuerda pulsada (Karplus-Strong)."""
    n = int(seconds * rate)
    period = max(2, int(rate / freq))
    buf = noise(period, seed) * 0.5
    out = np.empty(n)
    for i in range(n):
        j = i % period
        out[i] = buf[j]
        buf[j] = damping * 0.5 * (buf[j] + buf[(j + 1) % period])
    return out * env(n, rate, 0.001, seconds, 0.0)


def mix_at(dest, src, start, gain=1.0):
    """Suma src en dest desde la muestra start (lo que se pasa se recorta)."""
    if start >= len(dest):
        return
    end = min(len(dest), start + len(src))
    dest[start:end] += src[:end - start] * gain


def mix_wrap(dest, src, start, gain=1.0):
    """Como mix_at pero lo que se pasa del final vuelve al principio (bucles sin corte)."""
    n = len(dest)
    for offset in range(0, len(src), n):
        chunk = src[offset:offset + n]
        pos = (start + offset) % n
        first = min(len(chunk), n - pos)
        dest[pos:pos + first] += chunk[:first] * gain
        if first < len(chunk):
            dest[:len(chunk) - first] += chunk[first:] * gain


def reverb(signal, rate, wet=0.2, room=0.6, wrap=False):
    """Eco corto de varias líneas de retardo; con wrap la cola vuelve al principio."""
    delays = [0.0297, 0.0371, 0.0411, 0.0437, 0.053, 0.067]
    tail = int(rate * 1.2)
    out = np.concatenate([signal, np.zeros(tail)]) if not wrap else signal.copy()
    total = np.zeros_like(out)
    for k, d in enumerate(delays):
        step = int(d * rate)
        gain = room ** (k * 0.5 + 1.0)
        echo = np.zeros_like(out)
        src = out.copy()
        shift = step
        g = gain
        while shift < len(out) and g > 0.01:
            if wrap:
                echo += np.roll(src, shift) * g
            else:
                echo[shift:] += src[:len(out) - shift] * g
            shift += step * 3
            g *= room
        total += echo
    total = lowpass(total, 4000.0, rate)
    result = out + total * wet / len(delays) * 2.0
    if not wrap:
        # Recorta el silencio del final.
        level = np.abs(result)
        last = np.nonzero(level > 1e-4)[0]
        result = result[:last[-1] + 1] if len(last) else result
    return result


def normalize(signal, peak=PEAK):
    top = np.max(np.abs(signal))
    return signal if top == 0 else signal * (peak / top)


def write_wav(path, signal, rate):
    data = np.clip(signal, -1.0, 1.0)
    pcm = (data * 32767.0).astype("<i2")
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(rate)
        out.writeframes(pcm.tobytes())


# --- Efectos ---------------------------------------------------------------------------------

def sfx_click(rate):
    t = times(0.05, rate)
    tick = sine(2100.0, t) * env(len(t), rate, 0.0005, 0.012)
    body = sine(900.0, t) * env(len(t), rate, 0.0005, 0.02) * 0.5
    return tick + body


def sfx_build(rate):
    # Golpe de madera: tono que cae y un poco de ruido.
    t = times(0.22, rate)
    freq = 190.0 * np.exp(-t / 0.08) + 90.0
    phase = 2.0 * np.pi * np.cumsum(freq) / rate
    thump = np.sin(phase) * env(len(t), rate, 0.001, 0.06)
    knock = lowpass(noise(len(t), 3), 2500.0, rate) * env(len(t), rate, 0.0005, 0.015) * 0.8
    wood = sine(620.0, t) * env(len(t), rate, 0.0005, 0.03) * 0.3
    return reverb(thump + knock + wood, rate, 0.15, 0.4)


def sfx_sell(rate):
    out = np.zeros(int(0.4 * rate))
    mix_at(out, bell(note("E6"), 0.3, rate, 0.12, 2.0, 1.2), 0, 0.7)
    mix_at(out, bell(note("B6"), 0.35, rate, 0.18, 2.0, 1.2), int(0.07 * rate), 0.7)
    return reverb(out, rate, 0.2, 0.5)


def sfx_error(rate):
    out = np.zeros(int(0.32 * rate))
    for k, name in enumerate(["E3", "C3"]):
        t = times(0.14, rate)
        tone = soft_square(note(name), t, 4) * env(len(t), rate, 0.004, 0.08, 0.2, 0.05, 0.06)
        mix_at(out, lowpass(tone, 1800.0, rate), int(k * 0.13 * rate), 0.6)
    return out


def sfx_notice(rate):
    out = np.zeros(int(0.35 * rate))
    mix_at(out, marimba(note("E5"), 0.25, rate, 0.12), 0)
    mix_at(out, marimba(note("A5"), 0.3, rate, 0.15), int(0.08 * rate))
    return reverb(out, rate, 0.25, 0.5)


def sfx_hire(rate):
    out = np.zeros(int(0.6 * rate))
    for k, name in enumerate(["C5", "E5", "G5", "C6"]):
        mix_at(out, marimba(note(name), 0.4, rate, 0.2), int(k * 0.075 * rate), 0.8)
    return reverb(out, rate, 0.3, 0.55)


def sfx_contract(rate):
    out = np.zeros(int(0.8 * rate))
    mix_at(out, bell(note("G5"), 0.6, rate, 0.35), 0, 0.6)
    mix_at(out, bell(note("D6"), 0.7, rate, 0.45), int(0.11 * rate), 0.6)
    return reverb(out, rate, 0.3, 0.6)


def sfx_cash(rate):
    # Caja registradora: el mecanismo y luego la campanilla.
    out = np.zeros(int(0.9 * rate))
    mech = highpass(noise(int(0.06 * rate), 7), 1500.0, rate) * env(int(0.06 * rate), rate, 0.001, 0.015)
    mix_at(out, mech, 0, 0.5)
    mix_at(out, mech, int(0.05 * rate), 0.4)
    for k, name in enumerate(["C7", "E7"]):
        mix_at(out, bell(note(name), 0.6, rate, 0.3, 1.41, 1.5), int((0.1 + k * 0.01) * rate), 0.35)
    for k, name in enumerate(["G5", "C6", "E6"]):
        mix_at(out, marimba(note(name), 0.35, rate, 0.18), int((0.12 + k * 0.06) * rate), 0.5)
    return reverb(out, rate, 0.25, 0.5)


def sfx_success(rate):
    out = np.zeros(int(1.3 * rate))
    for k, name in enumerate(["C5", "E5", "G5"]):
        mix_at(out, epiano(note(name), 0.5, rate, 0.3), int(k * 0.09 * rate), 0.5)
    for name in ["C5", "E5", "G5", "C6"]:
        mix_at(out, epiano(note(name), 1.0, rate, 0.6), int(0.3 * rate), 0.35)
    mix_at(out, bell(note("C7"), 0.7, rate, 0.35, 2.0, 1.0), int(0.3 * rate), 0.15)
    return reverb(out, rate, 0.35, 0.6)


def sfx_objective(rate):
    out = np.zeros(int(1.4 * rate))
    seq = ["G4", "C5", "E5", "G5", "C6"]
    for k, name in enumerate(seq):
        mix_at(out, bell(note(name), 0.6, rate, 0.25, 2.0, 1.4), int(k * 0.07 * rate), 0.45)
    for k in range(6):
        sparkle = bell(note("C7") * (1.0 + 0.12 * (k % 3)), 0.2, rate, 0.08, 3.0, 1.0)
        mix_at(out, sparkle, int((0.35 + k * 0.05) * rate), 0.12)
    return reverb(out, rate, 0.35, 0.6)


def _brass(freq, seconds, rate):
    t = times(seconds, rate)
    vibrato = 1.0 + 0.004 * np.sin(2.0 * np.pi * 5.0 * t) * np.clip(t / 0.3, 0.0, 1.0)
    phase = 2.0 * np.pi * np.cumsum(freq * vibrato) / rate
    tone = np.zeros_like(t)
    for k in range(1, 9):
        tone += np.sin(phase * k) / (k ** 1.3)
    tone = lowpass(tone, 2600.0, rate)
    return tone * env(len(t), rate, 0.03, 0.4, 0.6, 0.12, seconds - 0.15)


def sfx_fanfare(rate):
    out = np.zeros(int(2.4 * rate))
    hits = [(0.0, 0.16, ["G4", "D5"]), (0.18, 0.16, ["G4", "D5"]), (0.36, 0.16, ["G4", "D5"]),
            (0.56, 1.4, ["C4", "G4", "C5", "E5"])]
    for start, length, notes in hits:
        for name in notes:
            mix_at(out, _brass(note(name), length, rate), int(start * rate), 0.3)
    hit = lowpass(noise(int(0.6 * rate), 11), 6000.0, rate) * env(int(0.6 * rate), rate, 0.001, 0.25)
    mix_at(out, hit, int(0.56 * rate), 0.15)
    mix_at(out, bell(note("C7"), 1.2, rate, 0.6, 2.0, 1.0), int(0.56 * rate), 0.12)
    return reverb(out, rate, 0.4, 0.65)


def sfx_event(rate):
    out = np.zeros(int(0.9 * rate))
    for k, name in enumerate(["A5", "E5", "A5"]):
        mix_at(out, bell(note(name), 0.4, rate, 0.2, 1.0, 1.5), int(k * 0.15 * rate), 0.5)
    return reverb(out, rate, 0.3, 0.55)


def sfx_alarm(rate):
    out = np.zeros(int(0.9 * rate))
    for k in range(2):
        for j, name in enumerate(["F5", "D5"]):
            t = times(0.16, rate)
            tone = lowpass(soft_square(note(name), t, 5), 3000.0, rate)
            tone *= env(len(t), rate, 0.005, 0.1, 0.3, 0.04, 0.1)
            mix_at(out, tone, int((k * 0.38 + j * 0.17) * rate), 0.4)
    return reverb(out, rate, 0.2, 0.4)


def sfx_game_over(rate):
    out = np.zeros(int(2.4 * rate))
    for k, name in enumerate(["G4", "F#4", "F4", "E4"]):
        length = 0.4 if k < 3 else 1.6
        mix_at(out, _brass(note(name), length, rate), int(k * 0.42 * rate), 0.4)
        mix_at(out, _brass(note(name) / 2.0, length, rate), int(k * 0.42 * rate), 0.25)
    return reverb(out, rate, 0.4, 0.6)


# --- Música ----------------------------------------------------------------------------------

def _kick(rate):
    t = times(0.3, rate)
    freq = 120.0 * np.exp(-t / 0.04) + 45.0
    return np.sin(2.0 * np.pi * np.cumsum(freq) / rate) * env(len(t), rate, 0.002, 0.12)


def _hat(rate, seed, length=0.05):
    n = int(length * rate)
    return highpass(noise(n, seed), 5000.0, rate) * env(n, rate, 0.001, length * 0.3)


def _rim(rate, seed):
    n = int(0.12 * rate)
    t = times(0.12, rate)
    tone = sine(1700.0, t) * env(n, rate, 0.001, 0.012) * 0.6
    snap = lowpass(highpass(noise(n, seed), 1200.0, rate), 6000.0, rate) * env(n, rate, 0.001, 0.04)
    return tone + snap


def _chord_notes(root, kind):
    shapes = {"maj7": [0, 4, 7, 11], "m7": [0, 3, 7, 10], "7": [0, 4, 7, 10], "m9": [0, 3, 7, 10, 14],
              "maj9": [0, 4, 7, 11, 14], "6": [0, 4, 7, 9]}
    base = note(root)
    return [base * 2.0 ** (s / 12.0) for s in shapes[kind]]


def _lofi_wobble(signal, rate, depth=0.0025, speed=0.4):
    """Leve vaivén de tono, como una cinta: se aplica con un remuestreo."""
    n = len(signal)
    t = np.arange(n) / float(rate)
    drift = np.cumsum(1.0 + depth * np.sin(2.0 * np.pi * speed * t))
    drift *= (n - 1) / drift[-1]
    return np.interp(drift, np.arange(n), signal)


def music_office(rate):
    """Bucle relajado de oficina: piano eléctrico, bajo, batería suave y marimba."""
    bpm = 88.0
    beat = 60.0 / bpm
    bars = 16
    total = int(bars * 4 * beat * rate)
    out = np.zeros(total)
    progression = [("F3", "maj7", "F2"), ("E3", "m7", "E2"), ("D3", "m7", "D2"), ("C3", "maj7", "C2"),
                   ("Bb2", "maj7", "Bb1"), ("A2", "m7", "A1"), ("D3", "m9", "D2"), ("G2", "7", "G1")]
    rng = np.random.RandomState(42)
    scale = ["C5", "D5", "E5", "G5", "A5", "C6", "D6"]
    for bar in range(bars):
        root, kind, bass = progression[bar % len(progression)]
        bar_start = bar * 4 * beat
        # Acordes en el 1 y a contratiempo del 3.
        for hit, length in [(0.0, 1.6), (2.5, 1.2)]:
            for k, freq in enumerate(_chord_notes(root, kind)):
                start = int((bar_start + hit * beat + k * 0.012) * rate)
                mix_wrap(out, epiano(freq, length * beat + 0.4, rate, 0.9), start, 0.09)
        # Bajo: raíz en 1, quinta antes del 3, raíz en 3.
        bass_f = note(bass)
        for hit, freq, length in [(0.0, bass_f, 1.4), (1.5, bass_f * 1.5, 0.45), (2.0, bass_f, 1.8)]:
            t = times(length * beat, rate)
            tone = (sine(freq, t) + 0.25 * sine(freq * 2.0, t)) * env(len(t), rate, 0.008, 0.6, 0.3, 0.08,
                                                                        length * beat - 0.1)
            mix_wrap(out, tone, int((bar_start + hit * beat) * rate), 0.32)
        # Batería: bombo en 1 y el «y» del 2, aro en 2 y 4, platillo en corcheas con swing.
        if bar >= 1:
            for hit in [0.0, 1.5, 2.75] if bar % 4 == 3 else [0.0, 1.5]:
                mix_wrap(out, _kick(rate), int((bar_start + hit * beat) * rate), 0.35)
            for hit in [1.0, 3.0]:
                mix_wrap(out, _rim(rate, bar * 7 + int(hit)), int((bar_start + hit * beat) * rate), 0.13)
            for eighth in range(8):
                swing = 0.08 if eighth % 2 else 0.0
                at = bar_start + (eighth * 0.5 + swing) * beat
                gain = 0.05 if eighth % 2 else 0.08
                mix_wrap(out, _hat(rate, bar * 31 + eighth), int(at * rate), gain)
        # Melodía de marimba en la segunda mitad, a frases de dos compases.
        if bar >= 8 and bar % 2 == 0:
            spots = sorted(rng.choice([0.0, 0.5, 1.0, 1.5, 2.5, 3.0, 4.5, 5.0, 6.0], 5, replace=False))
            for spot in spots:
                freq = note(scale[rng.randint(len(scale))])
                mix_wrap(out, marimba(freq, 0.6, rate, 0.3), int((bar_start + spot * beat) * rate), 0.12)
    out = reverb(out, rate, 0.35, 0.55, wrap=True)
    out = _lofi_wobble(out, rate)
    hiss = lowpass(noise(total, 5), 3000.0, rate) * 0.006
    return normalize(out + hiss, 0.7)


def music_menu(rate):
    """Bucle del menú: más lento, pads y piano."""
    bpm = 72.0
    beat = 60.0 / bpm
    bars = 8
    total = int(bars * 4 * beat * rate)
    out = np.zeros(total)
    progression = [("C3", "maj9", "C2"), ("A2", "m7", "A1"), ("F2", "maj9", "F1"), ("G2", "6", "G1")]
    melody = [("E5", 0.0), ("G5", 1.5), ("D5", 3.0), ("C5", 4.0), ("A4", 5.5), ("C5", 7.0),
              ("A5", 8.0), ("G5", 9.5), ("E5", 11.0), ("D5", 12.0), ("E5", 13.5), ("G4", 15.0)]
    for bar in range(bars):
        root, kind, bass = progression[bar % len(progression)]
        bar_start = bar * 4 * beat
        for k, freq in enumerate(_chord_notes(root, kind)):
            t = times(4 * beat + 0.6, rate)
            pad = (sine(freq, t) + 0.3 * sine(freq * 2.003, t) + 0.15 * sine(freq * 0.998 * 3.0, t))
            pad *= env(len(t), rate, 0.6, 10.0, 0.8, 0.5, 4 * beat - 0.6)
            mix_wrap(out, pad, int(bar_start * rate), 0.045)
        for k, freq in enumerate(_chord_notes(root, kind)[:4]):
            mix_wrap(out, epiano(freq * 2.0, 1.5, rate, 0.8), int((bar_start + k * 0.33 * beat) * rate), 0.06)
        t = times(4 * beat, rate)
        tone = sine(note(bass), t) * env(len(t), rate, 0.02, 1.5, 0.5, 0.3, 4 * beat - 0.3)
        mix_wrap(out, tone, int(bar_start * rate), 0.25)
    for half in range(2):
        for name, at in melody:
            start = int((half * 16 + at) * beat * rate)
            mix_wrap(out, epiano(note(name), 1.6, rate, 0.9), start, 0.16)
            mix_wrap(out, bell(note(name) * 2.0, 0.8, rate, 0.4, 2.0, 0.8), start, 0.03)
    out = reverb(out, rate, 0.5, 0.7, wrap=True)
    out = _lofi_wobble(out, rate, 0.002, 0.3)
    hiss = lowpass(noise(total, 9), 3000.0, rate) * 0.005
    return normalize(out + hiss, 0.7)


SOUNDS = {
    "click": sfx_click, "build": sfx_build, "sell": sfx_sell, "error": sfx_error, "notice": sfx_notice,
    "hire": sfx_hire, "contract": sfx_contract, "cash": sfx_cash, "success": sfx_success,
    "objective": sfx_objective, "fanfare": sfx_fanfare, "event": sfx_event, "alarm": sfx_alarm,
    "game_over": sfx_game_over,
}
MUSIC = {"music_office": music_office, "music_menu": music_menu}


def main():
    parser = argparse.ArgumentParser(description="Genera los sonidos de Quincena Office.")
    root = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
    parser.add_argument("--out", default=os.path.join(root, "assets", "sounds"))
    parser.add_argument("--only", default="")
    args = parser.parse_args()
    only = set(filter(None, args.only.split(",")))
    os.makedirs(args.out, exist_ok=True)
    for name, make in list(SOUNDS.items()) + list(MUSIC.items()):
        if only and name not in only:
            continue
        rate = MUSIC_RATE if name in MUSIC else SFX_RATE
        signal = make(rate)
        if name in SOUNDS:
            signal = normalize(signal)
        path = os.path.join(args.out, name + ".wav")
        write_wav(path, signal, rate)
        print("%-14s %5.2f s  %s" % (name, len(signal) / float(rate), os.path.relpath(path, root)))


if __name__ == "__main__":
    main()
