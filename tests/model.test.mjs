import { test } from 'node:test';
import assert from 'node:assert/strict';
import { saveCommand, parseStatus, connectCommand } from '../webroot/model.js';
import { exec } from '../webroot/bridge.js';

const good = { enabled: 'on', port: '5555', mode: 'tcp', notify: 'on' };
test('valid configuration maps to a fixed controller', () => {
  assert.match(saveCommand(good), /control\.sh save on 5555 tcp on$/);
});
test('rejects shell metacharacters, invalid ranges and noncanonical numbers', () => {
  for (const port of ['', '0', '1023', '65536', '05555', '5555;id', "5555'", '1e4', '-1', '5555\n', '99999999999999999']) {
    assert.throws(() => saveCommand({ ...good, port }), undefined, port);
  }
  for (const port of ['1024', '65535']) assert.doesNotThrow(() => saveCommand({ ...good, port }));
});
test('rejects arbitrary enums before any bridge call', () => {
  for (const key of ['enabled', 'mode', 'notify']) {
    assert.throws(() => saveCommand({ ...good, [key]: 'on;id' }));
  }
});
test('status parsing treats HTML and shell payloads as inert text', () => {
  const state = parseStatus('reason=<img onerror=alert(1)>\nport=5555\n__proto__=polluted\n');
  assert.equal(state.reason, '<img onerror=alert(1)>');
  assert.equal(Object.getPrototypeOf(state), null);
  assert.equal({}.polluted, undefined);
});
test('never offers an unverified or malicious connection address', () => {
  const goodState = { active: 'on', ip: '192.168.1.9', actual_port: '5555' };
  assert.equal(connectCommand(goodState), 'adb connect 192.168.1.9:5555');
  for (const ip of ['999.1.1.1', '1.2.3.4;id', '', '<script>']) assert.equal(connectCommand({ ...goodState, ip }), '');
  assert.equal(connectCommand({ ...goodState, active: 'off' }), '');
  assert.equal(connectCommand({ ...goodState, actual_port: '65536' }), '');
});
test('official native callback bridge resolves asynchronous results', async () => {
  globalThis.ksu = { exec(command, options, callback) {
    assert.equal(options, '{}');
    setTimeout(() => globalThis[callback](0, 'actual output', ''), 1);
  } };
  assert.equal(await exec('fixed command'), 'actual output');
  assert.equal(Object.keys(globalThis).some(k => k.startsWith('wadb_callback_')), false);
  delete globalThis.ksu;
});
test('bridge errors and timeouts are never reported as success', async () => {
  globalThis.ksu = { exec(command, options, callback) { globalThis[callback](1, '', 'denied'); } };
  await assert.rejects(exec('x'), /denied/);
  globalThis.ksu = { exec() {} };
  await assert.rejects(exec('x', 5), /超时/);
  delete globalThis.ksu;
  await assert.rejects(exec('x'), /root/);
});
test('promise-based manager adapter requires an explicit exit status', async () => {
  globalThis.ksuwebui = { exec: async () => ({ errno: 0, stdout: 'ok' }) };
  assert.equal(await exec('x'), 'ok');
  globalThis.ksuwebui = { exec: async () => ({ stdout: 'not proof of success' }) };
  await assert.rejects(exec('x'), /失败/);
  delete globalThis.ksuwebui;
});
