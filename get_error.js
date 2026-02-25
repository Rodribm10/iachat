const { chromium } = require('playwright');
const fs = require('fs');

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext();
  const page = await context.newPage();
  
  // Listen for console errors
  page.on('console', msg => {
    if (msg.type() === 'error') {
      console.log('Browser Error:', msg.text());
    }
  });

  page.on('pageerror', err => {
    console.log('Page Error:', err.message);
    console.log('Stack:', err.stack);
    fs.writeFileSync('error_trace.txt', err.stack);
  });

  // Since we don't have a live authenticated session here easily, 
  // maybe the error happens even without auth? Or we can just read the server logs if it's SSR?
  // Chatwoot is an SPA mostly for dashboard.
  // Wait, the user already provided the error: "TypeError: Cannot read properties of null (reading 'emitsOptions')"
  await browser.close();
})();
