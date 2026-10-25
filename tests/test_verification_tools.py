"""Regression checks for diagnostics that must never produce a false pass."""
import base64
import hashlib
import json
import struct
import zipfile
import zlib
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import verify_audio
import verify_project
import build_android


class VerificationDiagnostics(unittest.TestCase):
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
