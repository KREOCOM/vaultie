package com.example.vaultie

import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android only draws edge-to-edge (content behind the status/nav bars,
        // with the system's own icons overlaid transparently on top) by default
        // starting with Android 15 — every phone before that keeps a solid
        // status-bar band reserved unless the app opts in. Without this, our
        // own onboarding artwork (which paints its own status-bar look INTO the
        // image, meant to sit under the real one) left a visible gap of empty
        // colour above it instead, on every phone below Android 15.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        // REMOVED (2026-08-12): FLAG_SECURE used to block screenshots/screen
        // recording and blank the app-switcher thumbnail here. iOS has no
        // equivalent API — a screenshot can't be prevented there, only
        // detected after the fact — so this was Android-only asymmetry, not a
        // deliberate per-platform choice. Removed for parity: screenshots now
        // work the same (i.e. are possible) on both platforms.
    }
}
