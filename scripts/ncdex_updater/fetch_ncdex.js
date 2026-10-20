const admin = require('firebase-admin');
const puppeteer = require('puppeteer');

async function scrape() {
  if (!process.env.FIREBASE_SERVICE_ACCOUNT) {
    console.error('FIREBASE_SERVICE_ACCOUNT secret is missing.');
    process.exit(1);
  }

  const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
  const db = admin.firestore();

  console.log('Launching headless browser...');
  const browser = await puppeteer.launch({
    headless: 'new',
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu',
      '--single-process'
    ]
  });

  try {
    const page = await browser.newPage();

    // Block heavy assets (images, stylesheets, fonts) to speed up loading
    await page.setRequestInterception(true);
    page.on('request', (req) => {
      const type = req.resourceType();
      if (['image', 'stylesheet', 'font', 'media'].includes(type)) {
        req.abort();
      } else {
        req.continue();
      }
    });

    await page.setUserAgent(
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
    );

    console.log('Loading NCDEX URL...');
    // Use domcontentloaded so background scripts don't cause infinite hangs
    await page.goto('https://www.ncdex.com/market-watch/live_quotes', {
      waitUntil: 'domcontentloaded',
      timeout: 30000
    });

    console.log('Waiting for live table...');
    await page.waitForSelector('table tbody tr', { timeout: 20000 });

    const data = await page.evaluate(() => {
      const rows = Array.from(document.querySelectorAll('table tbody tr'));
      return rows.map(r => {
        const cells = Array.from(r.querySelectorAll('td')).map(c => c.innerText.trim());
        return {
          symbol: cells[0] || '',
          expiry: cells[1] || '',
          open: cells[2] || '',
          high: cells[3] || '',
          low: cells[4] || '',
          lastPrice: cells[5] || '',
          change: cells[6] || '',
          volume: cells[7] || ''
        };
      }).filter(item => item.symbol !== '');
    });

    console.log(`Parsed ${data.length} commodity rows.`);

    await db.collection('market_watch').doc('live_summary').set({
      commodities: data,
      last_updated: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    console.log('Firestore write complete.');
  } catch (err) {
    console.error('Scraping error:', err.message);
    process.exit(1);
  } finally {
    await browser.close();
    // Force Node process to terminate immediately so GitHub Actions does not hang
    process.exit(0);
  }
}

scrape();
