"""Validate production asset coverage and byte-identical source provenance.

This reads image metadata only; it neither edits artwork nor judges its quality.
"""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def validate(root=ROOT):
    root = Path(root).resolve()
    errors = []
    report = {"characters": 0, "environments": 0, "props": 0, "source_images": 0}
    dimensions = {}

    def local(name, prefix):
        name = str(name).removeprefix("res://")
        path = (root / name).resolve()
        if not path.is_relative_to(root / prefix) or not path.is_file():
            raise ValueError("missing or unsafe asset: " + name)
        return path

    try:
        manifest = json.loads((root / "assets/art/reboot/manifest.json").read_text())
        provenance = json.loads((root / "assets/art/source/scientist-reboot/provenance.json").read_text())
        records = provenance["approved_copies"] + provenance["generated"]
        recorded = set()
        for item in records:
            runtime = local(item["runtime"], "assets/art/reboot")
            source = local(item["source"], "assets/art/source/scientist-reboot")
            digest = hashlib.sha256(runtime.read_bytes()).hexdigest()
            if digest != item["sha256"] or hashlib.sha256(source.read_bytes()).hexdigest() != digest:
                errors.append("source or runtime bytes differ: " + item["runtime"])
            if "original" in item:
                original = local(item["original"], "docs/design")
                if hashlib.sha256(original.read_bytes()).hexdigest() != digest:
                    errors.append("approved original differs: " + item["original"])
            else:
                request = item.get("request", {})
                if not request.get("prompt"):
                    errors.append("generated art has no recorded prompt: " + item["runtime"])
            with Image.open(runtime) as im:
                im.verify()
            with Image.open(runtime) as im:
                dimensions[runtime] = im.size
                if list(im.size) != [item["width"], item["height"]]:
                    errors.append("source dimension metadata differs: " + item["runtime"])
            recorded.add(runtime)
        report["source_images"] = len(recorded)
        for group in ("characters", "environments", "props"):
            entries = manifest[group]
            report[group] = len(entries)
            for key, item in entries.items():
                for variant in [item, *item.get("variants", {}).values()]:
                    path = local(variant["path"], "assets/art/reboot")
                    if path not in recorded:
                        errors.append("unrecorded source: " + variant["path"])
                        continue
                    if "region" in variant:
                        region = variant["region"]
                        if (len(region) != 4 or any(type(n) is not int for n in region)
                                or min(region[:2]) < 0 or min(region[2:]) <= 0
                                or region[0] + region[2] > dimensions[path][0]
                                or region[1] + region[3] > dimensions[path][1]):
                            errors.append("invalid atlas region: " + group + "/" + key)
                    if "pivot" in variant and (len(variant["pivot"]) != 2
                            or not all(isinstance(n, (int, float)) and 0 <= n <= 1 for n in variant["pivot"])):
                        errors.append("invalid pivot: " + group + "/" + key)
        for character in ["CH%02d" % n for n in range(1, 10)]:
            if character not in manifest["characters"]:
                errors.append("missing campaign character: " + character)
        for scene in ("ENV01", "ENV02", "ENV03"):
            if scene not in manifest["environments"]:
                errors.append("missing environment: " + scene)
        for number in range(1, 31):
            level = json.loads((root / ("data/levels/L%02d.json" % number)).read_text())
            for entity in level["entities"]:
                asset = entity["asset_id"]
                if asset.startswith("CH"):
                    if asset.removesuffix("_RIG") not in manifest["characters"]:
                        errors.append(level["level_id"] + ": missing actor " + asset)
                elif asset not in manifest["props"]:
                    errors.append(level["level_id"] + ": missing prop " + asset)
    except (OSError, ValueError, KeyError, TypeError) as error:
        errors.append(str(error))
    return {"status": "failed" if errors else "passed", **report, "errors": errors,
            "limits": "Metadata, campaign coverage and source identity; composition, acting and readability need visual review."}


if __name__ == "__main__":
    result = validate()
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(result["status"] != "passed")
