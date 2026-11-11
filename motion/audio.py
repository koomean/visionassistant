#!/usr/bin/env python3
"""LunaV: an original, six-second, softly voiced sonic identity.

No recorded or downloaded audio is used. All tones and air textures are
deterministically synthesized here with Python's standard library.
Run: python3 Motion/source/audio.py
"""

from array import array
import math
from pathlib import Path
import random
import struct
import wave

RATE = 48_000
DURATION = 6.0
COUNT = int(RATE * DURATION)
TAU = math.tau
left = array("d", [0.0]) * COUNT
right = array("d", [0.0]) * COUNT
rng = random.Random(0x4C554E41)


def smooth(v):
    v = min(1.0, max(0.0, v))
    return v * v * (3.0 - 2.0 * v)


def add(i, value, pan=0.0):
    # Equal-power panning keeps the small image centered and mono compatible.
    angle = (pan + 1.0) * math.pi / 4.0
    left[i] += value * math.cos(angle)
    right[i] += value * math.sin(angle)


def glass(start, frequency, level, decay=0.75, pan=0.0):
    for i in range(int(start * RATE), min(COUNT, int((start + 2.55) * RATE))):
        t = i / RATE - start
        onset = smooth(t / 0.018)
        body = math.sin(TAU * frequency * t) * math.exp(-t / decay)
        # Tiny near-harmonic components give a warm glass timbre, without the
        # sharp attack and loud upper partials of a metallic bell.
        second = 0.19 * math.sin(TAU * frequency * 2.001 * t + 0.05) * math.exp(-t / (decay * 0.66))
        third = 0.035 * math.sin(TAU * frequency * 3.003 * t) * math.exp(-t / (decay * 0.4))
        add(i, level * onset * (body + second + third), pan)


# The first breath: a soft D/A/E harmonic light, opening rather than dramatic.
for i in range(int(0.15 * RATE), int(2.35 * RATE)):
    t = i / RATE
    attack = smooth((t - 0.15) / 0.68)
    release = 1.0 - smooth((t - 1.05) / 1.30)
    phase = t - 0.15
    pad = (0.038 * math.sin(TAU * 146.832384 * phase)
           + 0.027 * math.sin(TAU * 220.0 * phase + 0.45)
           + 0.018 * math.sin(TAU * 329.627557 * phase + 0.82))
    add(i, attack * release * pad)

glass(0.43, 587.329536, 0.069, decay=0.63, pan=-0.18)
glass(0.83, 880.0, 0.046, decay=0.61, pan=0.18)

# Filtered air supports the reveal and the suffix's gradual dust dissolution.
# The two one-pole filters isolate a soft air band instead of white hiss.
low_fast = 0.0
low_slow = 0.0
for i in range(COUNT):
    t = i / RATE
    noise = rng.uniform(-1.0, 1.0)
    low_fast += 0.115 * (noise - low_fast)
    low_slow += 0.018 * (noise - low_slow)
    air = low_fast - low_slow
    swell = smooth((t - 0.15) / 0.56) * (1.0 - smooth((t - 0.72) / 0.48))
    dust = smooth((t - 1.48) / 0.38) * (1.0 - smooth((t - 2.30) / 0.52))
    transition = smooth((t - 2.50) / 0.30) * (1.0 - smooth((t - 2.88) / 0.35))
    amplitude = 0.036 * swell + 0.032 * dust + 0.044 * transition
    pan = -0.14 + 0.28 * smooth((t - 1.48) / 1.34)
    add(i, air * amplitude, pan)

