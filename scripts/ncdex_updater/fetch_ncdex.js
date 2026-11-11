const admin = require('firebase-admin');
const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

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
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());

  const match = clean.match(/(?:(\d{1,2})[\s\-_]+)?(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)[a-z]*(?:[\s\-_]+(\d{2,4}))?/i);
  if (match) {
    const day = match[1] ? parseInt(match[1], 10) : 20; // Default expiry day is 20th
    const m = monthMap[match[2].toUpperCase()] ?? 0;
    let y = match[3] ? parseInt(match[3], 10) : now.getFullYear();
    if (y < 100) y += 2000;

    // Contract expires at 23:59:59 on the expiry day (e.g. 20th)
    const expiryDate = new Date(y, m, day, 23, 59, 59);
    return expiryDate >= todayStart;
  }
  return true;
}

function getExpirySortKey(expiryStr) {
  if (!expiryStr || typeof expiryStr !== 'string') return 99999999;
  const clean = expiryStr.trim().toUpperCase();
  const monthMap = {
    'JAN': 1, 'FEB': 2, 'MAR': 3, 'APR': 4, 'MAY': 5, 'JUN': 6,
    'JUL': 7, 'AUG': 8, 'SEP': 9, 'OCT': 10, 'NOV': 11, 'DEC': 12
  };
  const match = clean.match(/(?:(\d{1,2})[\s\-_]+)?(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)[a-z]*(?:[\s\-_]+(\d{2,4}))?/i);
  if (match) {
    const day = match[1] ? parseInt(match[1], 10) : 1;
    const month = monthMap[match[2].toUpperCase()] || 1;
    let year = match[3] ? parseInt(match[3], 10) : new Date().getFullYear();
    if (year < 100) year += 2000;
    return year * 10000 + month * 100 + day;
  }
  return 99999999;
}

function initFirebase() {
  const apps = admin.apps || (admin.getApps ? admin.getApps() : []);
  if (apps.length > 0) {
    return (admin.firestore ? admin.firestore() : require('firebase-admin/firestore').getFirestore());
  }

  let serviceAccount;
  if (process.env.FIREBASE_SERVICE_ACCOUNT) {
    try {
      serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
    } catch (err) {
      console.error('❌ Service Account parse error:', err.message);
      process.exit(1);
    }
  } else {
    try {
      const keyPath = path.join(__dirname, 'serviceAccountKey.json');
      if (fs.existsSync(keyPath)) {
        serviceAccount = require(keyPath);
        console.log('🔑 Loaded credentials from local serviceAccountKey.json');
      } else {
        console.error('❌ FATAL: FIREBASE_SERVICE_ACCOUNT environment variable and serviceAccountKey.json are both missing!');
        process.exit(1);
      }
    } catch (e) {
      console.error('❌ Error reading local serviceAccountKey.json:', e.message);
      process.exit(1);
    }
  }

  try {
    const certFn = admin.cert || (admin.credential && admin.credential.cert);
    admin.initializeApp({
      credential: certFn(serviceAccount)
    });
    return (admin.firestore ? admin.firestore() : require('firebase-admin/firestore').getFirestore());
  } catch (err) {
    console.error('❌ Firebase Admin init error:', err.message);
    process.exit(1);
  }
}

async function scrapeOnce(db) {
  console.log(`\n⏰ [${new Date().toLocaleTimeString('en-IN')}] Launching browser for NCDEX live quotes...`);

  let browser;
  try {
    browser = await puppeteer.launch({
      headless: true,
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-gpu',
        '--window-size=1366,768'
      ]
    });

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

    // Map: commodity display -> Map of (expiry -> entry)
    const commodityContractsMap = new Map();

    for (const cells of tableData) {
      const rawProduct = (cells[0] || '').toUpperCase();
      const expiry = (cells[1] || '').trim();

      if (!isCurrentOrFutureExpiry(expiry)) continue;

      const matched = COMMODITY_CONFIG.find(item =>
        item.patterns.some(pat => rawProduct.includes(pat))
      );

      if (!matched) continue;

      let ltp = '0';
      let change = '0';

      if (cells.length >= 6) {
        const lowLtpHigher = (cells[3] || '').replace(/,/g, '').split(/\s+/);
        if (lowLtpHigher.length >= 2) {
          ltp = lowLtpHigher.length === 3 ? lowLtpHigher[1] : lowLtpHigher[0];
        } else {
          ltp = (cells[3] || cells[2] || '0').replace(/,/g, '');
        }
        change = (cells[5] || '0').replace(/,/g, '');
      }

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

      if (!commodityContractsMap.has(matched.display)) {
        commodityContractsMap.set(matched.display, new Map());
      }
      const expMap = commodityContractsMap.get(matched.display);
      if (!expMap.has(expiry) || (cleanPrice !== '0' && expMap.get(expiry).lastPrice === '0')) {
        expMap.set(expiry, entry);
      }
    }

    // Capture both near month (e.g. November) and next month (+1 month, e.g. December) contracts
    const finalList = [];
    for (const item of COMMODITY_CONFIG) {
      if (!commodityContractsMap.has(item.display)) continue;
      const contracts = Array.from(commodityContractsMap.get(item.display).values());
      // Sort chronologically: near month first, next month second
      contracts.sort((a, b) => getExpirySortKey(a.expiry) - getExpirySortKey(b.expiry));

      // Keep up to 2 active future contracts (near month + 1 month forward e.g. Nov and Dec)
      const topContracts = contracts.slice(0, 2);
      topContracts.forEach((c, idx) => {
        c.monthIndex = idx;
        c.monthType = idx === 0 ? 'NEAR' : 'NEXT';
        finalList.push(c);
      });
    }

    console.log(`✅ Formatted ${finalList.length} active contracts.`);

    const FieldValue = (admin.firestore && admin.firestore.FieldValue)
      ? admin.firestore.FieldValue
      : require('firebase-admin/firestore').FieldValue;
    const now = FieldValue.serverTimestamp();
    await db.collection('market_watch').doc('live_summary').set({
      commodities: finalList,
      rates: finalList,
      last_updated: now,
      updatedAt: now,
      status: 'active',
      source: 'NCDEX'
    }, { merge: true });

    console.log('🎉 Successfully saved full commodity list to Firestore!');
    return true;
  } catch (err) {
    console.error('⚠️ Scrape cycle error (will retry next interval):', err.message);
    return false;
  } finally {
    if (browser) {
      try {
        await browser.close();
      } catch (_) {}
    }
  }
}

async function main() {
  console.log('🚀 [NCDEX Continuous Loop Scraper] Starting service...');
  const db = initFirebase();

  // Loop configuration: 8 cycles spaced 3 minutes apart = ~25 minutes per GitHub Actions run
  const TOTAL_CYCLES = 8;
  const DELAY_MINUTES = 3;

  for (let cycle = 1; cycle <= TOTAL_CYCLES; cycle++) {
    console.log(`\n========================================`);
    console.log(`🔄 [Cycle ${cycle}/${TOTAL_CYCLES}] Live NCDEX Scrape`);
    console.log(`========================================`);

    await scrapeOnce(db);

    if (cycle < TOTAL_CYCLES) {
      console.log(`⏳ Sleeping ${DELAY_MINUTES} minutes before next automatic scrape...`);
      await new Promise(r => setTimeout(r, DELAY_MINUTES * 60 * 1000));
    }
  }

  console.log('\n🏁 [NCDEX Continuous Loop] Completed all cycles for this run.');
  process.exit(0);
}

main();
