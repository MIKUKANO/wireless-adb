import { chromium } from 'playwright';
import { createServer } from 'node:http';
import { readFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';

const root = fileURLToPath(new URL('../webroot/', import.meta.url));
const out = fileURLToPath(new URL('../.case/', import.meta.url));
await mkdir(out, { recursive: true });
const server = createServer(async (req, res) => {
  const name = req.url === '/' ? 'index.html' : req.url.slice(1);
  if (!['index.html', 'styles.css', 'app.js', 'model.js', 'bridge.js'].includes(name)) {
    res.writeHead(404); res.end(); return;
  }
  const content = await readFile(path.join(root, name));
  res.setHeader('Content-Type', name.endsWith('.js') ? 'application/javascript' : name.endsWith('.css') ? 'text/css' : 'text/html');
  res.end(content);
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const url = `http://127.0.0.1:${server.address().port}/`;
const options = { headless: true };
if (process.env.PLAYWRIGHT_CHROME) options.executablePath = process.env.PLAYWRIGHT_CHROME;
let browser;
try {
  browser = await chromium.launch(options);
  const page = await browser.newPage({ viewport: { width: 1100, height: 960 }, locale: 'zh-CN' });
  const errors = [], requests = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('request', request => requests.push(request.url()));
  await page.addInitScript(() => {
    window.mock = { enabled: 'on', port: '5555', mode: 'tcp', notify: 'on', active: 'on',
      ip: '192.168.1.8', actual_port: '5555', auth: '1', reason: 'active_tcp' };
    window.commands = [];
    window.ksu = { exec(command, options, callback) {
      window.commands.push(command);
      let stdout = '', errno = 0, stderr = '';
      if (command.includes(' save ')) {
        const [enabled, port, mode, notify] = command.split(' save ')[1].split(' ');
        Object.assign(window.mock, { enabled, port, mode, notify });
      }
      if (command.endsWith(' pause')) Object.assign(window.mock, { enabled: 'off', active: 'off', reason: 'disabled' });
      if (command.endsWith(' apply')) Object.assign(window.mock, { active: window.mock.enabled, actual_port: window.mock.port });
      if (command.endsWith(' doctor')) stdout = '<img src=x onerror="window.injected=true">\nfixture: mock diagnostics';
      else stdout = Object.entries(window.mock).map(([k, v]) => `${k}=${v}`).join('\n');
      if (window.failNext) { errno = 1; stderr = 'fixture: root denied'; window.failNext = false; }
      setTimeout(() => window[callback](errno, stdout, stderr), 1);
    } };
  });
  await page.goto(url);
  await page.waitForFunction(() => document.querySelector('#message').textContent.includes('已连接模块'));
  assert.equal(await page.locator('#state-label').textContent(), '连接已就绪');
  assert.equal(await page.locator('#connect-command').textContent(), 'adb connect 192.168.1.8:5555');
  assert.equal(await page.locator('#guard').count(), 0);
  assert.equal(await page.locator('#interval').count(), 0);
  console.log('PASS initial Chinese state and complete removal of self-check settings');
  await page.locator('#port').fill('6000');
  await page.locator('#refresh').click();
  await page.waitForFunction(() => document.querySelector('#message').textContent.includes('未保存更改已保留'));
  assert.equal(await page.locator('#port').inputValue(), '6000');
  await page.locator('#apply').click();
  await page.waitForFunction(() => window.commands.some(c => c.includes(' save on 6000 tcp on')));
  await page.waitForFunction(() => document.querySelector('#message').textContent === '配置已应用。');
  assert.equal(await page.locator('#connect-command').textContent(), 'adb connect 192.168.1.8:6000');
  console.log('PASS form persistence, asynchronous save/apply and live result');
  await page.evaluate(() => { window.failNext = true; });
  await page.locator('#apply').click();
  await page.waitForFunction(() => document.querySelector('#message').textContent.includes('root denied'));
  assert.equal(await page.locator('#message').getAttribute('data-error'), 'true');
  console.log('PASS failed root operation is visibly reported as failure');
  await page.locator('#doctor').click();
  await page.waitForFunction(() => document.querySelector('#diagnostic-text').textContent.includes('<img'));
  assert.equal(await page.locator('#diagnostic-text img').count(), 0);
  assert.equal(await page.evaluate(() => window.injected), undefined);
  console.log('PASS diagnostic HTML payload remains inert text');
  await page.locator('#pause').click();
  await page.waitForFunction(() => document.querySelector('#state-label').textContent.includes('已关闭'));
  assert.equal(await page.locator('#copy').isDisabled(), true);
  console.log('PASS manual shutdown removes the copyable active endpoint');
  await page.locator('#mode').selectOption('tls');
  assert.equal(await page.locator('#port').isDisabled(), true);
  await page.locator('#mode').selectOption('tcp');
  assert.equal(await page.locator('#port').isDisabled(), false);
  for (const colorScheme of ['light', 'dark']) {
    for (const [width, height] of [[375, 900], [720, 480], [1024, 900]]) {
      await page.setViewportSize({ width, height });
      await page.emulateMedia({ colorScheme, reducedMotion: 'reduce' });
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
      assert.equal(overflow, false, `${width}px ${colorScheme}`);
    }
  }
  console.log('PASS light/dark, reduced motion and 375/720/1024px layouts');
  await page.setViewportSize({ width: 375, height: 1000 });
  await page.emulateMedia({ colorScheme: 'light', reducedMotion: 'reduce' });
  await page.evaluate(() => { window.mock.active = 'on'; window.mock.enabled = 'on'; window.mock.reason = 'active_tcp'; });
  await page.locator('#refresh').click();
  await page.waitForFunction(() => document.querySelector('#state-label').textContent === '连接已就绪');
  await page.locator('#diagnostics').evaluate(el => { el.hidden = true; });
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({ path: path.join(out, 'ui-mobile-preview.png') });
  const noRoot = await browser.newPage();
  await noRoot.goto(url);
  await noRoot.waitForFunction(() => document.querySelector('#message').textContent.includes('未连接 root'));
  assert.equal(await noRoot.locator('#message').getAttribute('data-error'), 'true');
  console.log('PASS normal browser has an explicit unsupported-bridge state');
  assert.deepEqual(errors, []);
  assert.equal(requests.every(r => r.startsWith(url)), true);
  console.log('PASS no uncaught page errors or external network requests');
  console.log('UI preview uses mocked Android status, not a connected phone');
} finally {
  if (browser) await browser.close();
  await new Promise(resolve => server.close(resolve));
}
