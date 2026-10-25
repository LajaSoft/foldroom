import { chromium } from 'playwright-core';
import { mkdir, writeFile } from 'node:fs/promises';

const output = '/results';
await mkdir(output, { recursive: true });
const browser = await chromium.connectOverCDP(process.env.CHROMIUM_CDP_URL ?? 'http://127.0.0.1:9223');
console.log(`Chromium ${browser.version()} · external browser`);
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
await page.bringToFront();
const failures = [];
const messages = [];
page.on('console', message => {
  const text = message.text();
  messages.push(`${message.type()}: ${text}`);
  if (message.type() === 'error') failures.push(text);
});
page.on('pageerror', error => failures.push(error.message));
page.on('crash', () => failures.push('Chromium renderer crashed'));
page.on('dialog', async dialog => {
  failures.push(`Browser dialog: ${dialog.message()}`);
  await dialog.dismiss();
});
await page.addInitScript(() => {
  window.webglContextLost = false;
  document.addEventListener('webglcontextlost', () => {
    window.webglContextLost = true;
  }, true);
});

try {
  await page.goto(process.env.DEMO_URL ?? 'http://localhost:8081/play/');
  await page.waitForFunction(() => {
    const status = document.querySelector('#status');
    return !status;
  }, null, { timeout: 120_000 });
  await page.screenshot({ path: `${output}/chromium-menu.png` });
  // Godot renders its UI inside the canvas rather than HTML controls.
  await page.locator('canvas').press('Enter');
  await page.locator('canvas').press('w');
  // GPU watchdog crashes previously appeared about 30 seconds after startup.
  await page.waitForTimeout(35_000);
  await page.screenshot({ path: `${output}/chromium-play.png` });
  await page.locator('canvas').press('Escape');
  await page.waitForFunction(() => document.pointerLockElement === null);
  await page.screenshot({ path: `${output}/chromium-paused.png` });
  await page.bringToFront();
  await page.locator('canvas').press('Enter');
  await page.waitForFunction(() => document.pointerLockElement !== null);
  // Browser Escape can release the pointer without delivering a key event.
  await page.evaluate(() => document.exitPointerLock());
  await page.waitForFunction(() => document.pointerLockElement === null);
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  await page.screenshot({ path: `${output}/chromium-lock-released.png` });
  // Fixed viewport: the Rooms / Tubes menu button is drawn by Godot in canvas.
  await page.mouse.click(550, 253);
  await page.waitForTimeout(35_000);
  await page.screenshot({ path: `${output}/chromium-other-geometry.png` });
  if (await page.evaluate(() => window.webglContextLost)) {
    failures.push('WebGL context lost');
  }
  if (failures.length) throw new Error(failures.join('\n'));
  console.log('PASS Chromium: game loaded, canvas rendered, input delivered, no WebGL loss or console errors');
} finally {
  await writeFile(`${output}/chromium-console.log`, messages.join('\n'));
  await browser.close();
}
