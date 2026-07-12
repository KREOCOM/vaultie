# Preview data generator

Computes the Bilance-style Dashboard preview data (`lib/screens/preview/dashboard_preview.dart`)
from the user's real Revolut export. DEMO/preview only — production uses the committed resolver.

## Pipeline
1. `python3 gen_dash.py` — classifies all transactions (see `classify()`), builds months/week/subs/
   spark/all/budgets, runs a **consistency self-test** (category-sum==net, day-sum==net), writes
   `dash_data.json`. Input: `~/banksync-test/revolut_txns.json`.
2. Balance series (reconstructed backwards from current balance) + accounts are folded into
   `dash_data.json` (see the balance block — reconstruct daily balance, anchor last day = current).
3. The JSON is base64-encoded and injected into `dashboard_preview.dart` at `const String _dashB64`.

## Key logic (data-signal based, generalises)
- `bank_transaction_code`: EXCHANGE = currency conversion → TRANSFER (never income); TOPUP/P2P →
  transfer; loans (Mogo) → Finansai; CARD_CREDIT/REFUND → income (refund).
- MCC=0% → categories are best-effort keyword guesses; fuel stations split by amount (flagged).
- Savings % = net / total-money-in (income alone understates it across currencies).

## Production TODO
Replace demo classifier with the committed resolver; wire live Enable Banking data + balances
endpoint; multi-currency (settings base currency EUR/NOK/USD; each account has a currency).
