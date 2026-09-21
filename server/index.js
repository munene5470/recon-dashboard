:root {
  color-scheme: dark;
  font-family: Inter, system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  line-height: 1.5;
  font-weight: 400;
  background: #08101d;
  color: #e2e8f0;
  font-synthesis: none;
  text-rendering: optimizeLegibility;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

* { box-sizing: border-box; }

html, body, #root {
  margin: 0;
  min-width: 100%;
  min-height: 100%;
  background: #08101d;
}

body { min-height: 100vh; }

button, input { font: inherit; }
button { cursor: pointer; }

.app-shell {
  display: grid;
  grid-template-columns: 360px 1fr;
  min-height: 100vh;
}

.sidebar {
  background: #0f172a;
  border-right: 1px solid rgba(148, 163, 184, 0.2);
  padding: 24px 18px;
}

.brand-block {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 22px;
}

.brand-mark {
  display: grid;
  place-items: center;
  width: 48px;
  height: 48px;
  border-radius: 14px;
  background: linear-gradient(135deg, #22c55e, #2563eb);
  font-weight: 700;
  color: white;
}

.brand-block h1 { margin: 0; font-size: 1.3rem; }
.brand-block small { color: #93c5fd; }

.scan-form {
  display: flex;
  flex-direction: column;
  gap: 14px;
}

.scan-form label {
  display: flex;
  flex-direction: column;
  gap: 8px;
  color: #cbd5e1;
  font-size: 0.85rem;
}

.scan-form input {
  border: 1px solid rgba(148, 163, 184, 0.2);
  border-radius: 10px;
  background: rgba(15, 23, 42, 0.8);
  color: white;
  padding: 10px 12px;
}

.checkbox-row {
  flex-direction: row !important;
  align-items: center;
  gap: 10px !important;
}

.scan-form button,
.ghost-button {
  border: none;
  border-radius: 10px;
  background: linear-gradient(135deg, #16a34a, #2563eb);
  color: white;
  padding: 10px 14px;
  font-weight: 600;
}

.ghost-button {
  background: rgba(148, 163, 184, 0.14);
}

.main-panel { padding: 20px; }

.topbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 18px;
}

.topbar h2 { margin: 0; }

.scan-list {
  display: grid;
  gap: 12px;
  margin-bottom: 18px;
}

.scan-item {
  width: 100%;
  text-align: left;
  background: rgba(15, 23, 42, 0.72);
  border: 1px solid rgba(148, 163, 184, 0.18);
  border-radius: 12px;
  padding: 14px 16px;
  color: white;
}

.scan-item.active {
  border-color: rgba(59, 130, 246, 0.7);
  box-shadow: 0 0 0 1px rgba(59, 130, 246, 0.4);
}

.scan-meta-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.scan-target { font-weight: 600; }

.status {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 4px 8px;
  border-radius: 999px;
  font-size: 0.75rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.status-running { background: rgba(59, 130, 246, 0.2); color: #93c5fd; }
.status-queued { background: rgba(250, 204, 21, 0.18); color: #fde68a; }
.status-completed { background: rgba(34, 197, 94, 0.18); color: #86efac; }
.status-failed { background: rgba(239, 68, 68, 0.18); color: #fca5a5; }

.scan-dir {
  color: #93c5fd;
  margin-top: 4px;
  font-size: 0.76rem;
}

.details-panel {
  background: rgba(15, 23, 42, 0.7);
  border: 1px solid rgba(148, 163, 184, 0.18);
  border-radius: 16px;
  padding: 18px;
}

.details-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 18px;
}

.details-header h3 { margin: 0; }

.metrics-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
  gap: 12px;
  margin-bottom: 18px;
}

.metric-card {
  background: rgba(15, 23, 42, 0.9);
  border: 1px solid rgba(148, 163, 184, 0.16);
  border-radius: 12px;
  padding: 12px 14px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.metric-card span { color: #cbd5e1; font-size: 0.76rem; }

.panel-block { margin-top: 18px; }
.panel-block h4 { margin: 0 0 12px; }

pre {
  background: rgba(2, 6, 23, 0.9);
  border: 1px solid rgba(148, 163, 184, 0.16);
  border-radius: 12px;
  padding: 14px;
  overflow: auto;
  white-space: pre-wrap;
  word-break: break-word;
  color: #dbeafe;
}

.tag-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.tag {
  display: inline-flex;
  padding: 5px 9px;
  border-radius: 999px;
  background: rgba(34, 197, 94, 0.12);
  color: #bbf7d0;
  border: 1px solid rgba(34, 197, 94, 0.2);
}

.error-box {
  margin-top: 16px;
  background: rgba(127, 29, 29, 0.3);
  border: 1px solid rgba(248, 113, 113, 0.35);
  color: #fecaca;
  border-radius: 10px;
  padding: 10px 12px;
}

.loading, .empty-state {
  padding: 18px;
  border-radius: 12px;
  border: 1px dashed rgba(148, 163, 184, 0.25);
  color: #cbd5e1;
}

@media (max-width: 980px) {
  .app-shell { grid-template-columns: 1fr; }
  .sidebar {
    border-right: none;
    border-bottom: 1px solid rgba(148, 163, 184, 0.2);
  }
}
