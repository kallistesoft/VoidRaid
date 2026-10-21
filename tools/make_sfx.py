"""Synthesizes the game's sound effects into assets/sfx (no third-party audio, no licensing).

Run: python3 tools/make_sfx.py
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / "assets" / "sfx"


def sweep(f0, f1, dur, vol=0.5, decay=6.0, wave_shape="square"):
    """Pitch slide from f0 to f1 (exponential), with a decaying envelope."""
    n = int(RATE * dur)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        f = f0 * (f1 / f0) ** (t / dur)
        phase += 2 * math.pi * f / RATE
        if wave_shape == "square":
            s = 1.0 if math.sin(phase) >= 0 else -1.0
            s *= 0.6
        elif wave_shape == "saw":
            s = ((phase / math.pi) % 2) - 1
        else:
            s = math.sin(phase)
        env = min(1.0, t / 0.003) * math.exp(-decay * t)
        out.append(vol * env * s)
    return out


def noise(dur, vol=0.3, decay=30.0, seed=1, lowpass=0.0):
    rng = random.Random(seed)
    out, prev = [], 0.0
    for i in range(int(RATE * dur)):
        v = rng.uniform(-1, 1)
        prev = prev * lowpass + v * (1 - lowpass)
        out.append(vol * prev * math.exp(-decay * i / RATE))
    return out


def mix(*tracks):
    """tracks: (start_seconds, samples)"""
    length = max(int(start * RATE) + len(s) for start, s in tracks)
    buf = [0.0] * length
    for start, s in tracks:
        o = int(start * RATE)
        for i, v in enumerate(s):
            buf[o + i] += v
    return buf


def save(name, samples):
    peak = max(1e-9, max(abs(v) for v in samples))
    scale = min(1.0, 0.9 / peak)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(v * scale * 32767)) for v in samples))


OUT.mkdir(parents=True, exist_ok=True)

# Laser: quick downward chirp, kept soft since it repeats constantly.
save("shoot", sweep(1400, 500, 0.07, vol=0.3, decay=30))
# Armoured enemy hit: short metallic tick.
save("hit", mix((0, sweep(900, 700, 0.04, vol=0.3, decay=60, wave_shape="sine")), (0, noise(0.03, vol=0.15, decay=120))))
# Enemy explosion: noise burst with a falling thump.
save("explode", mix((0, noise(0.35, vol=0.5, decay=12, seed=2, lowpass=0.6)), (0, sweep(220, 50, 0.25, vol=0.4, decay=10, wave_shape="sine"))))
# Player hit: harsh descending buzz + boom.
save("playerHit", mix((0, sweep(600, 80, 0.5, vol=0.4, decay=5, wave_shape="saw")), (0, noise(0.6, vol=0.5, decay=6, seed=3, lowpass=0.75))))
# Shield absorbs a hit: glassy ping.
save("shield", mix((0, sweep(1800, 1200, 0.3, vol=0.3, decay=10, wave_shape="sine")), (0.02, sweep(2400, 1600, 0.25, vol=0.2, decay=12, wave_shape="sine"))))
# Power-up: rising arpeggio.
save("powerUp", mix(*[(i * 0.05, sweep(f, f * 1.02, 0.12, vol=0.3, decay=18)) for i, f in enumerate([523.25, 659.25, 783.99, 1046.5])]))
# Boss warning: two-tone siren.
save("warning", mix(*[(i * 0.45, sweep(f, f, 0.4, vol=0.35, decay=1.5, wave_shape="saw")) for i, f in enumerate([440, 330, 440, 330])]))
# Boss down: long rumbling explosion with a bright tail.
save("bossDown", mix((0, noise(1.6, vol=0.6, decay=2.2, seed=4, lowpass=0.8)), (0, sweep(160, 30, 1.2, vol=0.5, decay=2.5, wave_shape="sine")),
                     *[(0.5 + i * 0.08, sweep(f, f, 0.5, vol=0.15, decay=5, wave_shape="sine")) for i, f in enumerate([523.25, 659.25, 783.99, 1046.5])]))
# Level clear: bright major fanfare.
save("levelClear", mix(*[(i * 0.11, sweep(f, f, 0.4 if i < 3 else 0.9, vol=0.3, decay=4 if i < 3 else 2.5)) for i, f in enumerate([392.0, 523.25, 659.25, 783.99])]))
# Game over: slow descending minor.
save("gameOver", mix(*[(i * 0.22, sweep(f, f * 0.97, 0.6, vol=0.35, decay=3.5, wave_shape="saw")) for i, f in enumerate([392.0, 311.13, 261.63, 196.0])]))
print("written:", sorted(p.name for p in OUT.glob("*.wav")))
