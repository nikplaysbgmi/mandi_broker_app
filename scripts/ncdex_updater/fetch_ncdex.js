const admin = require('firebase-admin');
const puppeteer = require('puppeteer');

async function main() {
  console.log('--- Starting NCDEX Live Rate Sync ---');

  // 1. Verify and Initialize Firebase
  if (!process.env.FIREBASE_SERVICE_ACCOUNT) {
    console.error('❌ Error: FIREBASE_SERVICE_ACCOUNT secret is missing from environment.');
    process.exit(1);
  }

  try {
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
    console.log(`📡 Connecting to Firebase Project: ${serviceAccount.project_id}`);

    if (admin.apps.length === 0) {
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
      });
    }
  } catch (err) {
    console.error('❌ Error parsing FIREBASE_SERVICE_ACCOUNT JSON:', err.message);
    process.exit(1);
  }

  const db = admin.firestore();

  // 2. Launch Puppeteer
  const browser = await puppeteer.launch({
    headless: 'new',
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu'
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

    console.log('⏳ Waiting for commodity table to populate...');
    await page.waitForSelector('table', { timeout: 45000 });

    // 3. Extract Contract Rows
    const data = await page.evaluate(() => {
      const rows = Array.from(document.querySelectorAll('table tbody tr'));
      return rows.map(r => {
        const cells = Array.from(r.querySelectorAll('td')).map(c => c.innerText.trim());
        if (cells.length < 3) return null;
        return {
          symbol: cells[0] || '',
          expiry: cells[1] || '',
          open: cells[2] || '',
          high: cells[3] || '',
          low: cells[4] || '',
          lastPrice: cells[5] || cells[2] || '',
          change: cells[6] || '',
          volume: cells[7] || ''
        };
      }).filter(item => item !== null && item.symbol !== '');
    });

    console.log(`📊 Extracted ${data.length} commodity records from NCDEX.`);

    // 4. Update Firestore market_watch/live_summary
    console.log('💾 Writing data to Firestore: market_watch/live_summary...');
    const now = admin.firestore.FieldValue.serverTimestamp();

    await db.collection('market_watch').doc('live_summary').set({
      commodities: data,
      rates: data,
      last_updated: now,
      updatedAt: now,
      status: 'active'
    }, { merge: true });

    console.log('✅ Successfully updated Firestore!');
  } catch (err) {
    console.error('❌ Scrape execution error:', err.message);
    process.exit(1);
  } finally {
    await browser.close();
  }
}

main();
