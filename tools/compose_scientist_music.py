"""Author the original Professor soundtrack; no audio output device or network used.

Regenerate with:
python3 tools/compose_scientist_music.py --soundfont /path/to/FluidR3_GM.sf2
The pinned FluidR3 MIT instruments are loaded through the existing offline
FluidSynth renderer. This version writes independent score/MIDI sources and
retains the previous score sources. Runtime music IDs remain stable.
"""
from pathlib import Path
import argparse
import json
import hashlib
import tempfile

import compose_background_music as renderer

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/audio/scientist-reboot"
REVISION = "0.5.0-professor-open-windows"
# zero-based General MIDI programs; marimba replaces the old vibraphone accents.
PROGRAMS = {0: 0, 1: 24, 2: 48, 3: 4, 4: 12, 5: 71}
INSTRUMENTS = {0: "low-velocity acoustic piano", 1: "nylon guitar",
               2: "chamber strings", 3: "soft electric piano",
               4: "quiet marimba", 5: "low clarinet"}
# Each row contains a bass and open upper voicing. Low register + sixth/ninth
# colours replace the old repeated close-position piano sequence.
HARMONIES = {
    "D6": (38, [54, 57, 59, 64]),
    "G9": (43, [54, 57, 59, 62]),
    "Bm7": (47, [54, 57, 62, 66]),
    "A6sus": (45, [52, 55, 59, 62]),
    "Em9": (40, [54, 55, 59, 62]),
    "Fsm7": (42, [52, 57, 61, 64]),
    "Cmaj9": (48, [52, 55, 59, 62]),
    "Dsus": (38, [50, 55, 57, 64]),
}
FORMS = [
    {"name": "MAIN", "title": "Open Windows", "bpm": 64, "meter": 4, "bars": 48, "shift": 0,
     "progression": ["D6", "G9", "Bm7", "A6sus", "Em9", "Fsm7", "G9", "D6"]},
    {"name": "RIVER", "title": "A Question on the Water", "bpm": 62, "meter": 4, "bars": 48, "shift": 0,
     "progression": ["D6", "Bm7", "G9", "A6sus", "Em9", "G9", "Dsus", "D6"]},
    {"name": "KITCHEN", "title": "The Warmth of an Idea", "bpm": 68, "meter": 4, "bars": 48, "shift": 3,
     "progression": ["D6", "Fsm7", "G9", "D6", "Bm7", "Em9", "A6sus", "D6"]},
    {"name": "ARCHIVE", "title": "Notes in the Margin", "bpm": 60, "meter": 3, "bars": 48, "shift": -2,
     "progression": ["Bm7", "G9", "D6", "A6sus", "Em9", "Cmaj9", "G9", "Bm7"]},
    {"name": "ALBUM", "title": "Small Discoveries", "bpm": 60, "meter": 4, "bars": 48, "shift": 0,
     "progression": ["G9", "D6", "Em9", "Bm7", "Fsm7", "G9", "A6sus", "D6"]},
    {"name": "FINALE", "title": "The World Answers", "bpm": 66, "meter": 4, "bars": 48, "shift": 0,
     "progression": ["D6", "G9", "Bm7", "Em9", "Fsm7", "G9", "A6sus", "D6"]},
    {"name": "CREDITS", "title": "Light Left in the Workshop", "bpm": 62, "meter": 4, "bars": 48, "shift": 0,
     "progression": ["D6", "G9", "Fsm7", "Bm7", "Em9", "G9", "A6sus", "D6"]},
]


