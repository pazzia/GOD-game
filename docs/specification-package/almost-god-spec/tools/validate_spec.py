"""Static documentation/fixture checks. Does not run Godot or prove playability.

Only the JSON Schema keywords used by this package are interpreted. This is
not a general purpose Draft 2020-12 implementation. Run with Python 3.10+.
"""
from pathlib import Path
from collections import Counter
import csv
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
errors = []
checks = []


def check(condition, message):
    if not condition:
        errors.append(message)


def load_json(name):
    return json.loads((ROOT / name).read_text(encoding="utf-8"))


def table(name):
    with (ROOT / name).open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def unique(rows, field, label):
    values = [row[field] for row in rows]
    check(len(values) == len(set(values)), label + ": duplicate " + field)
    return set(values)


def schema_check(value, schema, path):
    if schema is False:
        errors.append(path + ": value forbidden")
        return
    if schema is True:
        return
    kinds = {"object": dict, "array": list, "string": str, "boolean": bool,
             "integer": int, "number": (int, float), "null": type(None)}
    kind = schema.get("type")
    if kind:
        allowed = kind if isinstance(kind, list) else [kind]
        valid = any(isinstance(value, kinds[k]) and
                    not (isinstance(value, bool) and k in ("number", "integer"))
                    for k in allowed)
        check(valid, path + ": wrong type")
        if not valid:
            return
    if "const" in schema:
        check(value == schema["const"], path + ": const mismatch")
    if "enum" in schema:
        check(value in schema["enum"], path + ": enum mismatch")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        check(value >= schema.get("minimum", float("-inf")), path + ": below minimum")
        check(value <= schema.get("maximum", float("inf")), path + ": above maximum")
    if isinstance(value, str) and "pattern" in schema:
        check(re.search(schema["pattern"], value) is not None, path + ": pattern mismatch")
    if isinstance(value, dict):
        for key in schema.get("required", []):
            check(key in value, path + ": missing " + key)
        props = schema.get("properties", {})
        for key, item in value.items():
            if key in props:
                schema_check(item, props[key], path + "." + key)
            elif "additionalProperties" in schema:
                schema_check(item, schema["additionalProperties"], path + "." + key)
    if isinstance(value, list):
        check(len(value) >= schema.get("minItems", 0), path + ": too few items")
        check(len(value) <= schema.get("maxItems", float("inf")), path + ": too many items")
        if schema.get("uniqueItems"):
            enc = [json.dumps(v, sort_keys=True) for v in value]
            check(len(enc) == len(set(enc)), path + ": duplicate item")
        prefix = schema.get("prefixItems", [])
        for idx, item in enumerate(value):
            sub = prefix[idx] if idx < len(prefix) else schema.get("items", True)
            schema_check(item, sub, f"{path}[{idx}]")


