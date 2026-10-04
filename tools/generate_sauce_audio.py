"""Deterministic, original prototype sauce foley; no downloaded samples.
Run with Python 3 to rebuild mono PCM WAVs in assets/audio/sauce.
"""
import math
from pathlib import Path
import random
import struct
import wave

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / 'assets/audio/sauce'
OUT.mkdir(parents=True, exist_ok=True)


def clip(name, seconds, seed, loop=False, weight=1.0, bubbles=22):
    rng = random.Random(seed)
    count = int(seconds * RATE)
    samples = [0.0] * count
    low = 0.0
    slow = 0.0
    for i in range(count):
        t = i / RATE
        low += 0.24 * (rng.uniform(-1, 1) - low)
        slow += 0.07 * (low - slow)
        env = 1.0 if loop else (1 - math.exp(-t / 0.002)) * math.exp(-t / (seconds * 0.22))
        samples[i] = (low * 0.19 + slow * weight * 0.8) * env
    # Short, descending liquid resonances at irregular intervals, with a low
    # body on the accents. These are distinct from a flat white-noise hiss.
    for j in range(bubbles):
        start = rng.randrange(count) if loop else int((rng.random() ** 2) * count * 0.65)
        span = rng.uniform(0.015, 0.065) * weight
        frequency = rng.uniform(220, 1250) / weight
        phase = 0.0
        amplitude = rng.uniform(0.07, 0.21)
        for k in range(int(span * RATE)):
            t = k / RATE
            phase += math.tau * frequency * math.exp(-t / 0.032) / RATE
            env = (1 - math.exp(-t / 0.001)) * math.exp(-t / (span * 0.22))
            at = (start + k) % count if loop else start + k
            if at >= count:
                break
            samples[at] += math.sin(phase) * amplitude * env
    if not loop:
        phase = 0.0
        for i in range(count):
            t = i / RATE
            phase += math.tau * (72 / weight + 145 * math.exp(-t / 0.028)) / RATE
            samples[i] += math.sin(phase) * 0.35 * (1 - math.exp(-t / 0.002)) * math.exp(-t / 0.045 / weight)
    # Tiny tapered seams prevent clicks on loop restarts and one-shot edges.
    fade = int(RATE * 0.004)
    peak = max(abs(v) for v in samples) or 1
    gain = min(1.8, 0.82 / peak)
    data = bytearray()
    for i, value in enumerate(samples):
        taper = min(1.0, i / fade, (count - 1 - i) / fade)
        value = max(-0.95, min(0.95, value * gain * taper))
        data.extend(struct.pack('<h', round(value * 32767)))
    with wave.open(str(OUT / (name + '.wav')), 'wb') as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(data)


clip('spray_loop', 1.7, 31, loop=True, weight=0.65, bubbles=95)
clip('contact_loop', 1.7, 32, loop=True, weight=1.3, bubbles=160)
clip('start', 0.13, 33, weight=0.65, bubbles=9)
clip('end', 0.16, 34, weight=0.8, bubbles=8)
clip('contact', 0.23, 35, weight=1.2, bubbles=24)
clip('defeat', 0.42, 36, weight=1.8, bubbles=38)
for index in range(1, 4):
    clip(f'splat_{index}', 0.17 + index * 0.012, 40 + index, weight=0.9 + index * 0.1, bubbles=15)
