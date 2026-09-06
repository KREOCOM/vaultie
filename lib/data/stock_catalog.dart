/// Hand-picked ticker lists for the Investavimas tab's "add a holding" picker.
///
/// PROTOTYPE. Stock search is now LIVE (functions/stock_search.py → Finnhub,
/// covers any global stock, not just this list) — [kStockCatalog] below is
/// only the "Populiariausios" suggestions shown before the user types
/// anything, not a search limitation anymore.
///
/// [kCryptoCatalog] is still a hand-picked list, though, and stays one —
/// Finnhub's general /search endpoint doesn't return real crypto pairs for a
/// query like "bitcoin" (it returns bitcoin-THEMED STOCKS: GBTC, ABTC...,
/// verified directly), so there's no live crypto search to fall back to.
/// /quote itself DOES work fine for a crypto pair symbol (verified: BINANCE:
/// BTCUSDT returned a real live price) — only the search step needs this.
library;

class StockInfo {
  const StockInfo({required this.symbol, required this.name, required this.domain});

  /// Yahoo Finance's bare ticker (e.g. 'TSLA') — what stock_quote.py sends
  /// straight through to its chart endpoint, unmodified. 2026-08-28: was
  /// Stooq's 'tsla.us' format before the provider swap (Stooq started
  /// blocking datacenter requests) — see stock_quote.py's own doc.
  final String symbol;
  final String name;

  /// For the existing merchant-logo proxy (kMerchantLogoEndpoint) — the same
  /// mechanism CategoryIcon already uses for subscription brand logos, reused
  /// here rather than standing up a second logo pipeline for stocks.
  final String domain;
}

const kStockCatalog = <StockInfo>[
  StockInfo(symbol: 'TSLA', name: 'Tesla', domain: 'tesla.com'),
  StockInfo(symbol: 'AAPL', name: 'Apple', domain: 'apple.com'),
  StockInfo(symbol: 'MSFT', name: 'Microsoft', domain: 'microsoft.com'),
  StockInfo(symbol: 'GOOGL', name: 'Alphabet (Google)', domain: 'abc.xyz'),
  StockInfo(symbol: 'AMZN', name: 'Amazon', domain: 'amazon.com'),
  StockInfo(symbol: 'NVDA', name: 'Nvidia', domain: 'nvidia.com'),
  StockInfo(symbol: 'META', name: 'Meta (Facebook)', domain: 'meta.com'),
  StockInfo(symbol: 'NFLX', name: 'Netflix', domain: 'netflix.com'),
  StockInfo(symbol: 'DIS', name: 'Disney', domain: 'disney.com'),
  StockInfo(symbol: 'BA', name: 'Boeing', domain: 'boeing.com'),
  StockInfo(symbol: 'KO', name: 'Coca-Cola', domain: 'coca-cola.com'),
  StockInfo(symbol: 'NKE', name: 'Nike', domain: 'nike.com'),
  StockInfo(symbol: 'SBUX', name: 'Starbucks', domain: 'starbucks.com'),
  StockInfo(symbol: 'V', name: 'Visa', domain: 'visa.com'),
  StockInfo(symbol: 'MA', name: 'Mastercard', domain: 'mastercard.com'),
  StockInfo(symbol: 'JPM', name: 'JPMorgan Chase', domain: 'jpmorganchase.com'),
  StockInfo(symbol: 'PYPL', name: 'PayPal', domain: 'paypal.com'),
  StockInfo(symbol: 'AMD', name: 'AMD', domain: 'amd.com'),
  StockInfo(symbol: 'INTC', name: 'Intel', domain: 'intel.com'),
  StockInfo(symbol: 'ORCL', name: 'Oracle', domain: 'oracle.com'),
  StockInfo(symbol: 'IBM', name: 'IBM', domain: 'ibm.com'),
  StockInfo(symbol: 'ADBE', name: 'Adobe', domain: 'adobe.com'),
  StockInfo(symbol: 'CRM', name: 'Salesforce', domain: 'salesforce.com'),
  StockInfo(symbol: 'UBER', name: 'Uber', domain: 'uber.com'),
  StockInfo(symbol: 'ABNB', name: 'Airbnb', domain: 'airbnb.com'),
  StockInfo(symbol: 'SHOP', name: 'Shopify', domain: 'shopify.com'),
  StockInfo(symbol: 'SPOT', name: 'Spotify', domain: 'spotify.com'),
  StockInfo(symbol: 'SOFI', name: 'SoFi', domain: 'sofi.com'),
  StockInfo(symbol: 'PLTR', name: 'Palantir', domain: 'palantir.com'),
  StockInfo(symbol: 'COIN', name: 'Coinbase', domain: 'coinbase.com'),
  StockInfo(symbol: 'ASML', name: 'ASML', domain: 'asml.com'),
];

/// Finnhub's own crypto symbol format: 'EXCHANGE:PAIR' (Binance USDT pairs
/// here — the most liquid/commonly available quote pairing). Passed straight
/// through to stock_quote.py's quote(), unmodified, same as a stock symbol.
const kCryptoCatalog = <StockInfo>[
  StockInfo(symbol: 'BINANCE:BTCUSDT', name: 'Bitcoin', domain: 'bitcoin.org'),
  StockInfo(symbol: 'BINANCE:ETHUSDT', name: 'Ethereum', domain: 'ethereum.org'),
  StockInfo(symbol: 'BINANCE:SOLUSDT', name: 'Solana', domain: 'solana.com'),
  StockInfo(symbol: 'BINANCE:BNBUSDT', name: 'BNB', domain: 'bnbchain.org'),
  StockInfo(symbol: 'BINANCE:XRPUSDT', name: 'XRP', domain: 'ripple.com'),
  StockInfo(symbol: 'BINANCE:ADAUSDT', name: 'Cardano', domain: 'cardano.org'),
  StockInfo(symbol: 'BINANCE:DOGEUSDT', name: 'Dogecoin', domain: 'dogecoin.com'),
  StockInfo(symbol: 'BINANCE:DOTUSDT', name: 'Polkadot', domain: 'polkadot.network'),
  StockInfo(symbol: 'BINANCE:LTCUSDT', name: 'Litecoin', domain: 'litecoin.org'),
  StockInfo(symbol: 'BINANCE:AVAXUSDT', name: 'Avalanche', domain: 'avax.network'),
  StockInfo(symbol: 'BINANCE:LINKUSDT', name: 'Chainlink', domain: 'chain.link'),
  StockInfo(symbol: 'BINANCE:UNIUSDT', name: 'Uniswap', domain: 'uniswap.org'),
  StockInfo(symbol: 'BINANCE:ATOMUSDT', name: 'Cosmos', domain: 'cosmos.network'),
  StockInfo(symbol: 'BINANCE:SHIBUSDT', name: 'Shiba Inu', domain: 'shibatoken.com'),
  StockInfo(symbol: 'BINANCE:TRXUSDT', name: 'Tron', domain: 'trondao.org'),
];
