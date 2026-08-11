package com.example.vaultie

import android.os.Bundle
import android.view.WindowManager
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
        // Keep balances, IBANs and transaction history out of the OS app-switcher
        // snapshot (and out of screenshots / screen recordings). FLAG_SECURE blanks
        // the recents thumbnail so the last screen isn't captured before the PIN.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