def references(level, assets, localization):
    name = level["level_id"]
    entities = {row["id"]: row for row in level["entities"]}
    slots = {row["id"]: row for row in level["slots"]}
    zones = {row["id"]: row for row in level["zones"]}
    witnesses = level["witnesses"]
    nodes = unique(level["navigation"]["nodes"], "id", name + " nodes")
    for group in ("entities", "slots", "zones", "witnesses", "occluders", "goals"):
        unique(level[group], "id", name + " " + group)
    check(len(witnesses) >= level["required_votes"], name + ": insufficient witnesses")
    check(len(level["initial_active_laws"]) <= level["max_active_laws"] <= 2,
          name + ": law limit")
    for entity in entities.values():
        sid = entity["initial_slot"]
        check(sid in slots, name + ": missing initial slot " + sid)
        if sid in slots:
            check(entity["type_id"] in slots[sid]["allowed_entity_types"],
                  name + ": initial slot rejects " + entity["id"])
        check(entity["asset_id"] in assets, name + ": missing planned asset " + entity["asset_id"])
        props = entity["properties"]
        for key in ("carrier_entity_id", "supports_entity"):
            if key in props:
                check(props[key] in entities, name + ": bad reference " + key)
        if "support_when_slot" in props:
            check(props["support_when_slot"] in slots, name + ": bad support slot")
    occupied = [entity["initial_slot"] for entity in entities.values()]
    check(len(occupied) == len(set(occupied)), name + ": two initial entities share one slot")
    for slot in slots.values():
        check(slot["zone_id"] in zones, name + ": bad reach zone")
        check(all(0 <= v <= limit for v, limit in zip(slot["position"], (24, 28))),
              name + ": slot outside stage")
    for zone in zones.values():
        if zone["kind"] == "WATER":
            check(all(k in zone for k in ("polygon", "initial_phase", "initial_thermal_charge")),
                  name + ": incomplete water zone")
    for occluder in level["occluders"]:
        check(occluder["owner_entity"] in entities, name + ": bad occluder owner")
        check(occluder["active_slot"] is None or occluder["active_slot"] in slots,
              name + ": bad occluder activation slot")
    for witness in witnesses:
        check(witness["initial_view_slot"] in slots, name + ": bad witness slot")
        character = witness["character_id"]
        check(character + "_RIG" in assets, name + ": missing planned witness rig " + character)
        unique(witness["views"], "id", name + " views")
        windows = []
        for view in witness["views"]:
            start = view["from_tick"]
            end = start + view["duration_ticks"]
            check(0 <= start < end <= 200, name + ": view outside show horizon")
            check(0 < view["clear_ticks"] <= view["duration_ticks"], name + ": impossible clear interval")
            windows.append((start, end))
        windows.sort()
        check(all(a[1] <= b[0] for a, b in zip(windows, windows[1:])), name + ": overlapping views")
    for proof in level["proofs"]:
        check(proof["myth_id"] in level["available_myths"], name + ": unavailable proof myth")
        check(len(proof["result_anchors"]) == 3, name + ": expected three result anchors")
        for anchor in proof["result_anchors"] + proof["method_anchors"]:
            check(anchor["entity_id"] in entities, name + ": bad evidence entity")
        for predicate in proof["predicates"]:
            params = predicate["parameters"]
            if "entity_id" in params:
                check(params["entity_id"] in entities, name + ": bad proof entity")
            if "zone_id" in params:
                check(params["zone_id"] in zones, name + ": bad proof zone")
    for route in level["navigation"]["routes"]:
        check(set(route["nodes"]) <= nodes, name + ": bad route node")
        check(route["required_support_entity"] in entities, name + ": missing route support")
        check(route["required_support_slot"] in slots, name + ": missing route support slot")
    for aid in level["presentation"].values():
        check(aid in assets, name + ": missing planned presentation asset " + aid)
    check(level["title_key"] in localization, name + ": missing title")
    check(len(level["hints"]) == len(set(level["hints"])) == 3, name + ": hints")
    check(set(level["hints"]) <= localization, name + ": missing hint strings")
    check((ROOT / "examples" / level["canonical_solution_ref"]).is_file(), name + ": missing replay fixture")


