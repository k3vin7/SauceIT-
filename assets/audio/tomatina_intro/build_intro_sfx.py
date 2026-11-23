"""Render the intro's original crowd, hose, engine, monster and tail-gate sounds."""
from array import array
from math import exp, pi, sin
from os.path import dirname, join
from random import Random
import wave

RATE = 24000
TAU = 2 * pi
OUT = dirname(__file__)


def noise(seed, length):
    rng = Random(seed)
    return [rng.uniform(-1, 1) for _ in range(round(length * RATE))]


def low_pass(values, alpha):
    state = 0.0
    result = []
    for value in values:
        state += (value - state) * alpha
        result.append(state)
    return result


def save(name, samples):
    frames = array("h", [round(max(-1, min(1, s)) * 32767) for s in samples])
    with wave.open(join(OUT, name + ".wav"), "wb") as out:
        out.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        out.writeframes(frames.tobytes())


def strike(t, at, length):
    age = t - at
    return 0.0 if age < 0 else min(age * 190, 1.0) * exp(-age / length)


length = 4
air = noise(24, length)
murmur = low_pass(air, .10)
voices = Random(77)
phrases = [(voices.uniform(125, 356), voices.uniform(.7, 2.5), voices.uniform(0, TAU),
            voices.uniform(0, TAU)) for _ in range(19)]
save("crowd", [
    .29 * murmur[i] + sum(
        (.5 + .5 * sin(TAU * int(rate*length) * t/length + offset)) ** 4 *
        (.62 * sin(TAU * int(pitch*length) * t/length + phase + 2.3*sin(TAU*t + offset)) +
         .27 * sin(2 * TAU * int(pitch*length) * t/length + phase)) * .054
        for pitch, rate, offset, phase in phrases)
    for i in range(len(air)) for t in [i/RATE]
])

air = noise(341, 2)
body = low_pass(air, .17)
save("hose", [(a-b)*.14+b*.38 for a, b in zip(air, body)])

air = low_pass(noise(12, 2), .048)
save("bongo_engine", [
    (.31*sin(TAU*46*t) + .18*sin(TAU*92*t) + .08*sin(TAU*138*t)) *
    (.72+.28*sin(TAU*23*t)) + .27*a
    for i,a in enumerate(air) for t in [i/RATE]
])

air = noise(197, .72)
body = low_pass(air, .091)
save("bongo_latch", [
    strike(t,.015,.032)*(.33*a+.38*b+.30*sin(TAU*420*t))
    + strike(t,.109,.051)*(.28*a+.32*b+.21*sin(TAU*978*t)+.13*sin(TAU*1411*t))
    + strike(t,.30,.10)*(.39*b+.35*sin(TAU*92*t)+.11*sin(TAU*168*t))
    + strike(t,.352,.036)*(.22*a+.18*sin(TAU*290*t))
    for i,(a,b) in enumerate(zip(air, body)) for t in [i/RATE]
])

air = low_pass(noise(554, 1.16), .11)
save("tomato_growl", [
    strike(t,0,.47) * (.34*sin(TAU*(98*t-30*t*t)+1.6*sin(TAU*21*t)) +
       .26*sin(TAU*(157*t-54*t*t)) + .64*a) + strike(t,.56,.03)*.52*a
    for i,a in enumerate(air) for t in [i/RATE]
])

# Two close breaths, staggered footfalls and a low pulse for the escape shot.
length = 4.4
raw = noise(828, length)
rumble = low_pass(raw, .027)
breath = low_pass(raw, .19)
pulses = (.03, .18, .72, .85, 1.36, 1.46, 1.91, 2.04, 2.43, 2.55,
          2.87, 2.99, 3.31, 3.42, 3.72, 3.85)
steps = (1.21, 1.45, 1.76, 2.02, 2.28, 2.51, 2.73, 2.98, 3.23, 3.55, 3.88)
save("panic_breath", [
    (.27*sin(TAU*49*t) + .13*sin(TAU*63*t) + .51*rumble[i]) *
       sum(strike(t, when, .092) for when in pulses)
    + (.7*breath[i]+.12*raw[i]) * sum(strike(t, when, .044) for when in steps)
    + (.58*breath[i] + .067*sin(TAU*(197*t - 6*t*t))) *
      (strike(t, 1.33, .23) + strike(t, 2.26, .15) + strike(t, 3.12, .29))
    for i in range(len(raw)) for t in [i/RATE]
])
