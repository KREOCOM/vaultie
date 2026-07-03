# App Review notes (App Store Connect)

Paste the block below into **App Store Connect → your app → the version →
App Review Information → Notes**, after filling in the demo credentials.

> ⚠️ **Do not commit real credentials to this repo.** It is public. Fill in the
> demo account only inside App Store Connect. The `<...>` fields below are
> placeholders.

---

## Ready-to-paste review notes

```
DEMO ACCOUNT (email/password)
Email:    <demo email, e.g. appreview@vaultie.app>
Password: <demo password>

This account is already email-verified, so it goes straight to the dashboard.

WHY A DEMO ACCOUNT IS NEEDED
Vaultie requires an account. New sign-ups must confirm their email via a link
before reaching the app. The demo account above is pre-verified so you can sign
in without inbox access. You may also use "Continue with Apple" or
"Continue with Google" on the sign-in screen.

IN-APP PURCHASES (Vaultie Pro)
The app is free for up to 3 subscriptions. Adding a 4th opens the paywall.
Products: Monthly (auto-renewable) and Lifetime (one-time), managed via
RevenueCat + StoreKit. Please test with a Sandbox Apple ID. "Restore purchases"
is on the paywall; Terms and Privacy links are on the paywall itself.

HOW TO REACH KEY SCREENS
- Paywall:        add a 4th subscription, OR Settings → Vaultie Pro → Learn more
- Account delete: Settings → Delete account (in-app, per 5.1.1(v))
- Legal:          Settings → Privacy Policy / Terms of Use

CONTACT
osva50042@gmail.com
```

---

## How to create the pre-verified demo account

1. In **Firebase Console → Authentication → Users → Add user**, create the
   email/password account you used above.
2. Mark it verified. Either:
   - sign in once on a device/simulator and click the verification link sent to
     that inbox, **or**
   - set `emailVerified = true` via the Firebase Admin SDK / a quick script, **or**
   - use an inbox you control for the demo email and click the link.
3. Confirm it lands on the dashboard (not the "Verify your email" screen).

## Reminders before submitting

- Enable **Apple** as a sign-in provider in Firebase Auth, and turn on the
  **Sign in with Apple** capability for the App ID (see the auth work).
- Attach the **Monthly** and **Lifetime** IAPs to this app version and submit
  them **with** the build, mapped to the "Vaultie Pro" entitlement in RevenueCat,
  or the reviewer's purchase attempt will fail.
- Set the **Privacy Policy URL** to the hosted `docs/privacy.html`, and provide a
  **Terms of Use (EULA) URL** (hosted `docs/terms.html` or Apple's standard EULA).
- Fill in the App Privacy "nutrition label" to match `PrivacyInfo.xcprivacy` and
  `privacy.html`: **Email** (app functionality), **Purchases** (RevenueCat), and
  the favicon request to Google.
