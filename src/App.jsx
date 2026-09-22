import { useEffect, useMemo, useState } from 'react';

const statusClass = (status) => `stage-status stage-${status}`;
const fileLabel = (value) => value.split('/').pop();

export default function App() {
  const [scans, setScans] = useState([]);
  const [selectedId, setSelectedId] = useState(null);
  const [selected, setSelected] = useState(null);
  const [artifacts, setArtifacts] = useState([]);
  const [artifact, setArtifact] = useState('');
  const [artifactText, setArtifactText] = useState('');
  const [form, setForm] = useState({ target: 'example.com' });
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [copied, setCopied] = useState(false);

  const fetchScans = async () => {
    try {
      const response = await fetch('/api/scans');
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || 'Unable to load scans');
      setScans(data.scans || []);
      if (!selectedId && data.scans?.length) setSelectedId(data.scans[0].id);
    } catch (err) { setError(err.message); } finally { setLoading(false); }
  };

  const fetchSelected = async (scanId) => {
    if (!scanId) return;
    try {
      const response = await fetch(`/api/scans/${scanId}`);
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || 'Unable to load scan details');
      setSelected({ ...data.scan, stages: data.stages || [] });
      const artifactResponse = await fetch(`/api/scans/${scanId}/artifacts`);
      const artifactData = await artifactResponse.json();
      setArtifacts(artifactData.artifacts || []);
    } catch (err) { setError(err.message); }
  };

  useEffect(() => { fetchScans(); const timer = setInterval(fetchScans, 2500); return () => clearInterval(timer); }, []);
  useEffect(() => { if (selectedId) fetchSelected(selectedId); }, [selectedId]);
  useEffect(() => {
    if (!artifact || !selectedId) { setArtifactText(''); return; }
    fetch(`/api/scans/${selectedId}/artifacts/${artifact}`).then(async (response) => {
      const text = await response.text();
      if (!response.ok) throw new Error(text || 'Unable to read artifact');
      setArtifactText(text);
    }).catch((err) => setArtifactText(err.message));
  }, [artifact, selectedId]);

  const submit = async (event) => {
    event.preventDefault(); setError('');
    try {
      const response = await fetch('/api/scans', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ target: form.target }) });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || 'Unable to start scan');
      setForm({ target: '' }); setSelectedId(data.scan.id); await fetchScans();
    } catch (err) { setError(err.message); }
  };

  const copyResults = async () => {
    await navigator.clipboard.writeText(artifactText);
    setCopied(true); setTimeout(() => setCopied(false), 1500);
  };

  const deleteScan = async () => {
    if (!selected || !window.confirm(`Delete scan ${selected.target} and all results?`)) return;
    const response = await fetch(`/api/scans/${selected.id}`, { method: 'DELETE' });
    if (!response.ok) { const data = await response.json(); setError(data.error || 'Unable to delete scan'); return; }
    setSelected(null); setSelectedId(null); setArtifacts([]); setArtifact(''); await fetchScans();
  };

  const stages = selected?.stages || [];
  const completed = stages.filter((stage) => ['completed', 'skipped'].includes(stage.status)).length;
  const running = stages.find((stage) => stage.status === 'running');
  const progress = stages.length ? Math.round((completed / stages.length) * 100) : 0;
  const resultFiles = useMemo(() => artifacts.filter((item) => item.path.startsWith('subs/') || item.path.startsWith('findings/') || item.path.startsWith('report/')), [artifacts]);

  return <div className="app-shell">
    <aside className="sidebar"><div className="brand-block"><div className="brand-mark">ER</div><div><h1>Elite Recon</h1><small>Staged pipeline</small></div></div>
      <form className="scan-form" onSubmit={submit}><label>Authorized root domain<input required value={form.target} onChange={(event) => setForm({ target: event.target.value })} placeholder="example.com" /></label><button type="submit">Start staged scan</button></form>
      {error && <div className="error-box">{error}</div>}<p className="side-note">Only assess domains you are authorized to test. Results are refreshed automatically.</p>
    </aside>
    <main className="main-panel"><header className="topbar"><div><p className="eyebrow">PIPELINE CONTROL</p><h2>Recon workspace</h2></div><button className="ghost-button" type="button" onClick={fetchScans}>Refresh</button></header>
      {loading ? <div className="empty-state">Loading…</div> : <div className="scan-list">{scans.length ? scans.map((scan) => <button type="button" key={scan.id} className={`scan-item ${selectedId === scan.id ? 'active' : ''}`} onClick={() => setSelectedId(scan.id)}><div className="scan-meta-row"><strong>{scan.target}</strong><span className={`status status-${scan.status}`}>{scan.status}</span></div><small>{new Date(scan.created_at).toLocaleString()}</small></button>) : <div className="empty-state">No scans yet.</div>}</div>}
      {selected && <section className="details-panel"><div className="details-header"><div><p className="eyebrow">ACTIVE SCAN</p><h3>{selected.target}</h3><small>{selected.output_dir}</small></div><div className="action-row"><span className={`status status-${selected.status}`}>{selected.status}</span><button className="danger-button" type="button" onClick={deleteScan}>Delete scan</button></div></div>
        <div className="progress-label"><span>{completed} / {stages.length || 16} stages processed</span><strong>{progress}%</strong></div><div className="progress-track"><div style={{ width: `${progress}%` }} /></div>
        {running ? <div className="running-banner"><span className="pulse-dot" /> Currently running: <strong>Phase {String(running.phase).padStart(2, '0')} — {running.name}</strong><small>{running.message}</small></div> : <p className="running-note">No tool is currently running.</p>}
        <div className="stage-list">{stages.map((stage) => <div className={`stage-row ${stage.status === 'running' ? 'stage-row-running' : ''}`} key={stage.stage_key}><div className="stage-number">{String(stage.phase).padStart(2, '0')}</div><div className="stage-main"><strong>{stage.name}</strong><small>{stage.priority} priority · {stage.message || 'Waiting'}</small></div><span className={statusClass(stage.status)}>{stage.status}</span></div>)}</div>
        <div className="panel-block"><div className="section-heading"><h4>Tool and pipeline results</h4><div className="artifact-actions"><select value={artifact} onChange={(event) => setArtifact(event.target.value)}><option value="">Select a result file</option>{resultFiles.map((item) => <option key={item.path} value={item.path}>{item.path} ({item.size} bytes)</option>)}</select><button className="ghost-button" type="button" disabled={!artifactText} onClick={copyResults}>{copied ? 'Copied' : 'Copy'}</button></div></div>{artifact ? <pre className="artifact-output">{artifactText}</pre> : <div className="empty-state">Select a result file to view it. Output is scrollable.</div>}</div>
        <div className="panel-block"><h4>Live log</h4><pre className="log-output">{selected.log || 'No log output yet.'}</pre></div>
      </section>}
    </main>
  </div>;
}
