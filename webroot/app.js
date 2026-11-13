import { exec } from './bridge.js';
import { CONTROL, parseStatus, saveCommand, connectCommand, reasons } from './model.js';
const $ = id => document.getElementById(id);
let state = null, busy = false, dirty = false, hydrated = false;
const controls = ['enabled', 'port', 'mode', 'notify'];
function message(text, error = false) {
  $('message').textContent = text;
  $('message').dataset.error = String(error);
}
function render(data, updateForm = false) {
  state = data;
  const connected = data.active === 'on';
  $('state-label').textContent = connected ? '连接已就绪' : data.enabled === 'on' ? '等待连接' : '远程连接已关闭';
  $('status-card').dataset.active = String(connected);
  $('state-description').textContent = reasons[data.reason] || '请检查当前服务状态';
  $('mode-label').textContent = data.mode === 'tls' ? '原生 TLS · 加密传输' : '传统 TCP · 固定端口';
  $('ip-value').textContent = data.ip || '未连接 Wi-Fi';
  $('port-value').textContent = connected ? data.actual_port : '—';
  $('auth-value').textContent = data.auth === '1' ? '授权属性已开启' : '授权属性未确认';
  $('notify-help').textContent = ({ requested: '系统已接受通知请求；地址仅在本页显示', failed: '通知发送失败，请查看系统通知权限',
    unsupported: '当前管理器未解析到模块深链，请从模块页打开', off: '不再发送；已有通知可手动划除' })[data.notification] || '点击打开本页；通知不展示 IP 地址';
  $('connect-command').textContent = connectCommand(data) || '连接就绪后显示命令';
  $('copy').disabled = !connectCommand(data);
  if (updateForm) {
    for (const name of controls) {
      if ($(name).type === 'checkbox') $(name).checked = data[name] === 'on';
      else $(name).value = data[name];
    }
    dirty = false;
    hydrated = true;
  }
  updateMode();
}
function updateMode() {
  const tls = $('mode').value === 'tls';
  $('port').disabled = tls || busy;
  $('mode-help').textContent = tls
    ? '保留系统加密、配对和已授权设备管理。端口由系统分配，厂商的 Wi-Fi 策略仍可能影响服务。'
    : '固定端口，绑定当前 Wi-Fi IPv4 地址。不依赖系统无线调试开关，但传输不加密；首次授权仍需系统确认。';
}
async function refresh(updateForm = false) {
  render(parseStatus(await exec(`${CONTROL} status`)), updateForm);
  $('updated').textContent = `更新于 ${new Date().toLocaleTimeString('zh-CN', { hour12: false })}`;
}
async function action(task) {
  if (busy) return;
  busy = true;
  for (const el of document.querySelectorAll('button, input, select')) el.disabled = true;
  $('workspace').setAttribute('aria-busy', 'true');
  message('正在处理…');
  try { await task(); }
  catch (error) { message(error.message, true); }
  finally {
    busy = false;
    $('workspace').setAttribute('aria-busy', 'false');
    for (const el of document.querySelectorAll('button, input, select')) el.disabled = false;
    $('copy').disabled = !state || !connectCommand(state);
    updateMode();
  }
}
function config() {
  return Object.fromEntries(controls.map(name => [name, $(name).type === 'checkbox' ? ($(name).checked ? 'on' : 'off') : $(name).value.trim()]));
}
for (const name of controls) $(name).addEventListener('change', () => {
  dirty = true; updateMode(); message('有未保存的更改，点击“保存并应用”生效。');
});
$('port').addEventListener('input', () => { dirty = true; });
$('config-form').addEventListener('submit', event => {
  event.preventDefault();
  action(async () => {
    await exec(saveCommand(config()));
    hydrated = true;
    dirty = false;
    message('配置已保存，正在应用…');
    await exec(`${CONTROL} apply`);
    await refresh(true);
    message(state.active === 'on' || state.enabled === 'off' ? '配置已应用。' : '配置已保存；服务尚未就绪，请查看状态或诊断。');
  });
});
$('refresh').addEventListener('click', () => action(async () => {
  await refresh(!dirty && !hydrated); message(dirty ? '状态已刷新，未保存更改已保留。' : '状态已刷新。');
}));
$('pause').addEventListener('click', () => action(async () => {
  await exec(`${CONTROL} pause`); await refresh(true); message('已关闭模块远程连接，保留 USB 调试与已授权密钥。');
}));
$('pair').addEventListener('click', () => action(async () => {
  await exec(`${CONTROL} settings`); message('已请求打开系统配对与授权页面。');
}));
$('doctor').addEventListener('click', () => action(async () => {
  $('diagnostics').hidden = false;
  $('diagnostic-text').textContent = await exec(`${CONTROL} doctor`);
  message('诊断已更新；导出前请留意其中的本机连接地址。');
}));
$('copy').addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText(connectCommand(state)); message('连接命令已复制。');
  } catch { message('剪贴板不可用，请长按上方命令复制。', true); }
});
await action(async () => { await refresh(true); message('已连接模块。所有操作均在本机完成。'); });
