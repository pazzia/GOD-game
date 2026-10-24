LOCAL DEBUG SIGNING ONLY

This deliberately public test keystore preserves the signing identity between
local debug APK builds, including after restoring this source archive. It is
not a release credential and must never sign a store/production release.

Alias: androiddebugkey
Store password: android
Key password: android
Certificate SHA-256:
c404360ce379fd5bdf86f68b8c4bb398e7a3c452a1dc3a92a46bc1e820d77893

The build_android.py script uses this exact file. Keep the package id
com.almostgod.game and increment version/code for future distributed updates.

No production keystore or production signing secret is included.