def arrange(form):
    stems = {key: [] for key in ("bed", "curiosity", "tension")}
    meter, shift = form["meter"], form["shift"]
    name = form["name"]
    for bar in range(form["bars"]):
        section, part = divmod(bar, 8)
        # A 16-bar harmonic period; the middle section reharmonizes the answer.
        index = (bar // 2 + (2 if section == 3 else 0)) % 8
        root, raw = HARMONIES[form["progression"][index]]
        chord = [pitch + shift for pitch in raw]
        base = bar * meter
        still = section == 3
        opening = section == 0
        # Two-bar open voicings with different entrances. Each eighth bar has
        # no new chord attack; natural release carries the breathing space.
        if part in (0, 2, 4, 6):
            if not (still and part in (2, 6)):
                renderer.note(stems["bed"], base + .10, meter * 1.72,
                              root + shift + 12, 34 if still else 39, 1)
                for j, pitch in enumerate(chord[:3]):
                    renderer.note(stems["bed"], base + .22 + j * .12,
                                  meter * 1.74, pitch, 26 + (section % 3), 2)
            if part in (0, 4) and not still:
                channel = 3 if name in ("ARCHIVE", "ALBUM") else 0
                for j, pitch in enumerate(chord[1:]):
                    renderer.note(stems["bed"], base + .35 + j * .08,
                                  meter * 1.35, pitch, 34 - j * 3, channel)
        if not opening and not still and part in (1, 5):
            renderer.note(stems["bed"], base + meter * .58,
                          meter * .92, chord[section % 3], 31, 1)
        # Two-bar phrases followed by at least two bars without a melodic
        # question. The middle eight bars deliberately become almost silent.
        phrase = part in (0, 4) and not (opening and part == 0)
        phrase = phrase and not (still and part == 0)
        if phrase and not (name == "ALBUM" and part == 0):
            if section in (0, 1):
                motif = [chord[2], chord[-1], chord[1] + 12, chord[2]]
            elif section in (2, 3):
                motif = [chord[-1], chord[2], chord[1], chord[0] + 12]
            else:
                motif = [chord[2], chord[1] + 12, chord[-1], chord[1]]
            if name == "ARCHIVE":
                motif = [pitch - 2 for pitch in motif]
            starts = [.55, 2.05, meter + .75, meter + 2.15]
            durations = [1.25, 2.1, 1.1, meter * .95]
            channel = 5 if name in ("RIVER", "ARCHIVE") and section in (2, 4) else 0
            if name == "KITCHEN" and section in (1, 4):
                channel = 4
            for j, pitch in enumerate(motif):
                renderer.note(stems["curiosity"], base + starts[j], durations[j],
                              max(55, min(pitch, 78)), 35 + (j == 2) * 3, channel)
        # The live demonstration adds only occasional soft wooden replies.
        # No drum beat, clock, relentless arpeggio or cymbal marks the tempo.
        if part in (2, 6) and not opening:
            for j in range(2):
                renderer.note(stems["tension"], base + .70 + j * meter * .78,
                              meter * .72, chord[(section + j) % 3], 27 + j, 4)
    return stems


def sync_authoring(catalog):
    """Keep authoring references on the actual delivered score, not old plans."""
    by_id = {row["id"]: row for row in catalog["files"]}
    plan_path = ROOT / "data/authoring/audio_plan.json"
    plan = json.loads(plan_path.read_text())
    for row in plan:
        aid = row.get("asset_id", "")
        if not aid.startswith("MUS_"):
            continue
        rendered = by_id[aid]
        row["runtime_path"] = rendered["path"].removeprefix("res://")
        source_file = "STINGERS.json" if "_STINGER_" in aid else aid.split("_")[1].lower() + ".mid"
        row["source_path"] = "assets/source/audio/scientist-reboot/" + source_file
        row["duration_seconds"] = str(rendered["duration_seconds"])
        row["status"] = "rendered_professor_score_listening_pending"
        row["rights"] = "Original composition; MIT FluidR3 instruments, data/audio_licenses.json"
        row["music_revision"] = REVISION
    plan_path.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n")
    seed_path = ROOT / "data/music_composition_seed.json"
    seed = json.loads(seed_path.read_text())
    seed["status"] = "historical_notation_seed_preserved_not_active_score"
    seed["active_revision"] = REVISION
    seed["active_score_path"] = "assets/source/audio/scientist-reboot/SCORE.json"
    seed_path.write_text(json.dumps(seed, ensure_ascii=False, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--soundfont", type=Path, required=True)
    parser.add_argument("--themes", nargs="+", choices=[f["name"] for f in FORMS])
    args = parser.parse_args()
    font = renderer.soundfont(args)
    SOURCE.mkdir(parents=True, exist_ok=True)
    renderer.SOURCE = SOURCE
    renderer.PROGRAMS = PROGRAMS
    renderer.INSTRUMENTS = INSTRUMENTS
    catalog_path = ROOT / "data/audio_catalog.json"
    catalog = json.loads(catalog_path.read_text())
    by_id = {row["id"]: row for row in catalog["files"]}
    before = {key: value["sha256"] for key, value in by_id.items()}
    scores = []
    with tempfile.TemporaryDirectory(prefix="god-scientist-score-") as temporary_name:
        temporary = Path(temporary_name)
        for form in FORMS:
            stems = arrange(form)
            scores.append(dict(form, instruments=INSTRUMENTS, stems=stems))
            if args.themes and form["name"] not in args.themes:
                continue
            renderer.write_midi(form, stems)
            seconds = form["bars"] * form["meter"] * 60 / form["bpm"]
            groups = {"full": sum(stems.values(), [])} if form["name"] in ("MAIN", "ALBUM", "CREDITS") else stems
            for stem, notes in groups.items():
                synth = renderer.Synth(font)
                try:
                    # Less reverb than0.4 makes the quiet plucked notes clear
                    # without a constant glossy halo.
                    synth.lib.fluid_synth_set_reverb(synth.synth, .58, .62, 30, .18)
                    buffer = synth.render(notes, seconds, form["bpm"], True)
                finally:
                    synth.close()
                aid = "MUS_" + form["name"] + "_" + stem.upper()
                row = renderer.master_and_save(aid, buffer, form, stem, True, temporary)
                row["source"] = "tools/compose_scientist_music.py + assets/source/audio/scientist-reboot/SCORE.json"
                row["status"] = "new_professor_score_device_listening_pending"
                by_id[aid] = row
                print(aid, row["duration_seconds"], "seconds", flush=True)
        if not args.themes:
            # Original soft dyads/voicings, distinct from the old upward cue.
            cues = [("PROOF", 1.7, [62, 69], [0.05, .62]),
                    ("LAW", 2.5, [57, 62, 66, 71], [.05, .05, .50, .95]),
                    ("REVEAL", .95, [62, 64], [.05, .42]),
                    ("CHAPTER", 3.9, [57, 62, 66, 69], [.05, .35, .90, 1.60]),
                    ("FINAL", 6.8, [50, 57, 62, 66, 69, 62], [.05, .05, .45, 1.1, 2.0, 3.5])]
            cue_scores = []
            for name, seconds, pitches, entrances in cues:
                notes = []
                for i, pitch in enumerate(pitches):
                    renderer.note(notes, entrances[i], min(seconds * .62, seconds - entrances[i]), pitch, 35 + i % 3, 0)
                form = {"bpm": 60, "meter": 4}
                synth = renderer.Synth(font)
                try:
                    buffer = synth.render(notes, seconds, 60, False)
                finally:
                    synth.close()
                aid = "MUS_STINGER_" + name
                row = renderer.master_and_save(aid, buffer, form, "stinger", False, temporary)
                row["source"] = "tools/compose_scientist_music.py + assets/source/audio/scientist-reboot/STINGERS.json"
                by_id[aid] = row
                cue_scores.append({"id": aid, "seconds": seconds, "notes": notes})
                print(aid, "rendered", flush=True)
            (SOURCE / "STINGERS.json").write_text(json.dumps(cue_scores, indent=2) + "\n")
    catalog["files"] = [by_id[row["id"]] for row in catalog["files"]]
    catalog["music_revision"] = REVISION
    catalog["music_sources"] = {"directory": "assets/source/audio/scientist-reboot", "score": "SCORE.json", "renderer": "tools/compose_scientist_music.py"}
    catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
    (SOURCE / "SCORE.json").write_text(json.dumps({"revision": REVISION, "sample_rate": renderer.SR,
        "tuning_hz": 440, "soundfont_sha256": renderer.sha(font), "forms": scores,
        "mix_intent": "Spacious acoustic discovery music; six contrasting eight-bar sections, two-bar questions followed by rests, restrained wooden replies, no rhythmic pressure.",
        "loop_render": "Two full cycles, second cycle retained with periodic reverb tails,12ms circular filter-state bridge; no loop fade-out."}, indent=2) + "\n")
    (SOURCE / "soundfont-lock.json").write_text(json.dumps({"source_package_url": renderer.PACKAGE_URL,
        "package_sha256": renderer.PACKAGE_SHA256, "soundfont_sha256": renderer.sha(font),
        "license": "MIT; original complete notice retained in ../licenses/FluidR3-MIT.txt and data/audio_licenses.json",
        "soundfont_bundled": False, "renderer": "libfluidsynth.so.3 via tools/compose_background_music.py"}, indent=2) + "\n")
    changed = [key for key in before if by_id[key]["sha256"] != before[key]]
    report = {"revision": REVISION, "changed_ids": changed, "old_sha256": {key: before[key] for key in changed},
              "new_sha256": {key: by_id[key]["sha256"] for key in changed},
              "changed_music_files": len(changed), "unchanged_non_music_files": sum(1 for key in before if by_id[key]["bus"] != "Music" and before[key] == by_id[key]["sha256"]),
              "runtime_soundfont": False, "human_listening": "pending", "physical_phone_review": "pending"}
    (SOURCE / "PRODUCTION_REPORT.json").write_text(json.dumps(report, indent=2) + "\n")
    licenses_path = ROOT / "data/audio_licenses.json"
    licenses = json.loads(licenses_path.read_text()); licenses["music_revision"] = REVISION
    licenses["composition"] = "Original Professor soundtrack; exact score events, MIDI and original stinger events in assets/source/audio/scientist-reboot. Previous0.4 score retained separately."
    licenses_path.write_text(json.dumps(licenses, ensure_ascii=False, indent=2) + "\n")
    sync_authoring(catalog)


if __name__ == "__main__":
    main()
