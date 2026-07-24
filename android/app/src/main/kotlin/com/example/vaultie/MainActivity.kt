package com.example.vaultie

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Keep balances, IBANs and transaction history out of the OS app-switcher
        // snapshot (and out of screenshots / screen recordings). FLAG_SECURE blanks
        // the recents thumbnail so the last screen isn't captured before the PIN.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
