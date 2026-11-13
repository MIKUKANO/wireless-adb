export const CONTROL = '/system/bin/sh /data/adb/modules/wireless-adb/scripts/control.sh';
export function parseStatus(text) {
  const state = Object.create(null);
  for (const line of text.trim().split('\n')) {
    const index = line.indexOf('=');
    if (index > 0) state[line.slice(0, index)] = line.slice(index + 1);
  }
  return state;
}
export function saveCommand(config) {
  if (!/^[1-9]\d{3,4}$/.test(config.port) || String(Number(config.port)) !== config.port || Number(config.port) < 1024 || Number(config.port) > 65535) {
    throw new Error('端口必须是 1024–65535 之间的整数，不能带前导零。');
  }
  for (const key of ['enabled', 'notify']) {
    if (!['on', 'off'].includes(config[key])) throw new Error('开关值无效。');
  }
  if (!['tcp', 'tls'].includes(config.mode)) {
    throw new Error('连接模式无效。');
  }
  // Every argument is now drawn from a closed enum or canonical digits.
  return `${CONTROL} save ${config.enabled} ${config.port} ${config.mode} ${config.notify}`;
}
export function connectCommand(state) {
  if (state.active !== 'on' || !/^(\d{1,3}\.){3}\d{1,3}$/.test(state.ip || '') ||
      !state.ip.split('.').every(n => Number(n) <= 255) || !/^\d{4,5}$/.test(state.actual_port || '') ||
      Number(state.actual_port) < 1024 || Number(state.actual_port) > 65535) return '';
  return `adb connect ${state.ip}:${state.actual_port}`;
}
export const reasons = {
  disabled: '已关闭远程连接', waiting_wifi: '等待 Wi-Fi IPv4 地址', auth_unverified: '授权属性未通过检查，已阻止启用',
  active_tcp: 'TCP 监听已就绪', active_tls: '原生 TLS 监听已就绪', waiting_tls: '等待系统 TLS 服务；可打开配对与授权检查',
  waiting_listener: '等待监听启动', invalid_config: '配置无效，已停止恢复', restart_failed: '服务重启失败或处于冷却期',
  close_failed: '关闭操作失败，请检查诊断', boot_timeout: '等待开机完成超时', restored: '已恢复接管前状态',
  binding_unsupported: '系统未按指定地址监听；已尝试停止 adbd，需检查设备兼容性'
};
