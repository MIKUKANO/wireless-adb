// KernelSU's native bridge is callback-based, not a synchronous exec().
let counter = 0;
export function exec(command, timeout = 20000) {
  return new Promise((resolve, reject) => {
    const bridge = globalThis.ksu || globalThis.ksuwebui;
    if (!bridge || typeof bridge.exec !== 'function') {
      reject(new Error('未连接 root 桥接。请从 SukiSU / KernelSU 模块 WebUI 打开。'));
      return;
    }
    const name = `wadb_callback_${Date.now()}_${counter++}`;
    const cleanup = () => { clearTimeout(timer); delete globalThis[name]; };
    const finish = (errno, stdout, stderr) => {
      cleanup();
      if (!Number.isFinite(Number(errno)) || Number(errno) !== 0) {
        reject(new Error(String(stderr || `命令执行失败（${errno}）`)));
      } else resolve(String(stdout || ''));
    };
    const timer = setTimeout(() => {
      cleanup();
      reject(new Error('操作超时，结果未知。请刷新状态后再决定是否重试。'));
    }, timeout);
    globalThis[name] = finish;
    try {
      const result = bridge.exec(command, '{}', name);
      // Some standalone managers wrap the native bridge in a Promise.
      if (result && typeof result.then === 'function') {
        result.then(r => finish(r.errno, r.stdout, r.stderr), e => { cleanup(); reject(e); });
      } else if (result && typeof result === 'object' && 'errno' in result) {
        finish(result.errno, result.stdout, result.stderr);
      }
    } catch (error) { cleanup(); reject(error); }
  });
}
