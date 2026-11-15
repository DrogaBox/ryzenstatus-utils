// Worker-pool pattern: the main thread hands small jobs to N workers over MessagePorts and
// waits for the answers (like a JS app or Electron renderer using a pool). Chatty on purpose.
// Usage: node workers.js <workers> <jobs>
const { Worker } = require('node:worker_threads');
const n = +process.argv[2] || 4, jobs = +process.argv[3] || 200000;
const code = `
const { parentPort } = require('node:worker_threads');
parentPort.on('message', (m) => {
  let h = 2166136261;
  for (let i = 0; i < m.s.length; i++) h = Math.imul(h ^ m.s.charCodeAt(i), 16777619);
  parentPort.postMessage({ id: m.id, h });
});`;
const ws = Array.from({ length: n }, () => new Worker(code, { eval: true }));
let sent = 0, done = 0;
const t0 = process.hrtime.bigint();
const payload = 'x'.repeat(256);
function send(w) { if (sent < jobs) w.postMessage({ id: sent++, s: payload }); }
for (const w of ws) {
  w.on('message', () => {
    if (++done === jobs) {
      const ms = Number(process.hrtime.bigint() - t0) / 1e6;
      console.log(`workers ${n} jobs ${jobs}: ${ms.toFixed(0)} ms`);
      process.exit(0);
    }
    send(w);
  });
  for (let k = 0; k < 4; k++) send(w);
}
