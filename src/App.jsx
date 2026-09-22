import { useEffect, useState } from 'react';

const statusClass = (status) => `stage-status stage-${status}`;

export default function App() {
  const [scans, setScans] = useState([]);
  const [selected, setSelected] = useState(null);
  const [form, setForm] = useState({ target: '' });
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  const loadScans = async () => {
    try {
      const response = await fetch('/api/scans');
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || 'Unable to load scans');
      setScans(data.scans || []);
      setSelected((current) => current || data.scans?.[0] || null);
    } catch (err) { setError(err.message); }
    finally { setLoading(false); }
  };

  const loadSelected = async (scan) => {
    if (!scan) return;
    const response = await fetch(`/api/scans/${scan.id}`);
    const data = await response.json();
    if (response.ok) setSelected({ ...data.scan, stages: data.stages || [] });
  };

  useEffect(() => { loadScans(); const timer = setInterval(loadScans, 4000); return () => clearInterval(timer); }, []);
  useEffect(() => { loadSelected(selected); }, [selected?.id, scans]);

  const submit = async (event) => {
    event.preventDefault(); setError('');
    try {
      const response = await fetch('/api/scans', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(form) });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || 'Unable to start scan');
      setForm({ target: '' }); setSelected(data.scan); await loadScans();
    } catch (err) { setError(err.message); }
  };

  const stages = selected?.stages || [];
  const completed = stages.filter((stage) => stage.status === 'completed').length;
  const running = stages.find((stage) => stage.status === 'running');
  const progress = stages.length ? Math.round((completed / stages.length) * 100) : 0;

  return <div className="app-shell">
    <aside className="sidebar"><div className="brand-block"><div className="brand-mark">ER</div><div><h1>Elite Recon</h1><small>Staged pipeline</small></div></div>
      <form className="scan-form" onSubmit={submit}><label>Authorized root domain<input required value={form.target} onChange={(event) => setForm({ target: event.target.value })} placeholder="example.com" /></label><button type="submit">Start staged scan</button></form>
      {error && <div className="error-box">{error}</div>}
      <p className="side-note">Stages are dependency-ordered. Later phases remain skipped until their inputs are produced.</p>
    </aside>
    <main className="main-panel"><header className="topbar"><div><p className="eyebrow">PIPELINE CONTROL</p><h2>Recon workspace</h2></div><button className="ghost-button" onClick={loadScans}>Refresh</button></header>
      {loading ? <div className="empty-state">Loading…</div> : <div className="scan-list">{scans.length === 0 ? <div className="empty-state">No scans yet.</div> : scans.map((scan) => <button type="button" className={`scan-item ${selected?.id === scan.id ? 'active' : ''}`} key={scan.id} onClick={() => setSelected(scan)}><div className="scan-meta-row"><strong>{scan.target}</strong><span className={`status status-${scan.status}`}>{scan.status}</span></div><small>{new Date(scan.created_at).toLocaleString()}</small></button>)}</div>}
      {selected && <section className="details-panel"><div className="details-header"><div><p className="eyebrow">ACTIVE SCAN</p><h3>{selected.target}</h3><small>{selected.output_dir}</small></div><span className={`status status-${selected.status}`}>{selected.status}</span></div>
        <div className="progress-label"><span>{completed} / {stages.length || 16} stages complete</span><strong>{progress}%</strong></div><div className="progress-track"><div style={{ width: `${progress}%` }} /></div>{running && <p className="running-note">Running: Phase {running.phase} — {running.name}</p>}
        <div className="stage-list">{stages.map((stage) => <div className="stage-row" key={stage.stage_key}><div className="stage-number">{String(stage.phase).padStart(2, '0')}</div><div className="stage-main"><strong>{stage.name}</strong><small>{stage.priority} priority · {stage.message || 'Waiting'}</small></div><span className={statusClass(stage.status)}>{stage.status}</span></div>)}</div>
        <div className="panel-block"><h4>Live log</h4><pre className="log-output">{selected.log || 'No log output yet.'}</pre></div>
      </section>}
    </main>
  </div>;
}
