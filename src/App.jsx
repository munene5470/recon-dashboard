import { useEffect, useMemo, useState } from 'react';

const EMPTY_SUMMARY = { target: '', generated: '', findings: {} };

function parseSummary(value) {
  try {
    return value ? JSON.parse(value) : EMPTY_SUMMARY;
  } catch {
    return EMPTY_SUMMARY;
  }
}

export default function App() {
  const [scans, setScans] = useState([]);
  const [selectedId, setSelectedId] = useState(null);
  const [filter, setFilter] = useState('all');
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');
  const [form, setForm] = useState({ target: '', scopeFile: '', resumeDir: '', diffDir: '', aggressive: false });

  const fetchScans = async () => {
    try {
      const response = await fetch('/api/scans');
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || 'Error loading scans');
      setScans(data.scans || []);
      if (!selectedId && data.scans?.length) setSelectedId(data.scans[0].id);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchScans(); const timer = setInterval(fetchScans, 5000); return () => clearInterval(timer); }, []);

  const selectedScan = scans.find((scan) => scan.id === selectedId) || null;
  const summary = useMemo(() => parseSummary(selectedScan?.summary), [selectedScan]);
  const findings = summary.findings || {};
  const visibleScans = useMemo(
    () => scans.filter((scan) => filter === 'all' || scan.status === filter),
    [scans, filter]
  );

  const handleChange = (event) => {
    const { name, value, type, checked } = event.target;
    setForm((current) => ({ ...current, [name]: type === 'checkbox' ? checked : value }));
  };

  const handleSubmit = async (event) => {
    event.preventDefault();
    setSubmitting(true); setError('');
    try {
      const response = await fetch('/api/scans', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(form)
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || 'Unable to launch scan');
      setSelectedId(data.scan.id);
      setForm({ target: '', scopeFile: '', resumeDir: '', diffDir: '', aggressive: false });
      await fetchScans();
    } catch (err) {
      setError(err.message);
    } finally {
      setSubmitting(false);
    }
  };

  const downloadReport = () => {
    if (!selectedScan) return;
    window.open(`/api/scans/${selectedScan.id}/report`, '_blank', 'noopener,noreferrer');
  };

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand-block">
          <div className="brand-mark">ER</div>
          <div>
            <h1>Elite Recon</h1>
            <small>Ops dashboard</small>
          </div>
        </div>

        <form className="scan-form" onSubmit={handleSubmit}>
          <label>
            Target domain
            <input name="target" value={form.target} onChange={handleChange} placeholder="example.com" required />
          </label>
          <label>
            Scope file path
            <input name="scopeFile" value={form.scopeFile} onChange={handleChange} placeholder="/path/to/scope.txt" />
          </label>
          <label>
            Resume directory
            <input name="resumeDir" value={form.resumeDir} onChange={handleChange} placeholder="recon_example_..." />
          </label>
          <label>
            Diff directory
            <input name="diffDir" value={form.diffDir} onChange={handleChange} placeholder="recon_previous_..." />
          </label>
          <label className="checkbox-row">
            <input type="checkbox" name="aggressive" checked={form.aggressive} onChange={handleChange} />
            <span>Aggressive mode</span>
          </label>
          <button type="submit" disabled={submitting}>{submitting ? 'Launching…' : 'Launch scan'}</button>
        </form>
        {error && <div className="error-box">{error}</div>}
      </aside>

      <main className="main-panel">
        <header className="topbar">
          <div>
            <p className="eyebrow">OPERATIONS</p>
            <h2>Scan workspace</h2>
          </div>
          <button className="ghost-button" type="button" onClick={fetchScans}>Refresh</button>
        </header>

        <section className="toolbar">
          <strong>{scans.length} total scans</strong>
          <select value={filter} onChange={(event) => setFilter(event.target.value)}>
            <option value="all">All statuses</option>
            <option value="queued">Queued</option>
            <option value="running">Running</option>
            <option value="completed">Completed</option>
            <option value="failed">Failed</option>
          </select>
        </section>

        {loading ? (
          <div className="empty-state">Loading scans…</div>
        ) : (
          <div className="scan-list">
            {visibleScans.length === 0 ? (
              <div className="empty-state">No matching scans.</div>
            ) : (
              visibleScans.map((scan) => (
                <button key={scan.id} type="button" className={`scan-item ${selectedId === scan.id ? 'active' : ''}`} onClick={() => setSelectedId(scan.id)}>
                  <div className="scan-meta-row">
                    <span className="scan-target">{scan.target}</span>
                    <span className={`status status-${scan.status}`}>{scan.status}</span>
                  </div>
                  <small>{new Date(scan.created_at).toLocaleString()}</small>
                  <div className="scan-dir">{scan.output_dir}</div>
                </button>
              ))
            )}
          </div>
        )}

        {selectedScan && (
          <section className="details-panel">
            <div className="details-header">
              <div>
                <p className="eyebrow">SELECTED SCAN</p>
                <h3>{selectedScan.target}</h3>
                <small>{selectedScan.output_dir}</small>
              </div>
              <div className="action-row">
                <span className={`status status-${selectedScan.status}`}>{selectedScan.status}</span>
                <button className="ghost-button" type="button" onClick={downloadReport}>Download report</button>
              </div>
            </div>

            <div className="metrics-grid">
              <div className="metric-card">
                <span>Created</span>
                <strong>{new Date(selectedScan.created_at).toLocaleString()}</strong>
              </div>
              <div className="metric-card">
                <span>Last updated</span>
                <strong>{new Date(selectedScan.updated_at).toLocaleString()}</strong>
              </div>
              <div className="metric-card">
                <span>Mode</span>
                <strong>{selectedScan.aggressive ? 'Aggressive' : 'Safe'}</strong>
              </div>
            </div>

            <div className="panel-block">
              <h4>OWASP categories</h4>
              <div className="tag-grid">
                {Object.keys(findings).map((key) => <span key={key} className="tag">{key}</span>)}
              </div>
            </div>

            <div className="panel-block">
              <h4>Structured findings</h4>
              <pre>{JSON.stringify(summary, null, 2)}</pre>
            </div>

            <div className="panel-block">
              <h4>Live log</h4>
              <pre className="log-output">{selectedScan.log || 'No log output yet.'}</pre>
            </div>
          </section>
        )}
      </main>
    </div>
  );
}
