"""Read only public APK metadata/certificates; never open signing keys.

This is a certificate-identity comparison, not an apksigner replacement or a
device installation test. Uses the already installed cryptography package.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import struct
import subprocess
import sys
import zipfile

from cryptography.hazmat.primitives.serialization import Encoding, pkcs7

ROOT = Path(__file__).resolve().parents[3]
V2 = 0x7109871A
V3 = 0xF05368C0
ROTATION = 0x3BA06F8C


def lp(data, offset=0):
    size = struct.unpack_from("<I", data, offset)[0]
    end = offset + 4 + size
    if end > len(data):
        raise ValueError("APK signing record exceeds its container")
    return data[offset + 4:end], end


def signing_blocks(path, central_directory):
    with path.open("rb") as stream:
        stream.seek(central_directory - 24)
        footer = stream.read(24)
        if footer[8:] != b"APK Sig Block 42":
            raise ValueError("No APK signing block")
        size = struct.unpack_from("<Q", footer)[0]
        stream.seek(central_directory - size - 8)
        block = stream.read(size + 8)
    if struct.unpack_from("<Q", block)[0] != size:
        raise ValueError("APK signing block size mismatch")
    entries = {}
    offset = 8
    while offset < len(block) - 24:
        length = struct.unpack_from("<Q", block, offset)[0]
        scheme = struct.unpack_from("<I", block, offset + 8)[0]
        entries[scheme] = block[offset + 12:offset + 8 + length]
        offset += 8 + length
    return entries


def scheme_identity(value, version):
    signers, _ = lp(value)
    offset = 0
    fingerprints, attributes = [], []
    while offset < len(signers):
        signer, offset = lp(signers, offset)
        signed_data, _ = lp(signer)
        _, at = lp(signed_data)  # Content digests, not validated by this reader.
        certificates, at = lp(signed_data, at)
        cert_at = 0
        while cert_at < len(certificates):
            der, cert_at = lp(certificates, cert_at)
            fingerprints.append(hashlib.sha256(der).hexdigest())
        if version == 3:
            at += 8  # minSDK and maxSDK covered by signed data.
        extra, _ = lp(signed_data, at)
        extra_at = 0
        while extra_at < len(extra):
            attribute, extra_at = lp(extra, extra_at)
            attributes.append(struct.unpack_from("<I", attribute)[0])
    return {"certificate_sha256": fingerprints,
            "additional_attribute_ids": [hex(x) for x in attributes],
            "proof_of_rotation_present": ROTATION in attributes}


def inspect(path, ci_report):
    report = json.loads(ci_report.read_text())
    native = json.loads(subprocess.check_output(
        [sys.executable, str(ROOT / "tools/inspect_apk.py"), str(path)], text=True))
    manifest = next(x["attributes"] for x in native["manifest"] if x["element"] == "manifest")
    application = next(x["attributes"] for x in native["manifest"] if x["element"] == "application")
    with zipfile.ZipFile(path) as archive:
        signatures = [name for name in archive.namelist()
                      if name.startswith("META-INF/") and name.endswith((".RSA", ".DSA", ".EC"))]
        v1 = [hashlib.sha256(c.public_bytes(Encoding.DER)).hexdigest()
              for name in signatures
              for c in pkcs7.load_der_pkcs7_certificates(archive.read(name))]
        blocks = signing_blocks(path, archive.start_dir)
    schemes = {"v2": scheme_identity(blocks[V2], 2),
               "v3": scheme_identity(blocks[V3], 3)}
    ci_manifest = next(x["attributes"] for x in report["manifest"] if x["element"] == "manifest")
    return {"apk_path": str(path), "apk_sha256": native["sha256"],
            "size_bytes": native["size_bytes"], "package": manifest["package"],
            "version_name": manifest["versionName"], "version_code": manifest["versionCode"],
            "debuggable": application.get("debuggable", False),
            "allow_backup": application.get("allowBackup", True),
            "certificate_sha256": v1, "signing_schemes": schemes,
            "ci_report": str(ci_report), "ci_signature_verified": report["signature_verified"],
            "hash_matches_ci": native["sha256"] == report["sha256"],
            "manifest_matches_ci": manifest == ci_manifest,
            "v1_certificate_matches_ci": v1 == [report["certificate_sha256"]],
            "v2_v3_certificates_match_ci": all(
                scheme["certificate_sha256"] == [report["certificate_sha256"]]
                for scheme in schemes.values())}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--old-apk", type=Path,
                        default=Path("/workspace/deliverables/0.4/AlmostGod-0.4.0-preview.apk"))
    parser.add_argument("--new-apk", type=Path,
                        default=ROOT / "artifacts/android/AlmostGod-0.5.0-preview.apk")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    old = inspect(args.old_apk, ROOT / "docs/reviews/0.4.0/ci-build.json")
    new = inspect(args.new_apk, ROOT / "docs/reviews/android-signing/ci-build-0.5.0.json")
    checks = []
    for label, data in (("old", old), ("new", new)):
        for key in ("hash_matches_ci", "manifest_matches_ci", "v1_certificate_matches_ci",
                    "v2_v3_certificates_match_ci"):
            checks.append({"id": label + "_" + key, "observed": data[key]})
        checks.append({"id": label + "_no_v3_rotation_proof",
                       "observed": not data["signing_schemes"]["v3"]["proof_of_rotation_present"]})
    checks += [{"id": "same_package", "observed": old["package"] == new["package"]},
               {"id": "increased_version_code", "observed": old["version_code"] < new["version_code"]},
               {"id": "different_signing_certificates", "observed": old["certificate_sha256"] != new["certificate_sha256"]}]
    if not all(check["observed"] for check in checks):
        raise RuntimeError("Expected evidence changed; re-evaluate the report")
    result = {"recorded_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "status": "confirmed_identity_mismatch_between_available_apks",
              "old": old, "new": new, "checks": checks,
              "evidence_check_count": len(checks), "physical_device_tested": False,
              "installed_apk_identity_known": False,
              "fresh_full_signature_verification": False,
              "method": "Independently parse binary AndroidManifest, hash APK bytes, extract public v1/v2/v3 certificate identity and v3 rotation attributes; compare with previously verified CI reports.",
              "limits": ["No connected phone or installed-package error code was inspected.",
                         "This reader does not validate content digests or cryptographic signatures; CI signature_verified is historical evidence tied to matching APK hashes.",
                         "No private keys, passwords or credential files were opened, created or changed."]}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"status": result["status"], "evidence_checks": len(checks),
                      "same_package": old["package"], "old_certificate": old["certificate_sha256"],
                      "new_certificate": new["certificate_sha256"]}, indent=2))


if __name__ == "__main__":
    main()
