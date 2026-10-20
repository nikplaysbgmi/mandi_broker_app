const admin = require('firebase-admin');
const puppeteer = require('puppeteer');

// Helper to filter contracts strictly to the current or future months
function isCurrentOrFutureMonth(expiryStr) {
  if (!expiryStr || typeof expiryStr !== 'string') return true;

  const clean = expiryStr.trim().toUpperCase();
  const monthMap = {
    'JAN': 0, 'FEB': 1, 'MAR': 2, 'APR': 3, 'MAY': 4, 'JUN': 5,
    'JUL': 6, 'AUG': 7, 'SEP': 8, 'OCT': 9, 'NOV': 10, 'DEC': 11
  };

  const now = new Date();
  const currentYear = now.getFullYear();
  const currentMonth = now.getMonth(); // 0-indexed

  // Match: "20-NOV-2026", "NOV 2026", "20 NOV 26"
  const match = clean.match(/(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)[a-z]*[\s\-_]*(\d{2,4})/i);
  if (match) {
    const month = monthMap[match[1].toUpperCase()];
    let year = parseInt(match[2], 10);
    if (year < 100) year += 2000;

    if (year > currentYear) return true;
    if (year === currentYear && month >= currentMonth) return true;
    return false;
  }

  // Fallback match: DD-MM-YYYY or MM-YYYY
  const numMatch = clean.match(/(\d{1,2})[\/\-](\d{2,4})/);
  if (numMatch) {
    let month = parseInt(numMatch[1], 10) - 1;
    let year = parseInt(numMatch[2], 10);
    if (year < 100) year += 2000;

    if (year > currentYear) return true;
    if (year === currentYear && month >= currentMonth) return true;
    return false;
  }

  return true;
}

async function run() {
  console.log('🚀 [NCDEX Scraper] Starting live sync for current & future months...');

  if (!process.env.FIREBASE_SERVICE_ACCOUNT) {
    console.error('❌ FATAL: FIREBASE_SERVICE_ACCOUNT secret missing!');
    process.exit(1);
  }

  try {
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
    console.log(`📡 Connected to Firebase Project: ${serviceAccount.project_id}`);

    if (admin.apps.length === 0) {
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
      });
    }
  } catch (err) {
    console.error('❌ Failed to parse FIREBASE_SERVICE_ACCOUNT JSON:', err.message);
    process.exit(1);
  }

  const db = admin.firestore();

  // Launch Puppeteer with stable Ubuntu runner flags (removed crashpad-inducing flags)
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

    console.log('⏳ Waiting for table rows...');
    await page.waitForSelector('table tbody tr', { timeout: 45000 });
    await new Promise(r => setTimeout(r, 2000));

    // Extract table rows
    const rawRecords = await page.evaluate(() => {
      const rows = Array.from(document.querySelectorAll('table tbody tr'));
      const parsed = [];

      for (const row of rows) {
        const cells = Array.from(row.querySelectorAll('td')).map(c => c.innerText.trim());
        if (cells.length < 5) continue;

        const symbol = cells[0] || '';
        const expiry = cells[1] || '';
        const open = cells[2] || '';
        
        let ltp = '';
        let high = '';
        let low = '';
        let change = '';
        let changePercent = '';
        let volume = '';

        if (cells.length >= 10) {
          low = cells[3] || '';
          ltp = cells[4] || cells[3] || '';
          high = cells[5] || '';
          change = cells[7] || '';
          changePercent = cells[8] || '';
          volume = cells[12] || cells[11] || '';
        } else {
          const midParts = (cells[3] || '').split(/\s+/);
          if (midParts.length === 3) {
            low = midParts[0];
            ltp = midParts[1];
            high = midParts[2];
          } else {
            ltp = cells[3] || cells[2] || '';
          }
          change = cells[5] || '';
          volume = cells[6] || '';
        }

        if (symbol && symbol !== 'Product Name/Symbol') {
          parsed.push({
            symbol: symbol,
            commodity: symbol,
            expiry: expiry,
            open: open.replace(/,/g, ''),
            high: high.replace(/,/g, ''),
            low: low.replace(/,/g, ''),
            lastPrice: ltp.replace(/,/g, ''),
            ltp: ltp.replace(/,/g, ''),
            change: change.replace(/,/g, ''),
            changePercent: changePercent.replace(/%/g, '').trim(),
            volume: volume.replace(/,/g, '')
          });
        }
      }

      return parsed;
    });

    // Filter strictly to current and future month contracts
    const filteredRecords = rawRecords.filter(item => isCurrentOrFutureMonth(item.expiry));

    console.log(`📊 Extracted: ${rawRecords.length} total | Filtered (Current & Future): ${filteredRecords.length}`);

    // Update Firestore market_watch/live_summary
    console.log('💾 Writing data to Firestore: market_watch/live_summary...');
    const nowTimestamp = admin.firestore.FieldValue.serverTimestamp();

    await db.collection('market_watch').doc('live_summary').set({
      commodities: filteredRecords,
      rates: filteredRecords,
      last_updated: nowTimestamp,
      updatedAt: nowTimestamp,
      status: 'active',
      source: 'NCDEX'
    }, { merge: true });

    console.log('✅ Successfully updated Firestore with current & future month contracts!');
  } catch (err) {
    console.error('❌ Scraper error:', err.message);
    process.exit(1);
  } finally {
    await browser.close();
  }
}

run();
