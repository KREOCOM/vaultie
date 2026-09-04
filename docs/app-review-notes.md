# App Store Connect — App Review Notes

> ⚠️ This file contains the demo account password. It is a throwaway account with
> sample data only — no bank access, no real money, no privileges — but do not
> publish this repository without stripping it.

Copy the block below into **App Store Connect → your app version → App Review Information → Notes**.
Fill the three bracketed fields first.

---

Vaultie is a personal finance app for the EU market. It reads a user's own bank
accounts (read-only) to detect recurring payments and show where their money goes.

**Bank access / licensing**
Vaultie is not a licensed payment institution and never sees a user's bank
credentials. Account access is provided by **Enable Banking**, a licensed Account
Information Service Provider (AISP) operating under PSD2. The user authenticates
on their own bank's page; Vaultie receives read-only account information after
explicit consent, which the bank limits to 90 days. Vaultie cannot move money or
make payments.

The service is operated by **MB Živitoma** (company number 304754869, Vytauto g.
118-4, LT-00153 Palanga, Lithuania), which holds the agreement with Enable Banking.

**Demo account**
Email: appreview@vaultieapp.com
Password: Forappleteam2016

**How to review without a real bank account**
Connecting a real bank requires an account at a European bank and that bank's own
two-factor authentication, which we cannot provide to a reviewer.

Signing in with the demo account above opens **directly into a fully populated
dashboard** using sample data — no purchase, no bank connection, no email
verification needed. Every screen can be reviewed there: Overview with spending
by category, the home feed, recurring subscriptions and bills, the AI assistant,
budgets, and Settings including account deletion.

This is the demo mode described in Guideline 2.1: it exhibits the app's full
features and functionality.

**Subscription**
Vaultie is subscription-only (Vaultie Pro, monthly or yearly, auto-renewing).
Price, billing period, renewal terms and links to the Terms of Use and Privacy
Policy are shown on the purchase screen before any purchase, together with a
Restore Purchases control. Both documents are also reachable from Settings.

**Account deletion**
Settings → Account → Delete account removes the Firebase account and erases all
local data on the device, per guideline 5.1.1(v).

**Data handling**
Bank transactions are processed transiently in Cloud Functions (EU region,
europe-west1) and are never stored server-side. Only what the user chooses to keep
is saved, on their own device.

---

## Checklist before submitting

- [x] **`appreview@vaultieapp.com` created in Firebase → Authentication → Users**
      (uid 6X4ktnyRMKOTCZSCr0NDdehQPbt2). `lib/services/review_account.dart` matches
      this exact address; the app treats this one account as verified without a
      real mailbox check.
- [x] Account created; password recorded above
- [ ] Verify the demo account signs in and reaches the dashboard on a clean
      install of the **release** build — this is the one path a reviewer walks
- [ ] No Pro grant needed: the demo account bypasses the paywall by design
- [ ] App Privacy questionnaire filled in App Store Connect (data collected: email,
      purchase history, crash data, financial info — all linked to the user)
- [ ] Screenshots uploaded for every required device size
- [ ] `kPreviewOnboarding` is release-safe — already tied to `!kReleaseMode`, no
      manual step needed
- [ ] Build is **release**, not profile or debug

## About the Enable Banking contract

Do NOT attach it unprompted. The notes already state, truthfully, that the
service is operated by MB Živitoma and that access runs through Enable Banking as
the licensed AISP. Volunteering a contract whose counterparty name differs from
the Apple developer account invites the question it is meant to answer.

Keep it to hand. If App Review asks for documentation of the banking permission
— which they may, for a regulated field — send it then, with one line explaining
that MB Živitoma is wholly owned by the developer and operates the service.

## If rejected under Guideline 3.2.1(viii)

That guideline says money-management apps "should be submitted by the financial
institution performing such services" and by "the legal entity… rather than an
individual developer". The counter-argument, stated plainly: Vaultie performs no
financial service. It moves no money, lends nothing, invests nothing. It reads
account information, read-only, through a licensed AISP.

If it is rejected on that ground anyway, the fix is an Organization developer
account, which needs a D-U-N-S number for MB Živitoma. That takes days. Start the
D-U-N-S request now, in parallel — it is free, and having it means a rejection
costs a resubmission instead of a fortnight.
