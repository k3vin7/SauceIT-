"""사무실 슬롯머신 효과음을 합성해 이 폴더에 WAV로 쓴다(임시 소리, 녹음한 것으로 바꿔도 된다).

    python3 assets/audio/slot/build_slot_sfx.py
"""
import math, os, random, struct, wave

RATE = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
random.seed(11)


def tone(freq, seconds, volume=0.5, attack=0.004, decay=6.0, shape="sine", slide=0.0):
    out = []
    phase = 0.0
    count = int(RATE * seconds)
    for index in range(count):
        t = index / RATE
        f = freq * (1.0 + slide * t / max(seconds, 1e-6))
        phase += 2.0 * math.pi * f / RATE
        value = math.sin(phase)
        if shape == "square":
            value = 0.6 if value > 0 else -0.6
        elif shape == "bell":
            value = 0.7 * value + 0.3 * math.sin(phase * 2.76)
        envelope = min(t / attack, 1.0) * math.exp(-decay * t)
        out.append(value * envelope * volume)
    return out


def noise(seconds, volume=0.4, decay=30.0):
    return [(random.random() * 2.0 - 1.0) * volume * math.exp(-decay * i / RATE)
            for i in range(int(RATE * seconds))]


def mix(length, *layers):
    out = [0.0] * int(RATE * length)
    for start, samples in layers:
        offset = int(RATE * start)
        for index, value in enumerate(samples):
            if offset + index < len(out):
                out[offset + index] += value
    return out


def save(name, samples):
    peak = max(1e-6, max(abs(v) for v in samples))
    scale = min(1.0, 0.89 / peak)
    with wave.open(os.path.join(HERE, name), "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(RATE)
        file.writeframes(b"".join(struct.pack("<h", int(v * scale * 32767)) for v in samples))


C5, E5, G5, C6, E6, G6, C7 = 523.25, 659.25, 783.99, 1046.5, 1318.5, 1567.98, 2093.0

# 칸이 한 칸 넘어가는 소리, 칸이 멈추는 소리, 레버.
save("tick.wav", mix(0.05, (0, tone(1900, 0.03, 0.35, 0.001, 120)), (0, noise(0.02, 0.2, 200))))
save("stop.wav", mix(0.22, (0, tone(150, 0.2, 0.8, 0.001, 22)), (0, noise(0.05, 0.5, 80)),
                     (0.005, tone(2400, 0.06, 0.18, 0.001, 70))))
save("lever.wav", mix(0.4, (0, noise(0.12, 0.3, 30)), (0.02, tone(240, 0.3, 0.5, 0.002, 14, slide=-0.6)),
                      (0.26, tone(120, 0.12, 0.6, 0.001, 30))))
# 꽝: 힘 빠지는 두 음.
save("lose.wav", mix(0.6, (0, tone(311, 0.25, 0.4, 0.004, 9, "square", -0.12)),
                     (0.2, tone(233, 0.4, 0.4, 0.004, 7, "square", -0.2))))
# 1.1배: 짧게 딸랑.
save("win_small.wav", mix(0.5, (0, tone(E6, 0.2, 0.45, 0.002, 14, "bell")), (0.09, tone(G6, 0.4, 0.45, 0.002, 9, "bell"))))
# 2배·4배: 올라가는 아르페지오와 동전.
coins = [(0.42 + i * 0.045, tone(random.choice([C7, G6, E6 * 2]), 0.09, 0.22, 0.001, 45, "bell")) for i in range(14)]
save("win.wav", mix(1.3, (0, tone(C6, 0.2, 0.5, 0.002, 10, "bell")), (0.1, tone(E6, 0.2, 0.5, 0.002, 10, "bell")),
                    (0.2, tone(G6, 0.25, 0.5, 0.002, 9, "bell")), (0.3, tone(C7, 0.7, 0.5, 0.002, 4, "bell")), *coins))
# 10배(황금 셋): 팡파르 + 길게 쏟아지는 동전.
fanfare = []
for step, (start, note) in enumerate([(0.0, C5), (0.14, E5), (0.28, G5), (0.42, C6), (0.62, G5), (0.76, C6), (0.94, E6)]):
    fanfare.append((start, tone(note, 0.34, 0.42, 0.003, 5, "square")))
    fanfare.append((start, tone(note * 2, 0.34, 0.3, 0.003, 6, "bell")))
fanfare.append((1.12, tone(C6, 1.4, 0.42, 0.003, 2.2, "square")))
fanfare.append((1.12, tone(E6, 1.4, 0.34, 0.003, 2.2, "bell")))
fanfare.append((1.12, tone(G6, 1.4, 0.34, 0.003, 2.2, "bell")))
rain = [(0.9 + i * 0.05, tone(random.choice([C7, G6, E6 * 2, C7 * 1.19]), 0.1, 0.18, 0.001, 40, "bell")) for i in range(40)]
save("jackpot.wav", mix(3.1, *fanfare, *rain))
print("wrote", sorted(f for f in os.listdir(HERE) if f.endswith(".wav")))