# A nearly subliminal harmonic shimmer disperses with the dust. Its long,
# smooth envelope has no granular clicks or scratchy fineliner rhythm.
for i in range(int(1.48 * RATE), int(2.82 * RATE)):
    t = i / RATE - 1.48
    envelope = smooth(t / 0.40) * (1.0 - smooth((t - 0.74) / 0.60))
    shimmer = (0.0034 * math.sin(TAU * 1174.659072 * t + 0.13 * math.sin(TAU * 0.8 * t))
               + 0.0015 * math.sin(TAU * 1760 * t + 0.29)
               + 0.0006 * math.sin(TAU * 2349.318144 * t + 0.62))
    add(i, envelope * shimmer, 0.10 * math.sin(TAU * 0.42 * t))

# A quiet, rounded rising tone follows the suffix's dissolution into the logo.
for i in range(int(2.55 * RATE), int(3.20 * RATE)):
    t = i / RATE - 2.55
    envelope = smooth(t / 0.20) * (1.0 - smooth((t - 0.30) / 0.35))
    phase = TAU * (220 * t + 31.0 * t * t)
    add(i, 0.020 * envelope * math.sin(phase))

# The gold period lands on a soft D-major voicing. The notes bloom rather than
# click, and the stereo spacing remains deliberately narrow.
glass(3.12, 587.329536, 0.195, decay=0.86, pan=-0.10)
glass(3.19, 739.988845, 0.113, decay=0.79, pan=0.13)
glass(3.29, 880.0, 0.093, decay=0.76, pan=-0.02)
glass(3.38, 1174.659072, 0.036, decay=0.63, pan=0.10)

for i in range(int(3.10 * RATE), int(5.50 * RATE)):
    t = i / RATE - 3.10
    envelope = smooth(t / 0.24) * math.exp(-t / 0.83)
    warmth = (math.sin(TAU * 146.832384 * t)
              + 0.48 * math.sin(TAU * 220 * t + 0.2)
              + 0.28 * math.sin(TAU * 293.664768 * t + 0.4))
    add(i, 0.027 * envelope * warmth)

# Sparse, dark room reflections add a gentle tail; render from the dry buffers
# so each tap is independent and does not feed back indefinitely.
dry_left = array("d", left)
dry_right = array("d", right)
for delay, gain, cross in ((0.047, 0.10, True), (0.091, 0.071, False),
                           (0.173, 0.052, True), (0.257, 0.030, False)):
    offset = round(delay * RATE)
    for i in range(offset, COUNT):
        left[i] += gain * (dry_right[i - offset] if cross else dry_left[i - offset])
        right[i] += gain * (dry_left[i - offset] if cross else dry_right[i - offset])

# Fade fully to digital silence before the picture fades out, and leave a
# 400-ms silent handle at the tail for a clean cut in an editing timeline.
for i in range(COUNT):
    t = i / RATE
    envelope = smooth(t / 0.025) * (1.0 - smooth((t - 5.02) / 0.58))
    left[i] *= envelope
    right[i] *= envelope

raw_peak = max(max(map(abs, left)), max(map(abs, right)))
target_peak = 10 ** (-7.0 / 20)
gain = target_peak / raw_peak
output = bytearray(COUNT * 4)
squares = 0.0
peak = 0
for i in range(COUNT):
    l = round(max(-1.0, min(1.0, left[i] * gain)) * 32767)
    r = round(max(-1.0, min(1.0, right[i] * gain)) * 32767)
    struct.pack_into("<hh", output, i * 4, l, r)
    squares += l * l + r * r
    peak = max(peak, abs(l), abs(r))

path = Path(__file__).with_name("lunav-sonic-logo.wav")
with wave.open(str(path), "wb") as audio:
    audio.setnchannels(2)
    audio.setsampwidth(2)
    audio.setframerate(RATE)
    audio.writeframes(output)

rms = math.sqrt(squares / (COUNT * 2)) / 32767
print(path)
print(f"{DURATION:.3f}s | {RATE} Hz | stereo | PCM s16le")
print(f"Peak: {20 * math.log10(peak / 32767):.2f} dBFS | RMS: {20 * math.log10(rms):.2f} dBFS")
print("Original procedural synthesis; no samples or third-party recordings.")
