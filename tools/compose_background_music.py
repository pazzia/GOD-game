"""Compose/render the 0.4 quiet chamber soundtrack with MIT FluidR3 instruments.

Requires numpy, FFmpeg and libfluidsynth.so.3. No audio device is opened. The
SoundFont is an authoring dependency outside the repository, never an APK asset.
Regeneration: python3 tools/compose_background_music.py --soundfont /path/FluidR3_GM.sf2
Without --soundfont, the pinned official Debian package is checked and extracted
to ../GOD-music-tools. Score events, MIDI, licence and hashes remain in Git.
"""
from pathlib import Path
import argparse
import ctypes as C
import ctypes.util
import hashlib
import json
import shutil
import struct
import subprocess
import tempfile
import urllib.request
import wave

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/audio"
OUT = ROOT / "assets/audio/production"
SR = 48000
PACKAGE_URL = "https://deb.debian.org/debian/pool/main/f/fluid-soundfont/fluid-soundfont-gm_3.1-5.3_all.deb"
PACKAGE_SHA256 = "6f531493ac4e4d9772fd96b2488ea1790af81c196135fbdd25997da0781fc60e"
SOUNDFONT_SHA256 = "74594e8f4250680adf590507a306655a299935343583256f3b722c48a1bc1cb0"
# GM programs are zero-based. Keep melodic instruments in a comfortable register.
PROGRAMS = {0: 0, 1: 24, 2: 48, 3: 4, 4: 11, 5: 71}
INSTRUMENTS = {0: "soft acoustic piano", 1: "nylon guitar", 2: "warm chamber strings",
               3: "electric piano", 4: "soft vibraphone", 5: "low clarinet"}
