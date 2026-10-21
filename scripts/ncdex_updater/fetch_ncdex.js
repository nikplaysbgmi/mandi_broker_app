const admin = require('firebase-admin');
const puppeteer = require('puppeteer');

// Full list of agricultural commodities traded on NCDEX
const COMMODITY_CONFIG = [
  { display: 'JEERAUNJHA', patterns: ['JEERA'] },
  { display: 'TMCFGRNZM', patterns: ['TURMERIC', 'TMCFGRNZM'] },
  { display: 'GUARSEED10', patterns: ['GUAR SEED', 'GUARSEED'] },
  { display: 'GUARGUM5', patterns: ['GUAR GUM', 'GUARGUM'] },
  { display: 'COKUDL', patterns: ['COTTON SEED OILCAKE', 'COKUDL', 'KAPAS KHAL'] },
  { display: 'CASTOR', patterns: ['CASTOR SEED', 'CASTOR'] },
  { display: 'CHANA', patterns: ['CHANA', 'GRAM'] },
];

function isCurrentOrFutureExpiry(expiryStr) {
  if (!expiryStr || typeof expiryStr !== 'string') return true;
  const clean = expiryStr.trim().toUpperCase();

  const monthMap = {
    'JAN': 0, 'FEB': 1, 'MAR': 2, 'APR': 3, 'MAY': 4, 'JUN': 5,
    'JUL': 6, 'AUG': 7, 'SEP': 8, 'OCT': 9, 'NOV': 10, 'DEC': 11
  };

  const now = new Date();
  const currentYear = now.getFullYear();
  const currentMonth = now.getMonth();

  const match = clean.match(/(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)[a-z]*[\s\-_]*(\d{2,4})/i);
  if (match) {
    const m = monthMap[match[1].toUpperCase()];
    let y = parseInt(match[2], 10);
    if (y < 100) y += 2000;
    if (y > currentYear) return true;
    if (y === currentYear && m >= currentMonth) return true;
    return false;
  }
  return true;
}

async function run() {
  console.log('🚀 [NCDEX Scraper] Starting live quote extraction...');

  if (!process.env.FIREBASE_SERVICE_ACCOUNT) {
    console.error('❌ FATAL: FIREBASE_SERVICE_ACCOUNT missing!');
    process.exit(1);
  }

  try {
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
    if (admin.apps.length === 0) {
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
      });
    }
  } catch (err) {
    console.error('❌ Service Account parse error:', err.message);
    process.exit(1);
  }

  const db = admin.firestore();

  const browser = await puppeteer.launch({
    headless: true,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu',
      '--window-size=1366,768'
    ]
  });

  try {
    const page = await browser.newPage();
    await page.setViewport({ width: 1366, height: 768 });
    await page.setUserAgent(
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
    );

    console.log('🌐 Loading NCDEX Live Quotes page...');
    await page.goto('https://www.ncdex.com/market-watch/live_quotes', {
      waitUntil: 'domcontentloaded',
      timeout: 60000
    });

    await page.waitForSelector('table tbody tr', { timeout: 45000 });
    await new Promise(r => setTimeout(r, 2500));

    // Scrape all table rows
    const tableData = await page.evaluate(() => {
      const rows = Array.from(document.querySelectorAll('table tbody tr'));
      return rows.map(r => {
        const cells = Array.from(r.querySelectorAll('td')).map(c => c.innerText.trim());
        return cells;
      }).filter(c => c.length >= 4);
    });

    console.log(`📊 Total table rows extracted: ${tableData.length}`);

    const commodityMap = new Map();

    for (const cells of tableData) {
      const rawProduct = (cells[0] || '').toUpperCase();
      const expiry = cells[1] || '';

      // Skip past months
      if (!isCurrentOrFutureExpiry(expiry)) continue;

      // Find matched target commodity
      const matched = COMMODITY_CONFIG.find(item =>
        item.patterns.some(pat => rawProduct.includes(pat))
      );

      if (!matched) continue;

      let ltp = '0';
      let change = '0';

      // Parse NCDEX columns: [Product, Expiry, Open, Low LTP High, Close, Change, ...]
      if (cells.length >= 6) {
        const lowLtpHigher = (cells[3] || '').replace(/,/g, '').split(/\s+/);
        if (lowLtpHigher.length >= 2) {
          // In 'Low LTP High', LTP is the middle element
          ltp = lowLtpHigher.length === 3 ? lowLtpHigher[1] : lowLtpHigher[0];
        } else {
          ltp = (cells[3] || cells[2] || '0').replace(/,/g, '');
        }

        // Change column is usually cell 5
        change = (cells[5] || '0').replace(/,/g, '');
      }

      // Cleanup numbers
      const numLtp = parseFloat(ltp);
      const numChange = parseFloat(change);

      const cleanPrice = (!isNaN(numLtp) && numLtp > 0) ? numLtp.toFixed(0) : '0';
      const cleanChange = isNaN(numChange)
        ? '+0'
        : (numChange >= 0 ? `+${numChange.toFixed(0)}` : `${numChange.toFixed(0)}`);

      const entry = {
        symbol: matched.display,
        name: matched.display,
        commodity: matched.display,
        expiry: expiry,
        contract: expiry,
        lastPrice: cleanPrice,
        ltp: cleanPrice,
        change: cleanChange,
        isPositive: !isNaN(numChange) && numChange >= 0
      };

      // Store near-month contract (first occurrence or one with a valid price)
      if (!commodityMap.has(matched.display) ||
         (cleanPrice !== '0' && commodityMap.get(matched.display).lastPrice === '0')) {
        commodityMap.set(matched.display, entry);
      }
    }

    // Build the ordered list preserving configured commodity order
    const finalList = COMMODITY_CONFIG
      .filter(item => commodityMap.has(item.display))
      .map(item => commodityMap.get(item.display));

    console.log(`✅ Formatted ${finalList.length} active commodities for MarketWatch.`);

    // Write to Firestore
    const now = admin.firestore.FieldValue.serverTimestamp();
    await db.collection('market_watch').doc('live_summary').set({
      commodities: finalList,
      rates: finalList,
      last_updated: now,
      updatedAt: now,
      status: 'active',
      source: 'NCDEX'
    }, { merge: true });

    console.log('🎉 Successfully saved full commodity list to Firestore!');
  } catch (err) {
    console.error('❌ Scraper runtime error:', err.message);
    process.exit(1);
  } finally {
    await browser.close();
  }
}

run();
