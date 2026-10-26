"""Regression checks for diagnostics that must never produce a false pass."""
import base64
import hashlib
import http.client
import io
import json
import struct
import subprocess
import zipfile
import zlib
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
import urllib.error
from unittest.mock import patch, call

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import verify_audio
import verify_project
import build_android
import ci_android
import bootstrap_native


class VerificationDiagnostics(unittest.TestCase):
    def test_ci_rejects_missing_or_duplicate_required_suites(self):
        required = verify_project.expected_check_names(ui=True, audio=True)
        with tempfile.TemporaryDirectory() as folder:
            apk = Path(folder) / 'fixture.apk'
            apk.write_bytes(b'fixture for the report-integrity gate, not an Android package')
            checksum = hashlib.sha256(apk.read_bytes()).hexdigest()
            verification = {'status': 'passed', 'checks': [
                {'name': name, 'exit_code': 0, 'engine_errors': []} for name in required
            ], 'files_changed_during_verification': [], 'runtime_digest_sha256': 'source-fixture'}
            build = {'source_runtime_digest_sha256': 'source-fixture', 'signature_verified': True,
                     'new_debug_identity': True, 'sha256': checksum, 'size_bytes': apk.stat().st_size,
                     'manifest': [{'element': 'activity', 'attributes':
                                   {'name': 'com.godot.game.GodotApp', 'screenOrientation': 11}},
                                  {'element': 'manifest', 'attributes': {'package': build_android.PREVIEW_PACKAGE}}],
                     'source_verification': {'missing': [], 'mismatched': []}}
            ci_android.validate_reports(verification, build, 'source-fixture', apk)
            for mode in ('missing', 'duplicate', 'zero'):
                broken = json.loads(json.dumps(verification))
                if mode == 'missing':
                    broken['checks'] = [row for row in broken['checks'] if row['name'] != 'test_quest_journey.gd']
                elif mode == 'duplicate':
                    broken['checks'][-1] = broken['checks'][0]
                else:
                    broken['checks'] = []
                with self.subTest(mode=mode), self.assertRaises(RuntimeError):
                    ci_android.validate_reports(broken, build, 'source-fixture', apk)
            for orientation in (1, 4, 6, 10, None):
                # Portrait and unrestricted sensor modes must never pass. The
                # legacy value 6 is also not the pinned exporter's output (11).
                invalid = json.loads(json.dumps(build))
                invalid['manifest'][0]['attributes']['screenOrientation'] = orientation
                with self.subTest(orientation=orientation), self.assertRaisesRegex(RuntimeError, 'userLandscape.*found'):
                    ci_android.validate_reports(verification, invalid, 'source-fixture', apk)

    def test_zero_exit_leak_warnings_are_errors(self):
        for warning in (
            'WARNING: ObjectDB instances were leaked at exit (run with --verbose for details).',
            'WARNING: ObjectDB instances leaked at exit.',
            'ERROR: 5 resources still in use at exit.',
            'Resources still in use at exit',
            'SCRIPT ERROR: Parse Error: unresolved symbol',
        ):
            with self.subTest(warning=warning):
                self.assertEqual(verify_project.engine_errors('28 checks passed\n' + warning), [warning])
        self.assertEqual(verify_project.engine_errors('Godot Engine 4.7.2\n28 checks passed'), [])

    def test_loudnorm_allows_trailing_ffmpeg_logs(self):
        stats = {'input_i': '-20.15', 'input_tp': '-6.02'}
        stderr = '[Parsed_loudnorm_0 @ 0x1234]\n' + json.dumps(stats)
        stderr += '\n[out#0/null @ 0x4321] video:0KiB audio:12402KiB\nlog with {unrelated braces}\n'
        self.assertEqual(verify_audio.parse_loudnorm_output(stderr), stats)

    def test_loudnorm_selects_last_complete_measurement(self):
        self.assertEqual(verify_audio.parse_loudnorm_output(
            '{"input_i":"-30", "input_tp":"-4"}\n'
            '{"unrelated": 1}\n{"input_i":"-21", "input_tp":"-5"}\n'
        )['input_i'], '-21')

    def test_loudnorm_missing_or_truncated_report_fails(self):
        for text in ('ffmpeg error', '{"input_i": "-20"}', '{"input_i": "-20", "input_tp":'):
            with self.subTest(text=text), self.assertRaises(ValueError):
                verify_audio.parse_loudnorm_output(text)

    def test_archived_art_is_not_part_of_runtime_digest(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'assets').mkdir()
            (root / 'old' / 'assets').mkdir(parents=True)
            (root / 'assets' / 'stone.png').write_bytes(b'current')
            (root / 'old' / 'assets' / 'stone.png').write_bytes(b'historical')
            with patch.object(verify_project, 'ROOT', root):
                before = verify_project.runtime_manifest()
                (root / 'old' / 'assets' / 'stone.png').write_bytes(b'another historical version')
                self.assertEqual(verify_project.runtime_manifest(), before)
                self.assertEqual(list(before), ['assets/stone.png'])

    def test_missing_archived_key_never_creates_a_replacement(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            args = SimpleNamespace(new_debug_identity=False, debug_keystore=None)
            with patch.object(build_android, 'ROOT', root), patch.object(build_android, 'run') as run:
                with self.assertRaisesRegex(RuntimeError, 'Archived debug.keystore is missing'):
                    build_android.signing_identity(args, root / 'jdk', {}, root / 'build.apk')
                run.assert_not_called()
                self.assertFalse((root / 'tools/signing/debug.keystore').exists())

    def test_preview_key_cannot_overwrite_a_repository_key(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            key = root / 'tools/signing/debug.keystore'
            key.parent.mkdir(parents=True)
            key.write_bytes(b'archived identity')
            args = SimpleNamespace(new_debug_identity=True, debug_keystore=key)
            with patch.object(build_android, 'ROOT', root), self.assertRaisesRegex(RuntimeError, 'outside the source repository'):
                build_android.signing_identity(args, root / 'jdk', {}, root / 'build.apk')
            self.assertEqual(key.read_bytes(), b'archived identity')

    def test_export_checks_effective_package_version_and_min_sdk(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'export_presets.cfg').write_text('version/code=4\nversion/name="0.3.0-preview"\n')
            report = {'manifest': [
                {'element': 'manifest', 'attributes': {'package': 'com.almostgod.game.preview', 'versionCode': 4, 'versionName': '0.3.0-preview'}},
                {'element': 'uses-sdk', 'attributes': {'minSdkVersion': 29}},
            ]}
            with patch.object(build_android, 'ROOT', root):
                build_android.validate_android_manifest(report, True)
                for element, field, invalid in ((0, 'package', 'com.almostgod.game'), (0, 'versionCode', 3), (0, 'versionName', '0.2.0'), (1, 'minSdkVersion', 24)):
                    broken = json.loads(json.dumps(report))
                    broken['manifest'][element]['attributes'][field] = invalid
                    with self.subTest(field=field), self.assertRaises(RuntimeError):
                        build_android.validate_android_manifest(broken, True)

    def test_isolated_package_scope_preserves_legacy_modes_and_separates_attempts(self):
        self.assertEqual(build_android.selected_android_package(False), 'com.almostgod.game')
        self.assertEqual(build_android.selected_android_package(True), 'com.almostgod.game.preview')
        first = 'com.almostgod.game.review.r40277559409.a1'
        retry = 'com.almostgod.game.review.r40277559409.a2'
        self.assertEqual(build_android.selected_android_package(True, first), first)
        self.assertEqual(build_android.selected_android_package(True, retry), retry)
        self.assertNotEqual(first, retry)
        with self.assertRaisesRegex(RuntimeError, 'requires --new-debug-identity'):
            build_android.selected_android_package(False, first)
        for invalid in ('', 'com.almostgod.game', 'com.almostgod.game.preview',
                        'com.almostgod.game.preview.stable', 'com.almostgod.game.review',
                        'com.almostgod.game.review.r0.a1', 'com.almostgod.game.review.r1.a0',
                        'com.almostgod.game.review.r01.a1', 'com.almostgod.game.review.r1.a01',
                        'com.almostgod.game.review.r1.a1.extra', 'com.almostgod.game.review.r1\n',
                        'com.almostgod.game.review.r1/a1'):
            with self.subTest(package=invalid), self.assertRaisesRegex(RuntimeError, 'Review package must be'):
                build_android.selected_android_package(True, invalid)

    def test_invalid_review_package_fails_before_signing_or_tool_access(self):
        args = SimpleNamespace(new_debug_identity=True, preview_package='com.almostgod.game.preview')
        with patch.object(build_android, 'signing_identity') as signing:
            with self.assertRaisesRegex(RuntimeError, 'Review package must be'):
                build_android.build(args)
            signing.assert_not_called()

    def test_review_export_checks_exact_attempt_package_in_actual_manifest(self):
        package = 'com.almostgod.game.review.r40277559409.a1'
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'export_presets.cfg').write_text('version/code=7\nversion/name="0.5.1-preview"\n')
            report = {'manifest': [
                {'element': 'manifest', 'attributes': {'package': package, 'versionCode': 7, 'versionName': '0.5.1-preview'}},
                {'element': 'uses-sdk', 'attributes': {'minSdkVersion': 29}},
                {'element': 'provider', 'attributes': {'name': 'androidx.core.content.FileProvider',
                                                       'authorities': package + '.fileprovider'}},
                {'element': 'provider', 'attributes': {'name': 'androidx.startup.InitializationProvider',
                                                       'authorities': package + '.fileprovider'}},
            ]}
            with patch.object(build_android, 'ROOT', root):
                build_android.validate_android_manifest(report, True, package)
                for actual in ('com.almostgod.game.preview', 'com.almostgod.game',
                               'com.almostgod.game.review.r40277559409.a2'):
                    wrong = json.loads(json.dumps(report))
                    wrong['manifest'][0]['attributes']['package'] = actual
                    with self.subTest(package=actual), self.assertRaisesRegex(RuntimeError, 'APK package does not match'):
                        build_android.validate_android_manifest(wrong, True, package)
                for actual in ('com.almostgod.game.preview.fileprovider', package + '2.fileprovider',
                               package + '.fileprovider;com.almostgod.game.preview.other', ''):
                    wrong = json.loads(json.dumps(report))
                    wrong['manifest'][3]['attributes']['authorities'] = actual
                    with self.subTest(authority=actual), self.assertRaisesRegex(RuntimeError, 'provider authorities'):
                        build_android.validate_android_manifest(wrong, True, package)

    def test_ci_rejects_missing_duplicate_or_different_review_package(self):
        package = 'com.almostgod.game.review.r40277559409.a1'
        required = verify_project.expected_check_names(ui=True, audio=True)
        with tempfile.TemporaryDirectory() as folder:
            apk = Path(folder) / 'fixture.apk'
            apk.write_bytes(b'fixture for checking CI identity contracts; not an Android package')
            verification = {'status': 'passed', 'checks': [
                {'name': name, 'exit_code': 0, 'engine_errors': []} for name in required
            ], 'files_changed_during_verification': [], 'runtime_digest_sha256': 'source-fixture'}
            build = {'source_runtime_digest_sha256': 'source-fixture', 'signature_verified': True,
                     'new_debug_identity': True, 'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
                     'size_bytes': apk.stat().st_size, 'source_verification': {'missing': [], 'mismatched': []},
                     'manifest': [{'element': 'manifest', 'attributes': {'package': package}},
                                  {'element': 'activity', 'attributes':
                                   {'name': 'com.godot.game.GodotApp', 'screenOrientation': 11}},
                                  {'element': 'provider', 'attributes': {'authorities': package + '.fileprovider'}}]}
            ci_android.validate_reports(verification, build, 'source-fixture', apk, package)
            for mode in ('missing', 'duplicate', 'legacy', 'other_attempt', 'legacy_provider'):
                wrong = json.loads(json.dumps(build))
                message = 'Android package must match'
                if mode == 'missing':
                    wrong['manifest'].pop(0)
                elif mode == 'duplicate':
                    wrong['manifest'].append(wrong['manifest'][0])
                elif mode == 'legacy_provider':
                    wrong['manifest'][2]['attributes']['authorities'] = 'com.almostgod.game.preview.fileprovider'
                    message = 'provider authorities'
                else:
                    wrong['manifest'][0]['attributes']['package'] = (
                        build_android.PREVIEW_PACKAGE if mode == 'legacy' else 'com.almostgod.game.review.r40277559409.a2')
                with self.subTest(mode=mode), self.assertRaisesRegex(RuntimeError, message):
                    ci_android.validate_reports(verification, wrong, 'source-fixture', apk, package)

    def test_isolated_release_notes_never_instruct_deleting_legacy_progress(self):
        package = 'com.almostgod.game.review.r40277559409.a1'
        notes = ci_android.release_notes('source-fixture', 'https://github.com/fixture/run',
                                         {'sha256': 'checksum-fixture'}, 32, package)
        self.assertIn(package, notes)
        self.assertIn('ставится рядом', notes)
        self.assertIn('удалять старую preview или её данные не требуется', notes)
        self.assertIn('Прохождение и настройки новой сборки отдельные', notes)
        self.assertIn('не исправление постоянной подписи', notes)
        self.assertIn(ci_android.APK_NAME, notes)
        self.assertNotIn('потребуется удалить её', notes)

    def test_ci_rejects_legacy_authority_inside_otherwise_valid_review(self):
        package = 'com.almostgod.game.review.r40277559409.a1'
        report = {'manifest': [{'element': 'provider', 'attributes':
                              {'authorities': 'com.almostgod.game.preview.fileprovider'}}]}
        with self.assertRaisesRegex(RuntimeError, 'provider authorities'):
            build_android.validate_review_provider_authorities(report, package)
        report['manifest'][0]['attributes']['authorities'] = package + '.fileprovider;' + package + '.startup'
        build_android.validate_review_provider_authorities(report, package)


class PinnedDownloadRecovery(unittest.TestCase):
    def test_transient_http_retry_retains_pinned_digest_and_atomic_result(self):
        payload = b'pinned tool fixture'
        checksum = hashlib.sha512(payload).hexdigest()
        for status in (408, 429, 500, 502, 503, 504):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as folder:
                path = Path(folder) / 'tool.zip'
                responses = [urllib.error.HTTPError('https://example.invalid/tool', status, 'transient', {}, None),
                             urllib.error.HTTPError('https://example.invalid/tool', status, 'transient', {}, None),
                             io.BytesIO(payload)]
                with patch.object(bootstrap_native.urllib.request, 'urlopen', side_effect=responses) as fetch, patch.object(bootstrap_native.time, 'sleep') as sleep:
                    self.assertEqual(bootstrap_native.fetch('https://example.invalid/tool', path, checksum), path)
                    self.assertEqual(fetch.call_count, 3)
                    self.assertEqual(sleep.call_args_list, [call(1), call(2)])
                self.assertEqual(path.read_bytes(), payload)
                self.assertFalse(path.with_suffix('.zip.partial').exists())

    def test_transport_retry_is_bounded_and_leaves_no_partial(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'tool.zip'
            with patch.object(bootstrap_native.urllib.request, 'urlopen', side_effect=urllib.error.URLError(TimeoutError('fixture timeout'))) as fetch, patch.object(bootstrap_native.time, 'sleep') as sleep:
                with self.assertRaises(urllib.error.URLError):
                    bootstrap_native.fetch('https://example.invalid/tool', path, 'pinned-digest')
                self.assertEqual(fetch.call_count, 3)
                self.assertEqual(sleep.call_args_list, [call(1), call(2)])
            self.assertFalse(path.exists())
            self.assertFalse(path.with_suffix('.zip.partial').exists())

    def test_denials_and_not_found_never_retry(self):
        errors = [urllib.error.HTTPError('https://example.invalid/tool', code, 'not transient', {}, None)
                  for code in (401, 403, 404, 407)]
        errors.append(urllib.error.URLError(OSError('Tunnel connection failed: 403 Forbidden')))
        for error in errors:
            with self.subTest(error=str(error)), tempfile.TemporaryDirectory() as folder:
                path = Path(folder) / 'tool.zip'
                with patch.object(bootstrap_native.urllib.request, 'urlopen', side_effect=error) as fetch, patch.object(bootstrap_native.time, 'sleep') as sleep:
                    with self.assertRaises(urllib.error.URLError):
                        bootstrap_native.fetch('https://example.invalid/tool', path, 'pinned-digest')
                    self.assertEqual(fetch.call_count, 1)
                    sleep.assert_not_called()

    def test_hash_mismatch_never_retries_or_replaces_cached_bytes(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'tool.zip'
            path.write_bytes(b'previous cache bytes')
            checksum = hashlib.sha512(b'expected payload').hexdigest()
            with patch.object(bootstrap_native.urllib.request, 'urlopen', return_value=io.BytesIO(b'wrong payload')) as fetch, patch.object(bootstrap_native.time, 'sleep') as sleep:
                with self.assertRaisesRegex(RuntimeError, 'Checksum mismatch'):
                    bootstrap_native.fetch('https://example.invalid/tool', path, checksum)
                self.assertEqual(fetch.call_count, 1)
                sleep.assert_not_called()
            self.assertEqual(path.read_bytes(), b'previous cache bytes')
            self.assertFalse(path.with_suffix('.zip.partial').exists())

    def test_interrupted_read_restarts_download_from_zero(self):
        class Interrupted(io.BytesIO):
            def read(self, size=-1):
                if self.tell():
                    raise http.client.IncompleteRead(b'fragment')
                return super().read(3)
        payload = b'complete pinned fixture'
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'tool.zip'
            with patch.object(bootstrap_native.urllib.request, 'urlopen', side_effect=[Interrupted(payload), io.BytesIO(payload)]), patch.object(bootstrap_native.time, 'sleep') as sleep:
                bootstrap_native.fetch('https://example.invalid/tool', path, hashlib.sha512(payload).hexdigest())
                self.assertEqual(sleep.call_args_list, [call(1)])
            self.assertEqual(path.read_bytes(), payload)

    def test_verified_cache_never_contacts_network(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'tool.zip'
            payload = b'verified cache fixture'; path.write_bytes(payload)
            with patch.object(bootstrap_native.urllib.request, 'urlopen') as fetch:
                self.assertEqual(bootstrap_native.fetch('https://example.invalid/tool', path, hashlib.sha512(payload).hexdigest()), path)
                fetch.assert_not_called()


# Exact binary AndroidManifest.xml from official Godot 4.7.2 android_debug.apk.
# SHA-256: 0c23a84cc3ad46240dac623c012eb7773ea39d6092ca9de34111e4187702622d
# Compressed inline so the regression remains independent of a local SDK/network.
OFFICIAL_TEMPLATE_MANIFEST = zlib.decompress(base64.b64decode(
    b"eNqtWM1vVFUUP6/TlqEtZYooxYJ8lQ+BPkDLpwi00MLIUIaWVuNCGWbaMjq0dWYKhZiIRolx4cIYFsSVC1fElVFjTNzwB7AyrowL"
    b"VsSVIeiCRH/nvHM79915047KTH5995177+983o9pjOL0WxeRR2to23Ki16jyedertNuBNcA2oBdIAW8AV4BPgC+Au8CvQBzz1gOD"
    b"QA4oAjeBr4C7wK/AX8DGBowBLgDXgVvAN8A94D7QHCPqBnqB14EPgG+BX4A/gM5GoiFgDrgJfA08AB4Cj4HOJqKdwGEgDcwAHwA/"
    b"AI+BY82wDfgRaFtCdB74HtgSJ/oMeAScX0p0B7gHbGwBF5AGZoAvgfvAllb4AHwP/Aw8AKgNsQRuA3eA34CVy4h8oB8YA64Dt4Am"
    b"KtMlGqfLAL8VKEMX0S7grZHylKVpmpL2FHqCUS00g2cRb3kq4ZvXMUsgnZL5BbRyMjKH1kWapUl8TQ+yhL9zYJkGS1nHLsF7EZIs"
    b"3pmVaIWMymLOrPAMSv9lGkY7K7rKMq4VzLPiB/Pl0coLB9FT0FpEL48clb50hOUlsbQgLFNgvkRnIM+JpR3ozWLGuOg7KxyB5ozo"
    b"CTxfpnGagGSSjoOBdU6qFU2o1Ix4EfheFPk03oviB1c48xVlRpn6IGXuK+LLNeFni6doBFa9TWPiQyXurRhpS47PW+/2DM3n8Cm6"
    b"Kow5yK+Cdxq2lykJyYzEshKBRMi2WhawfwXh6kc7izGzYOKeScgHMNad04b2ZZ03YsW4JP5OSS6Dfre3TXIVWOT2BdF9B9rz0uLK"
    b"Wi6elsQP1paSKgvnb24BzmaplpPzseuQuixLZXGmhpSLY53C86JWb5DnPF3H09R+dW47MYZjZVZDCTWal1GzwsA5CUvYo5z6x9J+"
    b"zJyWurkqPoxrRpjzuNg2Dr+Y/ZpYn5VVNAOGgngbldHVdYwydTZlVZXRGszlUcFqGdRYGSuawHJJ9pmCxIpXTElWeAa2BjpHIWF9"
    b"J8SHjJwCJrvjks+UeMbM11Bjc+JpUezhqgm0ZSSnRDHaQz7tRqsBrX1SR72Q7AdeAIL6qOxQh2A/7yhsfx7cXAcZzV4Qo/j8eyWb"
    b"7VWyHrEmL/7xLpeRVcc7WV6q81lH4ku1ljVufkinj3XZh4oYwrx1i8zLOpn3EccBRLgPcU3ReTCs/9cMKZk9hPyeAtcwOFZVcUSd"
    b"Dax7FLanMWNT1Yxw/fuwMQlNA/Qmxg9jzx3D+wnRx5I+2H4K2cXZ5zDNic3TUiO+VqIvtciSxWty44J8wQ5fic6gVmlaxl+RGew5"
    b"ocaqeYKzbULnhPcjnuUrjxmRDI0wJ15e93OivU9cB49ISq2XpVoLunMV5db1X7SFK7cfGQwqh2t4mE4jm2dhEeeVc5rE29B/jl5Y"
    b"F6+QEXD2oY5S83Vk6opkTf5fHSNgH7OqtMK+/YmwnwZfGuwV3kQEb0lP57Ket1sXHeNHZLlyFlZXszlJCnIGZUL7X7bqdGnXc8MX"
    b"WU7OJV/26OCEWLVgv49T1kj7RCvvc/9uRsq6xwUeLMbgRqynKqpdizCYvM5URW87rCjjO4PzZBe+JbXrspwHftVeGOjZJTF/G8/g"
    b"DrGr6tRYFtqre9SCsmqNCz9neUJPSqKlYiv71QMGc6Jul8xNhjwbl7trXvbJsMezkv2CWJ4O3dbTzlm5blHegtyUihJnPluuODcQ"
    b"/j0Q3CTNCd4pVciWT+jtsF/ueQXwj9W4Adc/p3I3bnVWq30rqM5wXO9h9u6cqLrT9YR+RwS32Fm535Qke+Nio7nfxa2+kty8+HPD"
    b"i9M30vI8D2gAYkAz0A4sBxJAB7AK6AS6gLXAc8A6oBvYzHMbPK8N6ALWADuAGeAG8D7wIfARcBP4FPgO+Al4GPO8B42e9wj4E2hq"
    b"8rwBoAiUgOvA58BtINbMZiaQA75zEf2Nzwt4Jvkd8ruWnD+n0V6Jb1x/9yflRhn0Q5bwVLYS2CFRotgOla21xpm5my1Zt8q2ADt1"
    b"7k7tP4vnCZWdUFnamcvtc5YsoT6kgnnzPryqPjRYPqyw5nWq7BmHP6ZxcrlYRzn4ST8vH1UdjZaO1RW+FfxMys2yWtYVIXvOkRlb"
    b"XJ3G3xWWfCzC384KXwffu5P6/5soHS4X6/jdig9/+lVHi6XDq/BhVbS+l7RqKS7dLSJrjvB3lSUzfOsixq2PkHVH1NlW4IDWzwGV"
    b"PR+hY7sjM/HcYPk6HBHPpgg7ttWIp8tl4rnZku+OiCeF4tkmsYsBA+rXgI5bEuHX0ghZmxWnRpUti4hdu1UrD48GsqctWULHbYjQ"
    b"sbFGDFxfOQYX8NxjyfdoDGJWDLg9qP4ORvhrYt/hxIX5u+VOXuF/RfnNh8dwbeyzxuzSMZ5jw4vK/aK1L7jzDN8BS368Bl+v8vVa"
    b"fO48w3ewDr69yrfX4nPnGbkbEyN3c2HWwhFLnopYC6x/SPUPqWy53OgDWY+lw+Uye2l/xFporLEWEmAzes+ojjMLrAXev30d51u2"
    b"9EfUJNtyypKPRNgS09gy38EF9LYoF487pbJWp3ZNjM/UEeP9yrVfZYnQ3tr+nvHL5TJy1y+zBs9F+OuuwT7V3beIvyd13Emrfkbr"
    b"8O0lnfeSVT/HVHbM8mG0hm/nInz7GM/XLfl51d3k6D6keg6prFHXNsv2LbDfR+1DmyLOE96HLtSxD2Xq2IdeVrtetnx35xm5q9PY"
    b"kq3DllwdthxVW45aOnM1bMnWsGWiDlsm67DliNpyxNI5WcOWiRq25Ouw5a06bDmsthy2dL5Vw5Z8jb3YrVsjd+9gMecub+7sXo07"
    b"/j/D6riR"
))


class AndroidTemplateMinimumSdk(unittest.TestCase):
    def test_apk_inspector_requires_exact_font_license_contents(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            license_file = root / 'assets/fonts/NunitoSans-OFL.txt'
            license_file.parent.mkdir(parents=True)
            license_file.write_text('SIL Open Font License fixture\n')
            packed_license = 'assets/assets/fonts/NunitoSans-OFL.txt'
            with patch.object(verify_project, 'ROOT', root):
                self.assertIn('assets/fonts/NunitoSans-OFL.txt', verify_project.runtime_manifest())
            # A minimally shaped ELF64 has one compatible LOAD segment. No code runs.
            native = bytearray(120)
            native[:5] = b'\x7fELF\x02'
            struct.pack_into('<Q', native, 32, 64)
            struct.pack_into('<HH', native, 54, 56, 1)
            struct.pack_into('<I', native, 64, 1)
            struct.pack_into('<Q', native, 112, 16384)
            for mode in ('present', 'missing', 'changed'):
                apk = root / (mode + '.apk')
                with zipfile.ZipFile(apk, 'w') as archive:
                    archive.writestr('AndroidManifest.xml', OFFICIAL_TEMPLATE_MANIFEST)
                    for number in range(1, 31):
                        archive.writestr(f'assets/data/levels/L{number:02d}.json', '{}')
                    if mode != 'missing':
                        archive.writestr(packed_license, license_file.read_bytes() if mode == 'present' else b'altered license')
                    entry = zipfile.ZipInfo('lib/arm64-v8a/libfixture.so')
                    padding = (-archive.fp.tell() - 30 - len(entry.filename) - 4) % 16384
                    entry.extra = struct.pack('<HH', 0xffff, padding) + bytes(padding)
                    archive.writestr(entry, native)
                result = subprocess.run([sys.executable, str(Path(build_android.__file__).with_name('inspect_apk.py')), str(apk), '--source-root', str(root)], capture_output=True, text=True)
                report = json.loads(result.stdout)
                verification = report['source_verification']
                self.assertEqual(verification['font_licenses_expected'], 1)
                with self.subTest(mode=mode):
                    self.assertEqual(result.returncode, 0 if mode == 'present' else 1, result.stderr)
                    self.assertEqual(verification['missing'], [packed_license] if mode == 'missing' else [])
                    self.assertEqual(verification['mismatched'], [packed_license] if mode == 'changed' else [])

    def test_real_official_manifest_changes_only_the_minimum_integer(self):
        before = OFFICIAL_TEMPLATE_MANIFEST
        self.assertEqual(hashlib.sha256(before).hexdigest(), '0c23a84cc3ad46240dac623c012eb7773ea39d6092ca9de34111e4187702622d')
        patched, report = build_android.patch_manifest_min_sdk(before)
        offset, minimum = build_android.manifest_min_sdk(patched)
        self.assertEqual((offset, minimum), (4340, 29))
        self.assertEqual(report['before'], 24)
        self.assertEqual(before[:offset], patched[:offset])
        self.assertEqual(before[offset + 4:], patched[offset + 4:])
        self.assertEqual(len(before), len(patched))

    def test_rejects_malformed_ambiguous_or_unexpected_manifests(self):
        source = OFFICIAL_TEMPLATE_MANIFEST
        offset, _ = build_android.manifest_min_sdk(source)
        invalid = [b'', source[:7], source[:-1], source + b'\0\0\0\0']
        for at, fmt, value in ((12, '<I', 0), (offset - 1, '<B', 3),
                               (offset - 8, '<I', 0), (offset - 16, '<I', 0xffffffff)):
            changed = bytearray(source)
            struct.pack_into(fmt, changed, at, value)
            invalid.append(bytes(changed))
        # Duplicate uses-sdk must fail instead of updating only one declaration.
        duplicate = bytearray(source[:4364] + source[4288:4364] + source[4364:])
        struct.pack_into('<I', duplicate, 4, len(duplicate))
        invalid.append(bytes(duplicate))
        # Matching name with an incorrect Android resource ID is not sufficient.
        changed = bytearray(source)
        attribute_name = struct.unpack_from('<I', source, offset - 12)[0]
        struct.pack_into('<I', changed, 3888 + 8 + attribute_name * 4, 0x01010000)
        invalid.append(bytes(changed))
        for value in invalid:
            with self.subTest(length=len(value)), self.assertRaises(RuntimeError):
                build_android.patch_manifest_min_sdk(value)
        patched, _ = build_android.patch_manifest_min_sdk(source)
        with self.assertRaisesRegex(RuntimeError, 'expected 24, found 29'):
            build_android.patch_manifest_min_sdk(patched)
        with self.assertRaisesRegex(RuntimeError, 'Invalid target'):
            build_android.patch_manifest_min_sdk(source, target=-1)

    def test_template_copy_preserves_original_and_other_entries(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'official.apk'
            target = Path(folder) / 'custom.apk'
            with zipfile.ZipFile(source, 'w', zipfile.ZIP_DEFLATED) as archive:
                archive.writestr('AndroidManifest.xml', OFFICIAL_TEMPLATE_MANIFEST)
                archive.writestr('classes.dex', b'unchanged executable')
                archive.writestr('lib/arm64-v8a/libgodot_android.so', b'unchanged native')
            original = source.read_bytes()
            report = build_android.prepare_debug_template(source, target)
            self.assertEqual(source.read_bytes(), original)
            self.assertTrue(report['other_entry_contents_unchanged'])
            with zipfile.ZipFile(target) as archive:
                self.assertIsNone(archive.testzip())
                self.assertEqual(archive.read('classes.dex'), b'unchanged executable')
                self.assertEqual(archive.read('lib/arm64-v8a/libgodot_android.so'), b'unchanged native')
                self.assertEqual(build_android.manifest_min_sdk(archive.read('AndroidManifest.xml'))[1], 29)
            with self.assertRaisesRegex(RuntimeError, 'never be overwritten'):
                build_android.prepare_debug_template(source, source)


if __name__ == '__main__':
    unittest.main()