# root and upper chord voicing; add9/maj7 colours, no relentless dominant fanfare.
CHORDS = [
    (48, [55, 60, 64, 71]), (45, [52, 57, 60, 64]),
    (41, [53, 57, 60, 67]), (43, [55, 59, 62, 69]),
    (40, [52, 55, 59, 62]), (50, [53, 57, 60, 64]),
]
FORMS = [
    {"name": "MAIN", "title": "A Little Room of Light", "bpm": 68, "meter": 4, "bars": 32, "shift": 2,
     "progression": [0, 1, 2, 3, 1, 4, 2, 0]},
    {"name": "RIVER", "title": "Water Carries the Sky", "bpm": 64, "meter": 4, "bars": 32, "shift": 2,
     "progression": [0, 2, 1, 3, 5, 2, 3, 0]},
    {"name": "KITCHEN", "title": "Warm Windows", "bpm": 72, "meter": 4, "bars": 40, "shift": 5,
     "progression": [0, 4, 1, 2, 5, 3, 2, 0]},
    {"name": "ARCHIVE", "title": "Between the Pages", "bpm": 62, "meter": 3, "bars": 40, "shift": 7,
     "progression": [1, 2, 0, 3, 4, 1, 2, 0]},
    {"name": "ALBUM", "title": "Collected Small Wonders", "bpm": 62, "meter": 4, "bars": 32, "shift": 0,
     "progression": [0, 2, 4, 1, 2, 5, 3, 0]},
    {"name": "FINALE", "title": "Everything Finds Its Place", "bpm": 70, "meter": 4, "bars": 40, "shift": 2,
     "progression": [0, 1, 2, 3, 2, 4, 5, 0]},
    {"name": "CREDITS", "title": "A Quiet Bow", "bpm": 66, "meter": 4, "bars": 40, "shift": 0,
     "progression": [0, 4, 2, 3, 1, 2, 5, 0]},
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def soundfont(args):
    if args.soundfont:
        path = args.soundfont.resolve()
        if not path.is_file() or sha(path) != SOUNDFONT_SHA256:
            raise RuntimeError("SoundFont must match the pinned MIT FluidR3 GM SHA256")
        return path
    cache = args.tools_dir.resolve()
    package = cache / "fluid-soundfont-gm_3.1-5.3_all.deb"
    cache.mkdir(parents=True, exist_ok=True)
    if not package.exists() or sha(package) != PACKAGE_SHA256:
        pending = package.with_suffix(".partial")
        with urllib.request.urlopen(PACKAGE_URL, timeout=90) as source, pending.open("wb") as target:
            shutil.copyfileobj(source, target)
        if sha(pending) != PACKAGE_SHA256:
            pending.unlink()
            raise RuntimeError("SoundFont package SHA256 mismatch")
        pending.replace(package)
    subprocess.run(["dpkg-deb", "-x", str(package), str(cache / "package")], check=True)
    path = cache / "package/usr/share/sounds/sf2/FluidR3_GM.sf2"
    if sha(path) != SOUNDFONT_SHA256:
        raise RuntimeError("Extracted SoundFont SHA256 mismatch")
    return path


def note(events, start, duration, pitch, velocity, channel):
    events.append({"beat": round(start, 5), "duration": round(duration, 5),
                   "note": int(pitch), "velocity": int(velocity), "channel": channel})


def arrange(form):
    stems = {k: [] for k in ("bed", "curiosity", "tension")}
    meter, bars, shift = form["meter"], form["bars"], form["shift"]
    # Eight-bar phrases are developed across introduction / answer / bridge / return.
    for bar in range(bars):
        section = bar // 8
        part = bar % 8
        chord_index = form["progression"][(bar // 2 + (2 if section == 2 else 0)) % 8]
        root, raw_chord = CHORDS[chord_index]
        chord = [n + shift for n in raw_chord]
        base = bar * meter
        velocity = 41 + (5 if section in (1, 3) else 0)
        # Space between piano voicings lets the scene breathe; no metronomic beat.
        if bar % 2 == 0:
            note(stems["bed"], base + .04, meter * 1.8, root + shift, 43, 0)
            for j, pitch in enumerate(chord[:-1]):
                note(stems["bed"], base + .14 + j * .09, meter * 1.65,
                     pitch, velocity - j * 2, 3 if form["name"] == "ARCHIVE" else 0)
            if section != 0 or part >= 4:
                for pitch in chord[1:]:
                    note(stems["bed"], base + .36, meter * 1.65, pitch, 28, 2)
        # Nylon answers differ between sections and leave every fourth bar open.
        if part not in (3, 7) and form["name"] != "ALBUM":
            note(stems["bed"], base + meter * .47 + .035 * (part % 3), meter * .8,
                 chord[(bar + section) % 3], 38 if section != 2 else 33, 1)
            if section in (1, 3) and part in (1, 5):
                note(stems["bed"], base + meter * .83, meter * .7, chord[-1] - 12, 33, 1)
        # A short melodic question every four bars, answered only in later sections.
        # Most measures contain no foreground melody at all.
        if part in (0, 4) and not (section == 0 and part == 0):
            melody = [chord[1] + 12, chord[2] + 12, chord[1] + 12]
            if section == 2:
                melody = [chord[2] + 12, chord[-1], chord[1] + 12]
            if section == 4:
                melody = [chord[1] + 12, chord[0] + 12]
            channel = 0 if form["name"] in ("MAIN", "ALBUM", "CREDITS") else 1
            for j, pitch in enumerate(melody):
                note(stems["curiosity"], base + .55 + j * 1.65, 2.6,
                     min(pitch, 81), 38 + (3 if j == 1 else 0), channel)
        if section in (1, 3) and part == 6:
            note(stems["curiosity"], base + .7, meter * 1.15, chord[1] + 5, 33, 5)
        # The performance layer adds movement, not pressure: no drums or ticking.
        if part in (1, 5):
            for j, pitch in enumerate([chord[0], chord[2], chord[1]]):
                note(stems["tension"], base + .3 + j * meter * .54,
                     meter * .9, pitch, 29 + (j == 1) * 3, 4)
    return stems


class Synth:
    def __init__(self, font):
        library = ctypes.util.find_library("fluidsynth")
        if not library:
            raise RuntimeError("libfluidsynth is required for the sampled instrument render")
        self.lib = C.CDLL(library)
        functions = {
            "new_fluid_settings": (C.c_void_p, []),
            "fluid_settings_setnum": (C.c_int, [C.c_void_p, C.c_char_p, C.c_double]),
            "fluid_settings_setint": (C.c_int, [C.c_void_p, C.c_char_p, C.c_int]),
            "new_fluid_synth": (C.c_void_p, [C.c_void_p]),
            "fluid_synth_sfload": (C.c_int, [C.c_void_p, C.c_char_p, C.c_int]),
            "fluid_synth_program_change": (C.c_int, [C.c_void_p, C.c_int, C.c_int]),
            "fluid_synth_cc": (C.c_int, [C.c_void_p, C.c_int, C.c_int, C.c_int]),
            "fluid_synth_noteon": (C.c_int, [C.c_void_p, C.c_int, C.c_int, C.c_int]),
            "fluid_synth_noteoff": (C.c_int, [C.c_void_p, C.c_int, C.c_int]),
            "fluid_synth_write_float": (C.c_int, [C.c_void_p, C.c_int, C.c_void_p, C.c_int, C.c_int, C.c_void_p, C.c_int, C.c_int]),
            "fluid_synth_set_reverb": (None, [C.c_void_p, C.c_double, C.c_double, C.c_double, C.c_double]),
            "delete_fluid_synth": (None, [C.c_void_p]),
            "delete_fluid_settings": (None, [C.c_void_p]),
        }
        for name, (result, arguments) in functions.items():
            function = getattr(self.lib, name); function.restype = result; function.argtypes = arguments
        self.settings = self.lib.new_fluid_settings()
        self.lib.fluid_settings_setnum(self.settings, b"synth.sample-rate", SR)
        self.lib.fluid_settings_setnum(self.settings, b"synth.gain", .7)
        self.lib.fluid_settings_setint(self.settings, b"synth.chorus.active", 0)
        self.lib.fluid_settings_setint(self.settings, b"synth.polyphony", 256)
        self.synth = self.lib.new_fluid_synth(self.settings)
        if self.lib.fluid_synth_sfload(self.synth, str(font).encode(), 1) < 0:
            raise RuntimeError("FluidSynth could not load the verified SoundFont")
        self.lib.fluid_synth_set_reverb(self.synth, .72, .66, 35, .24)
        for channel, program in PROGRAMS.items():
            self.lib.fluid_synth_program_change(self.synth, channel, program)
            self.lib.fluid_synth_cc(self.synth, channel, 10, {0: 60, 1: 75, 2: 64, 3: 62, 4: 55, 5: 69}[channel])

    def render(self, notes, seconds, bpm, loop):
        length = round(seconds * SR)
        cycles = 2 if loop else 1
        buffer = np.zeros((length * cycles, 2), dtype=np.float32)
        events = []
        for cycle in range(cycles):
            for item in notes:
                start = round(item["beat"] * 60 / bpm * SR) + cycle * length
                stop = start + round(item["duration"] * 60 / bpm * SR)
                events.append((start, 1, item))
                events.append((stop, 0, item))
        events.sort(key=lambda row: (row[0], row[1]))
        cursor = 0
        for sample, active, item in events + [(len(buffer), 0, None)]:
            sample = min(sample, len(buffer))
            if sample > cursor:
                self.lib.fluid_synth_write_float(self.synth, sample - cursor,
                                                buffer.ctypes.data, cursor * 2, 2,
                                                buffer.ctypes.data, cursor * 2 + 1, 2)
                cursor = sample
            if item is not None and sample < len(buffer):
                if active:
                    self.lib.fluid_synth_noteon(self.synth, item["channel"], item["note"], item["velocity"])
                else:
                    self.lib.fluid_synth_noteoff(self.synth, item["channel"], item["note"])
        return buffer[length:].copy() if loop else buffer

    def close(self):
        self.lib.delete_fluid_synth(self.synth)
        self.lib.delete_fluid_settings(self.settings)


def variable_length(value):
    out = [value & 127]
    value >>= 7
    while value:
        out.insert(0, (value & 127) | 128); value >>= 7
    return bytes(out)


def write_midi(form, stems):
    events = [(0, b"\xff\x51\x03" + round(60000000 / form["bpm"]).to_bytes(3, "big")),
              (0, b"\xff\x58\x04" + bytes([form["meter"], 2, 24, 8]))]
    for channel, program in PROGRAMS.items():
        events.append((0, bytes([0xC0 + channel, program])))
    for notes in stems.values():
        for item in notes:
            events.extend([(round(item["beat"] * 480), bytes([0x90 + item["channel"], item["note"], item["velocity"]])),
                           (round((item["beat"] + item["duration"]) * 480), bytes([0x80 + item["channel"], item["note"], 0]))])
    events.sort(key=lambda row: (row[0], row[1][0] >> 4))
    track = bytearray(); previous = 0
    for tick, event in events:
        track += variable_length(tick - previous) + event; previous = tick
    track += b"\x00\xff\x2f\x00"
    (SOURCE / (form["name"].lower() + ".mid")).write_bytes(b"MThd" + struct.pack(">IHHH", 6, 0, 1, 480) + b"MTrk" + struct.pack(">I", len(track)) + track)


def master_and_save(aid, buffer, form, stem, loop, temporary):
    # A gentle low-pass removes brittle piano/vibraphone attacks; no pumping compressor.
    raw = temporary / "render.f32"
    raw.write_bytes(buffer.astype("<f4").tobytes())
    filtered = subprocess.run(["ffmpeg", "-v", "error", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", str(raw),
                               "-af", "highpass=f=45,lowpass=f=4200:p=2", "-f", "f32le", "pipe:1"], capture_output=True, check=True)
    array = np.frombuffer(filtered.stdout, dtype="<f4").reshape(-1, 2).copy()
    # Filter state starts at zero; a 12ms circular bridge keeps the periodic boundary continuous.
    if loop:
        n = 576
        delta = array[-1] - array[0]
        array[:n] += delta[None, :] * np.linspace(1, 0, n)[:, None]
    else:
        n = min(SR // 3, len(array) // 5)
        array[:480] *= np.linspace(0, 1, 480)[:, None]
        array[-n:] *= np.linspace(1, 0, n)[:, None]
    raw.write_bytes(array.astype("<f4").tobytes())
    result = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", str(raw),
                             "-af", "loudnorm=I=-22:TP=-2:LRA=9:print_format=json", "-f", "null", "-"], capture_output=True, text=True, check=True)
    from verify_audio import parse_loudnorm_output
    measured = parse_loudnorm_output(result.stderr)
    target = {"full": -21.5, "bed": -23.0, "curiosity": -29.5, "tension": -33.0, "stinger": -24.0}[stem]
    gain = min(10 ** ((target - float(measured["input_i"])) / 20), .72 / max(float(np.max(np.abs(array))), 1e-9))
    array *= gain
    destination = OUT / (aid.lower() + (".ogg" if loop else ".wav"))
    if loop:
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "pipe:0",
                        "-c:a", "libvorbis", "-q:a", "5", str(destination)], input=array.astype("<f4").tobytes(), check=True)
    else:
        with wave.open(str(destination), "wb") as wav:
            wav.setnchannels(2); wav.setsampwidth(2); wav.setframerate(SR)
            wav.writeframes((np.clip(array, -1, 1) * 32767).astype("<i2").tobytes())
    return {"id": aid, "path": "res://" + str(destination.relative_to(ROOT)), "bus": "Music", "loop": loop,
            "duration_seconds": round(len(array) / SR, 6), "sample_count": len(array), "sample_rate": SR, "channels": 2,
            "peak_linear": round(float(np.max(np.abs(array))), 6), "rms_linear": round(float(np.sqrt(np.mean(array * array))), 6),
            "sha256": sha(destination), "status": "new_score_device_listening_pending",
            "source": "tools/compose_background_music.py + assets/source/audio/SCORE.json",
            "rights": "Original composition; FluidR3 instrument samples, MIT, see data/audio_licenses.json",
            "tempo_bpm": form["bpm"], "meter": [form["meter"], 4], "stem": stem}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--soundfont", type=Path)
    parser.add_argument("--tools-dir", type=Path, default=ROOT.parent / "GOD-music-tools")
    parser.add_argument("--themes", nargs="+", choices=[f["name"] for f in FORMS])
    args = parser.parse_args()
    font = soundfont(args)
    catalog_path = ROOT / "data/audio_catalog.json"
    catalog = json.loads(catalog_path.read_text())
    by_id = {row["id"]: row for row in catalog["files"]}
    source_forms = []
    with tempfile.TemporaryDirectory(prefix="god-quiet-score-") as name:
        temporary = Path(name)
        for form in FORMS:
            stems = arrange(form)
            source_forms.append(dict(form, instruments=INSTRUMENTS, stems=stems))
            if args.themes and form["name"] not in args.themes:
                continue
            write_midi(form, stems)
            seconds = form["bars"] * form["meter"] * 60 / form["bpm"]
            full = form["name"] in ("MAIN", "ALBUM", "CREDITS")
            groups = {"full": sum(stems.values(), [])} if full else stems
            for stem, events in groups.items():
                engine = Synth(font)
                try:
                    audio = engine.render(events, seconds, form["bpm"], True)
                finally:
                    engine.close()
                aid = "MUS_" + form["name"] + "_" + stem.upper()
                by_id[aid] = master_and_save(aid, audio, form, stem, True, temporary)
                print(aid, by_id[aid]["duration_seconds"], "seconds", flush=True)
        if not args.themes:
            stingers = [("PROOF", 1.6, [62, 69]), ("LAW", 2.4, [62, 66, 69]),
                        ("REVEAL", .95, [64, 62]), ("CHAPTER", 3.8, [62, 66, 69, 74]),
                        ("FINAL", 6.5, [62, 69, 66, 74, 69])]
            for name, seconds, pitches in stingers:
                events = []
                for index, pitch in enumerate(pitches):
                    note(events, .05 + index * (seconds - .55) / len(pitches),
                         max(.3, seconds * .65), pitch, 43, 0)
                form = {"bpm": 60, "meter": 4}
                engine = Synth(font)
                try:
                    audio = engine.render(events, seconds, 60, False)
                finally:
                    engine.close()
                aid = "MUS_STINGER_" + name
                by_id[aid] = master_and_save(aid, audio, form, "stinger", False, temporary)
                print(aid, "rendered", flush=True)
    catalog["files"] = [by_id[row["id"]] for row in catalog["files"]]
    catalog["music_revision"] = "0.4.0-quiet-chamber"
    catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
    (SOURCE / "SCORE.json").write_text(json.dumps({"revision": "0.4.0-quiet-chamber", "sample_rate": SR,
        "tuning_hz": 440, "soundfont_sha256": sha(font), "forms": source_forms,
        "mix_intent": "Slow evolving harmony, sampled quiet instruments, sparse foreground phrases, no rhythmic pressure.",
        "loop_render": "Two complete cycles; retain second cycle with reverb tails, then 12ms circular filter-state bridge."}, indent=2) + "\n")
    (SOURCE / "soundfont-lock.json").write_text(json.dumps({"url": PACKAGE_URL, "package_sha256": PACKAGE_SHA256,
        "soundfont": "FluidR3_GM.sf2", "soundfont_sha256": sha(font), "instrument_license": "MIT",
        "runtime_soundfont_included": False, "renderer": "libfluidsynth.so.3", "composer": "tools/compose_background_music.py"}, indent=2) + "\n")
    (SOURCE / "PRODUCTION_REPORT.json").write_text(json.dumps({
        "revision": "0.4.0-quiet-chamber", "files": len(catalog["files"]),
        "music_runtime_files": 15, "stingers": 5, "unchanged_non_music_files": 202,
        "music_source": "tools/compose_background_music.py + SCORE.json + seven MIDI files",
        "non_music_source": "tools/expand_audio.py (existing effects, ambience and voices preserved)",
        "instruments": "FluidR3 GM sampled instruments, MIT",
        "review": "Run tools/verify_audio.py after rendering; subjective listening and phone review remain separate."
    }, indent=2) + "\n")


if __name__ == "__main__":
    main()
