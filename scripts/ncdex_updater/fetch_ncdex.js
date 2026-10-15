const path = require('path');
const fs = require('fs');
const axios = require('axios');
const cheerio = require('cheerio');
const { initializeApp, cert, getApps } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

// 1. Firebase Authentication
let serviceAccount;
const keyPath = path.join(__dirname, 'serviceAccountKey.json');

if (process.env.FIREBASE_SERVICE_ACCOUNT) {
  try {
    let rawSecret = process.env.FIREBASE_SERVICE_ACCOUNT.trim();
    if (!rawSecret.startsWith('{') && !rawSecret.endsWith('}')) {
      rawSecret = Buffer.from(rawSecret, 'base64').toString('utf8');
    }
    serviceAccount = JSON.parse(rawSecret);
  } catch (err) {
    console.error('❌ Failed to parse FIREBASE_SERVICE_ACCOUNT secret:', err.message);
    process.exit(1);
  }
} else if (fs.existsSync(keyPath)) {
  serviceAccount = require(keyPath);
} else {
  console.error('❌ Error: serviceAccountKey.json not found locally and FIREBASE_SERVICE_ACCOUNT is empty.');
  process.exit(1);
}

if (getApps().length === 0) {
  initializeApp({
    credential: cert(serviceAccount),
    projectId: serviceAccount.project_id || 'mandi-market-view',
  });
}

const db = getFirestore();

// Commodities mapping
const WATCH_ITEMS = [
  { match: 'jeera', symbol: 'JEERAUNJHA' },
  { match: 'dhaniya', symbol: 'DHANIYA' },
  { match: 'coriander', symbol: 'DHANIYA' },
  { match: 'turmeric', symbol: 'TMCFGRNZM' },
  { match: 'isabgol', symbol: 'ISABGOL' },
  { match: 'guar seed', symbol: 'GUARSEED10' },
  { match: 'guar gum', symbol: 'GUARGUM5' },
  { match: 'chana', symbol: 'CHANA' },
  { match: 'castor', symbol: 'CASTOR' },
  { match: 'cotton seed', symbol: 'COK2' },
  { match: 'kapas', symbol: 'KAPAS' },
  { match: 'moong', symbol: 'MOONG' },
];

const BROWSER_HEADERS = {
  'User-Agent':
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
  'Accept':
    'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
  'Accept-Language': 'en-IN,en-GB;q=0.9,en;q=0.8',
  'Cache-Control': 'no-cache',
  'Pragma': 'no-cache',
};

function formatExpiry(raw) {
  if (!raw) return '';
  const clean = raw.replace(/-/g, ' ').trim();
  const match = clean.match(/^(\d{1,2})\s*([a-zA-Z]{3})\s*(\d{4})$/);
  if (match) {
    return `${match[1]} ${match[2].toUpperCase()} ${match[3]}`;
  }
  return clean.toUpperCase();
}

