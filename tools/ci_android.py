"""Build a verified Android preview and an explicit, key-free release bundle."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import shutil
import subprocess
import sys

from verify_project import engine_errors, runtime_manifest, expected_check_names
from build_android import PREVIEW_PACKAGE, selected_android_package, validate_review_provider_authorities

ROOT = Path(__file__).resolve().parents[1]
APK_NAME = "AlmostGod-0.5.1-preview.apk"


def digest_manifest(manifest):
    return hashlib.sha256(json.dumps(manifest, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def validate_reports(verification, build, expected_digest, apk, expected_package=PREVIEW_PACKAGE):
    checks = verification.get("checks", [])
    required = expected_check_names(ui=True, audio=True)
    actual = [check.get("name") for check in checks]
    if (verification.get("status") != "passed" or len(actual) != len(set(actual))
            or set(actual) != set(required)
            or any(check.get("exit_code") != 0 or check.get("engine_errors") for check in checks)
            or verification.get("files_changed_during_verification") != []):
        raise RuntimeError("Every required verification suite must run exactly once and pass without engine errors or source changes.")
    if verification.get("runtime_digest_sha256") != expected_digest:
        raise RuntimeError("Verification does not describe the checked-out runtime sources.")
    if build.get("source_runtime_digest_sha256") != expected_digest:
        raise RuntimeError("APK and verification source digests differ.")
    if not build.get("signature_verified") or not build.get("new_debug_identity"):
        raise RuntimeError("Expected a verified signature for the separate preview application.")
    if expected_package != PREVIEW_PACKAGE:
        selected_android_package(True, expected_package)
        validate_review_provider_authorities(build, expected_package)
    package_nodes = [entry.get("attributes", {}) for entry in build.get("manifest", [])
                     if entry.get("element") == "manifest"]
    if len(package_nodes) != 1 or package_nodes[0].get("package") != expected_package:
        raise RuntimeError("The exported Android package must match the selected preview identity.")
    game_activities = [entry.get("attributes", {}) for entry in build.get("manifest", [])
                       if entry.get("element") == "activity"
                       and entry.get("attributes", {}).get("name") == "com.godot.game.GodotApp"]
    # Godot 4.7.2 maps SCREEN_SENSOR_LANDSCAPE (project enum 4) to Android
    # userLandscape (11), respecting the user's landscape rotation preference.
    # platform/android/export/gradle_export_util.cpp at tag 4.7.2-stable.
    if len(game_activities) != 1 or game_activities[0].get("screenOrientation") != 11:
        actual_orientations = [activity.get("screenOrientation") for activity in game_activities]
        raise RuntimeError("The exported Godot activity must use userLandscape (11), the Godot 4.7.2 "
                           f"SCREEN_SENSOR_LANDSCAPE mapping; found {actual_orientations}.")
    if build.get("sha256") != hashlib.sha256(apk.read_bytes()).hexdigest():
        raise RuntimeError("APK bytes do not match the build report.")
    if build.get("size_bytes") != apk.stat().st_size:
        raise RuntimeError("APK size does not match the build report.")
    resources = build.get("source_verification", {})
    if resources.get("missing") != [] or resources.get("mismatched") != []:
        raise RuntimeError("The APK is missing or changes required resources.")


def run(command, log, env, timeout=1800):
    print("Running:", " ".join(map(str, command)), flush=True)
    with log.open("w") as output:
        result = subprocess.run(list(map(str, command)), cwd=ROOT, env=env,
                                stdout=output, stderr=subprocess.STDOUT, timeout=timeout)
    text = log.read_text(errors="replace")
    if result.returncode or engine_errors(text):
        print(text[-12000:], flush=True)
        raise RuntimeError(f"Command failed or reported engine errors; see {log}")


def release_notes(current, run_url, build, suites, package):
    isolated = package != PREVIEW_PACKAGE
    if isolated:
        installation = (
            f"Это отдельная тестовая установка с package `{package}` и именем «Почти бог · UX тест». "
            "Она ставится рядом с прежней игрой: удалять старую preview или её данные не требуется. "
            "Прохождение и настройки новой сборки отдельные; автоматического переноса сохранений нет. "
            "Это не обновление старого package и не исправление постоянной подписи. "
            "Каждый CI-run/attempt получает другой package, поскольку временный ключ не сохраняется.\n\n")
    else:
        installation = (
            "Это legacy preview package `com.almostgod.game.preview` с временным сертификатом. "
            "Он не гарантирует обновление ранее установленной preview с иной подписью. "
            "Не удаляйте прежнюю игру ради установки без отдельной резервной копии и понимания потери локальных данных.\n\n")
    return (
        "Тестовая сборка «Почти бог» 0.5.1-preview для Android 10+ / ARM64.\n\n"
        "Исправления по результатам прогона Игрока: подсказки по текущему этапу, "
        "объяснение остановки, проверка плана, выбор и размещение предметов, пауза и крупный текст.\n\n"
        f"Скачайте `{APK_NAME}` — отдельный APK без архива.\n\n" + installation +
        f"Исходники: `{current}`. Проверки: {suites} наборов, без ошибок движка.\n\n"
        f"SHA-256 APK: `{build['sha256']}`.\n\n"
        f"[Сборка и полный журнал]({run_url})\n\n"
        "Подпись, package, состав APK и соответствие исходникам проверены автоматически. "
        "Проверка на физическом телефоне ещё не выполнена; это тестовая версия, не магазинный релиз.\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tools-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--debug-keystore", required=True, type=Path)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--preview-package", help="Isolated review package; defaults to the legacy preview identity only when omitted.")
    args = parser.parse_args()
    package = selected_android_package(True, args.preview_package)
    current = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    if current != args.source_sha:
        raise RuntimeError("Checkout HEAD differs from the workflow source SHA.")
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    apk = output / APK_NAME
    if apk.exists():
        raise RuntimeError("Use a fresh output directory; an APK already exists.")
    godot = args.tools_dir.resolve() / "Godot_v4.7.2-stable_linux.x86_64"
    env = os.environ.copy()
    baseline = runtime_manifest()
    expected_digest = digest_manifest(baseline)
    report_path = ROOT / "tests/reports/project-verification.json"
    report_path.unlink(missing_ok=True)
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    run([godot, "--headless", "--editor", "--path", ROOT, "--import", "--quit"],
        output / "import.log", env, timeout=600)
    if runtime_manifest() != baseline:
        raise RuntimeError("Import changed tracked runtime resources; commit the intended imports before release.")
    run([sys.executable, "tools/verify_project.py", "--godot", godot, "--ui", "--audio"],
        output / "verification.log", env, timeout=1800)
    if not report_path.is_file():
        raise RuntimeError("The current verification run did not produce a report.")
    build_command = [sys.executable, "tools/build_android.py", "--tools-dir", args.tools_dir.resolve(),
                     "--new-debug-identity", "--debug-keystore", args.debug_keystore.resolve(), "--output", apk]
    if args.preview_package is not None:
        build_command += ["--preview-package", package]
    run(build_command, output / "build.log", env, timeout=1200)
    verification = json.loads(report_path.read_text())
    build_path = apk.with_suffix(".build.json")
    build = json.loads(build_path.read_text())
    validate_reports(verification, build, expected_digest, apk, package)
    if runtime_manifest() != baseline:
        raise RuntimeError("Runtime sources changed during CI.")
    shutil.copy2(report_path, output / "project-verification.json")
    run_url = (f"https://github.com/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
               if "GITHUB_REPOSITORY" in os.environ and "GITHUB_RUN_ID" in os.environ else None)
    provenance = {"source_commit": current, "runtime_digest_sha256": expected_digest,
                  "started_at": started, "completed_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  "workflow_run_url": run_url, "workflow_run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
                  "apk_sha256": build["sha256"], "certificate_sha256": build["certificate_sha256"],
                  "verification_suites": len(verification["checks"]), "physical_device_tested": False,
                  "android_package": package,
                  "installation_mode": "parallel_isolated_review" if args.preview_package is not None else "legacy_preview",
                  "signing_continuity": False,
                  "progress_migration": "Not implemented; the isolated package has separate progress and settings.",
                  "legacy_installation_action": "No uninstall, reset, or migration is performed or requested.",
                  "signing_key": "Ephemeral test key generated on runner; never uploaded. Not a stable signing channel."}
    (output / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    filenames = [APK_NAME, build_path.name, "project-verification.json", "provenance.json"]
    (output / "SHA256SUMS.txt").write_text("".join(
        f"{hashlib.sha256((output / name).read_bytes()).hexdigest()}  {name}\n" for name in filenames))
    (output / "release-notes.md").write_text(release_notes(current, run_url, build, len(verification["checks"]), package))
    print(json.dumps(provenance, indent=2), flush=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error))
