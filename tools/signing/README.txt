LOCAL DEBUG SIGNING ONLY

This deliberately public test keystore preserves the signing identity between
local debug APK builds, including after restoring this source archive. It is
not a release credential and must never sign a store/production release.

Alias: androiddebugkey
Store password: android
Key password: android
Certificate SHA-256:
c404360ce379fd5bdf86f68b8c4bb398e7a3c452a1dc3a92a46bc1e820d77893

The default build_android.py mode requires this exact file and verifies its
certificate before export. The key is missing from the recovered repository;
the default mode deliberately fails instead of silently generating a replacement.

For a separate preview installation, run:
python3 tools/build_android.py --new-debug-identity --tools-dir ../GOD-native-tools --output build/AlmostGod-0.3.0-preview.apk

This explicit mode uses package id com.almostgod.game.preview and a persistent
local test key at ../GOD-local-signing/preview-debug.keystore. It does not overwrite
the historical certificate or update an existing com.almostgod.game installation.
Use --debug-keystore PATH to choose another preview key outside the repository.
The APK certificate is independently verified against the selected key and written
to the accompanying .build.json report. Keep that local key for future previews.

No production keystore or production signing secret is included.