async function fetchRates() {
  const timestamp = new Date().toLocaleTimeString('en-IN', {
    timeZone: 'Asia/Kolkata',
  });
  console.log(`[${timestamp} IST] ⏳ Fetching live NCDEX quotes...`);

  const finalRates = [];
  const seen = new Set();

  // 1. Scrape Live Quotes Table (Futures)
  try {
    const res = await axios.get('https://www.ncdex.com/market-watch/live_quotes', {
      headers: BROWSER_HEADERS,
      timeout: 12000,
    });
    const $ = cheerio.load(res.data);

    $('table tr').each((_, row) => {
      const cols = $(row)
        .find('td')
        .map((_, el) => $(el).text().trim())
        .get();

      // Expected table layout: [0]=Product Name, [1]=Expiry Date, ..., [5]=Close/LTP or [6]=Change
      if (cols.length >= 7) {
        const prodName = cols[0].toLowerCase();
        const rawExpiry = cols[1];
        
        // Find numbers across columns (LTP and Change)
        // Extract all numeric tokens in the row
        const rowText = cols.join(' ');
        for (const item of WATCH_ITEMS) {
          if (prodName.includes(item.match)) {
            // Find LTP: typically in column 2, 3, or 4
            let ltp = parseFloat(cols[3]?.replace(/,/g, ''));
            if (isNaN(ltp) || ltp <= 0) {
              ltp = parseFloat(cols[4]?.replace(/,/g, ''));
            }
            if (isNaN(ltp) || ltp <= 0) {
              ltp = parseFloat(cols[2]?.replace(/,/g, ''));
            }

            const change = parseFloat(cols[5]?.replace(/,/g, '')) || 0;
            const formattedExpiry = formatExpiry(rawExpiry);
            const key = `${item.symbol}_${formattedExpiry}`;

            if (!isNaN(ltp) && ltp > 0 && !seen.has(key)) {
              finalRates.push({
                symbol: item.symbol,
                expiry: formattedExpiry,
                ltp: Math.round(ltp),
                change: Math.round(change),
              });
              seen.add(key);
            }
          }
        }
      }
    });
  } catch (err) {
    console.warn('⚠️ Live quotes table warning:', err.message);
  }

  // 2. Scrape Live Spot Table (Spot prices for Unjha, Jodhpur, etc.)
  try {
    const spotRes = await axios.get('https://www.ncdex.com/markets/livespot', {
      headers: BROWSER_HEADERS,
      timeout: 10000,
    });
    const $spot = cheerio.load(spotRes.data);

    $spot('table tr').each((_, row) => {
      const cols = $spot(row)
        .find('td')
        .map((_, el) => $spot(el).text().trim())
        .get();
      if (cols.length < 6) return;

      const prodName = cols[0].toLowerCase();
      const location = cols[2] ? cols[2].toUpperCase().trim() : 'SPOT';
      const spotPrice = parseFloat(cols[5].replace(/,/g, ''));
      const pctChange = cols.length > 6 ? parseFloat(cols[6].replace(/,/g, '')) : 0;

      if (isNaN(spotPrice) || spotPrice <= 0) return;

      for (const item of WATCH_ITEMS) {
        const alreadyHasFuture = finalRates.some((r) => r.symbol === item.symbol);
        if (
          (!alreadyHasFuture || item.symbol === 'ISABGOL' || item.symbol === 'CHANA' || item.symbol === 'MOONG') &&
          prodName.includes(item.match)
        ) {
          const key = `${item.symbol}_SPOT_${location}`;
          if (!seen.has(key)) {
            const estChange = !isNaN(pctChange)
              ? Math.round((spotPrice * pctChange) / 100)
              : 0;
            finalRates.push({
              symbol: item.symbol,
              expiry: `SPOT ${location}`,
              ltp: Math.round(spotPrice),
              change: estChange,
            });
            seen.add(key);
          }
        }
      }
    });
  } catch (spotErr) {
    console.warn('⚠️ Spot quotes warning:', spotErr.message);
  }

  // 3. Fallback: Parse Raw HTML table text if specific structures change
  if (finalRates.length === 0) {
    try {
      const spotRes = await axios.get('https://www.ncdex.com/markets/livespot', {
        headers: BROWSER_HEADERS,
        timeout: 10000,
      });
      const rawText = spotRes.data.toString();
      // Regex for row: Jeera | Location | Date | Price | Percentage
      const rowPattern = /(Jeera|Isabgol|Guar seed|Guar Gum|Dhaniya|Chana|Castor Seed)\s*\|\s*([^|]+)\|\s*([A-Za-z0-9\s:]+)\|\s*([\d,]+\.?\d*)\s*\|\s*([-\d.]+)/gi;
      let m;
      while ((m = rowPattern.exec(rawText)) !== null) {
        const commodity = m[1].toLowerCase();
        const loc = m[2].trim().toUpperCase();
        const price = parseFloat(m[4].replace(/,/g, ''));
        const pct = parseFloat(m[5]);

        for (const item of WATCH_ITEMS) {
          if (commodity.includes(item.match)) {
            const key = `${item.symbol}_SPOT_${loc}`;
            if (!seen.has(key) && !isNaN(price) && price > 0) {
              finalRates.push({
                symbol: item.symbol,
                expiry: `SPOT ${loc}`,
                ltp: Math.round(price),
                change: !isNaN(pct) ? Math.round((price * pct) / 100) : 0,
              });
              seen.add(key);
            }
          }
        }
      }
    } catch (_) {}
  }

  // 4. Update Firestore
  if (finalRates.length > 0) {
    try {
      await db.collection('market_watch').doc('live_summary').set({
        rates: finalRates,
        updatedAt: FieldValue.serverTimestamp(),
      });
      console.log(`✅ SUCCESS: Synced ${finalRates.length} contracts to Firestore!`);
      finalRates.forEach((r) => {
        const sign = r.change >= 0 ? `+${r.change}` : `${r.change}`;
        console.log(`   📊 ${r.symbol} (${r.expiry}) -> ₹${r.ltp} (${sign})`);
      });
    } catch (dbErr) {
      console.error('❌ Firestore sync error:', dbErr.message);
    }
  } else {
    console.log('ℹ️ No rates parsed this run; existing Firestore data retained.');
  }
}

function isMarketHours() {
  const istDate = new Date(
    new Date().toLocaleString('en-US', { timeZone: 'Asia/Kolkata' })
  );
  const day = istDate.getDay();
  if (day === 0 || day === 6) return false;
  const hour = istDate.getHours();
  return hour >= 9 && hour < 17;
}

async function run() {
  const isForced = process.argv.includes('--force');
  await fetchRates();

  if (!isForced && !isMarketHours()) {
    console.log('ℹ️ Market closed (09:00 AM - 05:00 PM IST). Single run complete.');
    process.exit(0);
  }

  let ticks = 0;
  const interval = setInterval(async () => {
    ticks++;
    if (ticks >= 5 || (!isForced && !isMarketHours())) {
      clearInterval(interval);
      console.log('🏁 Batch run finished.');
      process.exit(0);
    }
    await fetchRates();
  }, 45 * 1000);
}

run();
