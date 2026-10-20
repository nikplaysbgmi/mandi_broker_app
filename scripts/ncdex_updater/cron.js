const { exec } = require('child_process');

function isMarketOpen() {
  const now = new Date();
  // UTC to IST (+5:30)
  const istOffset = 5.5 * 60 * 60 * 1000;
  const ist = new Date(now.getTime() + istOffset);
  const day = ist.getUTCDay(); // 0 = Sun, 6 = Sat
  const hours = ist.getUTCHours();
  const minutes = ist.getUTCMinutes();
  const currentMinute = hours * 60 + minutes;

  // Monday to Friday (1-5), 09:00 AM to 05:00 PM (540 to 1020 mins)
  return day >= 1 && day <= 5 && currentMinute >= 540 && currentMinute <= 1020;
}

function run() {
  if (isMarketOpen()) {
    console.log(`[${new Date().toLocaleTimeString('en-IN')}] Running NCDEX fetch...`);
    exec('node scripts/ncdex_updater/fetch_ncdex.js', (err, stdout, stderr) => {
      if (err) console.error(err);
      if (stdout) console.log(stdout);
    });
  } else {
    console.log('Outside market hours. Skipping update.');
  }
}

// Run immediately once, then every 5 minutes
run();
setInterval(run, 5 * 60 * 1000);
