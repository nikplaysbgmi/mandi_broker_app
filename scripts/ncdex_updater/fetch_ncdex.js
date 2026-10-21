const admin = require('firebase-admin');
const puppeteer = require('puppeteer');

// Core commodities tracked in the app UI
const TARGET_COMMODITIES = [
  { key: 'JEERAUNJHA', patterns: ['JEERA', 'JEERAUNJHA'] },
  { key: 'DHANIYA', patterns: ['DHANIYA', 'CORIANDER'] },
  { key: 'TMCFGRNZM', patterns: ['TMCFGRNZM', 'TURMERIC'] },
  { key: 'ISABGOL', patterns: ['ISABGOL', 'PSYLLIUM'] },
  { key: 'FENNEL', patterns: ['FENNEL', 'SAUNF'] },
  { key: 'FENUGREEK', patterns: ['FENUGREEK', 'METHI'] },
  { key: 'GUARSEED10', patterns: ['GUARSEED', 'GUARSEED10'] },
  { key: 'GUARGUM5', patterns: ['GUARGUM', 'GUARGUM5'] },
  { key: 'CHANA', patterns: ['CHANA', 'GRAM'] },
  { key: 'CASTOR', patterns: ['CASTOR', 'CASTORSEED'] },
  { key: 'SOYABEAN', patterns: ['SOYABEAN', 'SOYBEAN'] },
  { key: 'MUSTARD', patterns: ['MUSTARD', 'RMSEED'] }
];

async function run() {
  console.log('🚀 [NCDEX Scraper] Starting fetch for MarketWatch view...');

  if (!process.env.FIREBASE_SERVICE_ACCOUNT) {
    console.error('❌ FIREBASE_SERVICE_ACCOUNT missing!');
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
    console.error('❌ Service account parse error:', err.message);
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

    console.log('🌐 Loading NCDEX Live Quotes...');
    await page.goto('https://www.ncdex.com/market-watch/live_quotes', {
      waitUntil: 'domcontentloaded',
      timeout: 60000
    });

    await page.waitForSelector('table tbody tr', { timeout: 45000 });
    await new Promise(r => setTimeout(r, 2500));

    // Scrape all table rows
    const scrapedRows = await page.evaluate(() => {
      const rows = Array.from(document.querySelectorAll('table tbody tr'));
      return rows.map(r => {
        const cells = Array.from(r.querySelectorAll('td')).map(c => c.innerText.trim());
        return cells;
      }).filter(c => c.length >= 4);
    });

    console.log(`📊 Total raw rows scraped: ${scrapedRows.length}`);

    // Map rows to our target commodities, prioritizing the near month with actual trades
    const commodityMap = new Map();

    for (const cells of scrapedRows) {
      const rawSymbol = (cells[0] || '').toUpperCase();
      const expiry = cells[1] || '';

      // Find which target commodity this matches
      const target = TARGET_COMMODITIES.find(t =>
        t.patterns.some(p => rawSymbol.includes(p))
      );

      if (!target) continue;

      // Extract price fields across different NCDEX column variations
      let ltp = '0';
      let change = '0';

      if (cells.length >= 10) {
        // [Symbol, Expiry, Open, Low, LTP, High, Close, Change, %Change, ...]
        ltp = cells[4] || cells[3] || '0';
        change = cells[7] || cells[6] || '0';
      } else {
        // Grouped column format
        const combined = (cells[3] || '').split(/\s+/);
        ltp = combined.length >= 2 ? combined[1] : (cells[3] || '0');
        change = cells[5] || '0';
      }

      ltp = ltp.replace(/,/g, '').trim();
      change = change.replace(/,/g, '').trim();

      // Ensure valid numbers
      const numLtp = parseFloat(ltp);
      const numChange = parseFloat(change);

       const entry = {
        symbol: target.key,
        name: target.key,
        expiry: expiry,       // Exact date from NCDEX table (e.g., '20 NOV 2026')
        contract: expiry,     // Replaces static 'NEAR' with the actual date
        lastPrice: isNaN(numLtp) ? '0' : numLtp.toFixed(0),
        ltp: isNaN(numLtp) ? '0' : numLtp.toFixed(0),
        change: isNaN(numChange) ? '+0' : (numChange >= 0 ? `+${numChange.toFixed(0)}` : `${numChange.toFixed(0)}`),
        isPositive: !isNaN(numChange) && numChange >= 0
      };

      // If we haven't stored this commodity yet, or if this row has an active price (> 0) while the stored one is 0
      if (!commodityMap.has(target.key) || (numLtp > 0 && parseFloat(commodityMap.get(target.key).lastPrice) === 0)) {
        commodityMap.set(target.key, entry);
      }
    }

    // Build the ordered list matching the reference image order
    const finalList = TARGET_COMMODITIES
      .filter(t => commodityMap.has(t.key))
      .map(t => commodityMap.get(t.key));

    console.log(`✅ Ready to save ${finalList.length} near-month commodity cards.`);

    const now = admin.firestore.FieldValue.serverTimestamp();
    await db.collection('market_watch').doc('live_summary').set({
      commodities: finalList,
      rates: finalList,
      last_updated: now,
      updatedAt: now,
      status: 'active'
    }, { merge: true });

    console.log('🎉 Successfully saved to Firestore market_watch/live_summary!');
  } catch (err) {
    console.error('❌ Error during run:', err.message);
    process.exit(1);
  } finally {
    await browser.close();
  }
}

run();
