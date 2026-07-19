## 0.1.0

- Adds the read-only Observer Protocol v1 runtime bridge and DevTools panel.
- Reconciles snapshot, polling backlog, and live stream without a loss window.
- Adds single-flight bounded resynchronization and connection generations.
- Enforces complete UTF-8 payload limits with visible drop diagnostics.
- Adds strict polling/decode contracts, hot-restart-safe handler routing, CI,
  release web builds, and DevTools extension validation.
- Binds every DevTools handshake and live stream to one selected isolate,
  filters VM-wide extension events, and rebuilds the connection on target changes.
- Makes resync failures recoverable, rejects cross-session or incomplete
  snapshot backlogs, sanitizes diagnostics, and exposes explicitly cleared
  transport events.
- Verifies discovery, handshake, streaming and new-session recovery in a real
  Chrome/Flutter DevTools host.
