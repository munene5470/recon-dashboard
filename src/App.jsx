import { useEffect, useMemo, useState } from 'react';

const EMPTY_SUMMARY = {
  target: '',
  generated: '',
  findings: {},
};

function App() {
  const [scans, setScans] = useState([]);
  const [selectedId, setSelectedId] = useState(null);
  const [selectedScan, setSelectedScan] = useState(null);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [form, setForm] = useState({
    target: 'example.com',
    scopeFile: '',
    resumeDir: '',
    diffDir: '',
    aggressive: false,
  });
  const [error, setError] = useState('');

  const fetchScans = async () => {
    try {
      const response = await fetch('/api/scans');
      const data = await response.json();
      if (!response.ok) {
        throw new Error(data.error || 'Failed to fetch scans');
      }
      setScans(data.scans || []);
      if (!selectedId && data.scans?.length) {
        setSelectedId(data.scans[0].id);
      }
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchScans();
  }, []);

  useEffect(() => {
    if (!selectedId) return;
    const selected = scans.find((scan) => scan.id === selectedId);
    setSelectedScan(selected || null);
  }, [selectedId, scans]);

  useEffect(() => {
    const poll = setInterval(async () => {
      await fetchScans();
    }, 5_000);
    return () => clearInterval(poll);
  }, [selectedId]);

  const handleChange = (event) => {
    const { name, value, type, checked } = event.target;
    setForm((current) => ({
      ...current,
      [name]: type === 'checkbox' ? checked : value,
    }));
  };

  const handleSubmit = async (event) => {
    event.preventDefault();
    setSubmitting(true);
    setError('');

    try {
      const response = await fetch('/api/scans', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          target: form.target,
          scopeFile: form.scopeFile,
          resumeDir: form.resumeDir,
          diffDir: form.diffDir,
          aggressive: form.aggressive,
        }),
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || 'Scan failed to start');
      setSelectedId(data.scan.id);
      setForm({
        target: '',
        scopeFile: '',
        resumeDir: '',
        diffDir: '',
        aggressive: false,
      });
      await fetchScans();
    } catch (err) {
      setError(err.message);
    } finally {
      setSubmitting(false);
    }
  };

  const summary = useMemo(() => {
    if (!selectedScan?.summary) return EMPTY_SUMMARY;
    try {
      return JSON.parse(selectedScan.summary);
    } catch {
      return EMPTY_SUMMARY;
    }
  }, [selectedScan]);

  const findings = summary.findings || {};

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand-block">
          <div className="brand-mark">ER</div>
          <div>
            <h1>Elite Recon</h1>
            <small>Scan control center</small>
          </div>
        </div>

        <form onSubmit={handleSubmit} className="scan-form">
          <label>
            Target domain
            <input
              name="target"
              value={form.target}
              onChange={handleChange}
              placeholder="example.com"
              required
            />
          </label>

          <label>
            Scope file path
            <input
              name="scopeFile"
              value={form.scopeFile}
              onChange={handleChange}
              placeholder="/path/to/scope.txt"
            />
          </label>

          <label>
            Resume directory
            <input
              name="resumeDir"
              value={form.resumeDir}
              onChange={handleChange}
              placeholder="/tmp/recon_example"
            />
          </label>

          <label>
            Diff directory
            <input
              name="diffDir"
              value={form.diffDir}
              onChange={handleChange}
              placeholder="/tmp/recon_previous"
            />
          </label>

          <label className="checkbox-row">
            <input
              type="checkbox"
              name="aggressive"
              checked={form.aggressive}
              onChange={handleChange}
            />
            <span>Aggrressive mode</span>
          </label>

          <button type="submit" disabled={submitting}>
            {submitting ? 'Launching scan...' : 'Launch scan'}
          </button>
        </form>

        {error && <div className="error-box">{error}</div>}
      </aside>

      <main className="main-panel">
        <header className="topbar">
          <div>
            <h2>Recent scans</h2>
          </div>
          <button className="ghost-button" type="button" onClick={fetchScans}>
            Refresh
          </button>
        </header>

        {loading ? (
          <div className="loading">Loading scans…</div>
        ) : (
          <div className="scan-list">
            {scans.length === 0 ? (
              <div className="empty-state">No scans yet. Launch the first one.</div>
            ) : (
              scans.map((scan) => (
                <button
                  key={scan.id}
                  type="button"
                  className={selectedId === scan.id ? 'scan-item active' : 'scan-item'}
                  onClick={() => setSelectedId(scan.id)}
                >
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
                <h3>{selectedScan.target}</h3>
                <small>{selectedScan.output_dir}</small>
              </div>
              <span className={`status status-${selectedScan.status}`}>{selectedScan.status}</span>
            </div>

            <div className="metrics-grid">
              <div className="metric-card">
                <span>Created</span>
                <strong>{new Date(selectedScan.created_at).toLocaleString()}</strong>
              </div>
              <div className="metric-card">
                <span>Updated</span>
                <strong>{new Date(selectedScan.updated_at).toLocaleString()}</strong>
              </div>
              <div className="metric-card">
                <span>Mode</span>
                <strong>{selectedScan.aggressive ? 'Aggressive' : 'Safe'}</strong>
              </div>
            </div>

            <div className="panel-block">
              <h4>Findings summary</h4>
              <pre>{JSON.stringify(summary, null, 2)}</pre>
            </div>

            <div className="panel-block">
              <h4>OWASP categories</h4>
              <div className="tag-grid">
                {Object.keys(findings).map((key) => (
                  <span key={key} className="tag">
                    {key}
                  </span>
                ))}
              </div>
            </div>

            <div className="panel-block">
              <h4>Raw log</h4>
              <pre>{selectedScan.log || 'No log output yet.'}</pre>
            </div>
          </section>
        )}
      </main>
    </div>
  );
}

export default App;