def main():
    json_files = sorted(ROOT.rglob("*.json"))
    for path in json_files:
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:
            errors.append(str(path.relative_to(ROOT)) + ": " + str(exc))
    checks.append(f"JSON parse: {len(json_files)} files")
    req, tests, tasks = table("REQUIREMENTS.csv"), table("ACCEPTANCE_TESTS.csv"), table("BACKLOG.csv")
    assets, loc = table("ASSET_MANIFEST.csv"), table("LOCALIZATION_SEED.csv")
    req_ids = unique(req, "requirement_id", "requirements")
    test_ids = unique(tests, "test_id", "tests")
    task_ids = unique(tasks, "task_id", "backlog")
    asset_ids = unique(assets, "asset_id", "assets")
    loc_ids = unique(loc, "key", "localization")
    check(len(req) == len(tests) == 79, "requirements/tests expected 79 each")
    check(len(tasks) == 33, "backlog expected 33 work packages")
    for requirement in req:
        check(requirement["work_package"] in task_ids, "requirement work package missing")
        check(requirement["acceptance_id"] in test_ids, "requirement acceptance missing")
        check(requirement["status"] == "planned", "spec must not pretend requirement implemented")
    for test in tests:
        check(test["requirement_id"] in req_ids, "test requirement missing")
        check(test["status"] == "not_run" and not test["evidence"], "spec must not pretend game test ran")
    graph = {task["task_id"]: set(filter(None, task["dependencies"].split(";"))) for task in tasks}
    for tid, deps in graph.items():
        check(deps <= task_ids, tid + ": unknown dependency")
    done = set()
    while True:
        ready = {tid for tid, deps in graph.items() if deps <= done} - done
        if not ready:
            break
        done |= ready
    check(done == task_ids, "backlog dependency cycle")
    for task in tasks:
        actual = set(filter(None, task["requirements"].split(";")))
        expected = {r["requirement_id"] for r in req if r["work_package"] == task["task_id"]}
        check(actual == expected, task["task_id"] + ": traceability mismatch")
    checks.append("Traceability and acyclic dependency graph: 79 requirements, 79 test plans, 33 work packages")
    levels = load_json("level_blueprints.json")["levels"]
    check([l["id"] for l in levels] == [f"L{i:02d}" for i in range(1, 31)], "campaign level IDs")
    check(all(len(l["hints_ru"]) == len(set(l["hints_ru"])) == 3 for l in levels), "campaign three distinct hints")
    checks.append("Campaign: 30 design cards and 90 distinct per-level hint entries")
    for number in (1, 2, 3):
        lid = f"L{number:02d}"
        level = load_json(f"examples/{lid}.json")
        schema_check(level, load_json("schemas/level.schema.json"), lid)
        references(level, asset_ids, loc_ids)
        replay = load_json(f"examples/{lid}_solution.json")
        schema_check(replay, load_json("schemas/replay.schema.json"), lid + " replay")
        check(replay["level_id"] == lid and replay["verification"] == "not_run", lid + ": replay status")
        for step in replay["steps"]:
            required = {"command": ("type", "payload"), "advance_ticks": ("count",), "assert": ("predicate",)}[step["op"]]
            check(all(key in step for key in required), lid + ": malformed replay operation")
        stone = next(e for e in level["entities"] if e["id"] == "stone")
        cargo = next((e for e in level["entities"] if e["id"] == "cargo"), None)
        hero = next(e for e in level["entities"] if e["id"] == "hero")
        load = hero["mass_units"] + (cargo["mass_units"] if cargo else 0)
        check(load <= stone["properties"]["carry_capacity"], lid + ": canonical transport overload")
        if cargo:
            check(cargo["properties"].get("carrier_entity_id") == "hero", lid + ": carrier missing")
    schema_check(load_json("examples/settings_default.json"), load_json("schemas/settings.schema.json"), "settings")
    checks.append("L01–L03/settings: used schema subset, references, observation windows and total transport load")
    categories = Counter(a["category"] for a in assets)
    check(len(assets) == 571 and all(a["status"] == "planned" for a in assets), "asset manifest expected 571 planned rows")
    check(categories["music"] == 15 and categories["stinger"] == 5 and categories["voice"] == 90, "audio manifest counts")
    check(all(a["bus"] == "Music" for a in assets if a["category"] in ("music", "stinger")), "music bus routing plan")
    melody = load_json("catalogs/music_composition_seed.json")
    check(len(melody["bars"]) == 8 and all(sum(n[1] for n in bar) == 4 for bar in melody["bars"]), "notation bar lengths")
    checks.append("571 planned assets, 15 music stems, 5 stingers, 90 vocalizations; 8-bar notation rhythm")
    report = {"kind": "documentation_static_validation", "status": "passed" if not errors else "failed",
              "checks": checks, "errors": errors,
              "limitations": ["No Godot build or replay executed by this script.",
                              "Schema interpreter implements only keywords used in supplied schemas.",
                              "Asset rows describe required future production, not existing media.",
                              "RU/EN localization is a seed; untranslated entries remain explicit."]}
    (ROOT / "VALIDATION_REPORT.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
