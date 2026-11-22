"""Prepare dedicated RPG discharge edits from klangfabrik's CC0 recording.

Decode the source preview to 48 kHz, 16-bit PCM stereo first, then run with
Python + NumPy. Source details and hash are in assets/weapon_audio/CREDITS.md.
"""
import argparse
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]


def write_wav(path, samples, rate):
    pcm = np.rint(np.clip(samples, -1.0, 1.0) * 32767).astype('<i2')
    with wave.open(str(path), 'wb') as output:
        output.setnchannels(samples.shape[1])
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes(pcm.tobytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    args = parser.parse_args()
    with wave.open(str(args.source), 'rb') as source:
        rate = source.getframerate()
        if (rate, source.getsampwidth(), source.getnchannels()) != (48000, 2, 2):
            raise SystemExit('Decode to 48 kHz, PCM16 stereo before preparing.')
        samples = np.frombuffer(source.readframes(source.getnframes()), dtype='<i2')
        samples = samples.reshape(-1, 2).astype(np.float64) / 32768.0

    # The first launch has an unclipped attack and a full exhaust/reverberation
    # tail. Stop well before the recording's second launch at ~3.95 seconds.
    samples = samples[round(.098 * rate):round(2.498 * rate)]
    samples -= samples.mean(axis=0)
    frequencies = np.fft.rfftfreq(len(samples), 1.0 / rate)
    highpass = frequencies ** 2 / (frequencies ** 2 + 35.0 ** 2)
    # Mild low-body lift; preserve the recorded broadband rocket wash.
    body = 1.0 + .22 * np.exp(-.5 * (np.log2(np.maximum(frequencies, 1) / 140) / 1.1) ** 2)
    samples = np.fft.irfft(np.fft.rfft(samples, axis=0) * (highpass * body)[:, None], n=len(samples), axis=0)
    attack = round(.0004 * rate)
    release = round(.14 * rate)
    samples[:attack] *= np.linspace(0, 1, attack)[:, None]
    samples[-release:] *= np.linspace(1, 0, release)[:, None]
    samples *= 10 ** (-1.2 / 20) / np.max(np.abs(samples))
    write_wav(ROOT / 'assets/weapon_audio/first_person/rpg.wav', samples, rate)
    # Positional emitters need mono for reliable panning and wall occlusion.
    mono = samples.mean(axis=1, keepdims=True)
    mono *= 10 ** (-1.2 / 20) / np.max(np.abs(mono))
    write_wav(ROOT / 'assets/weapon_audio/rpg_fire.wav', mono, rate)
    print('Prepared 2.4 s RPG launch: stereo first person and mono spatial, -1.2 dBFS peak.')


if __name__ == '__main__':
    main()
