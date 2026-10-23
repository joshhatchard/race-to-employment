'use client';

import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react';
import { Avatar } from '@/components/Avatar';
import { celebrate } from '@/components/Confetti';
import { Logo } from '@/components/Logo';
import { message, supabase } from '@/lib/supabase';

type Group = { id: string; code: string; name: string; closed: boolean };
type Metric = 'applications' | 'interviews';
type View = 'dashboard' | 'feed' | 'applications';
type Standing = {
  user_id: string; display_name: string; colour: string; avatar: string; status: string;
  hired_at: string | null; hired_rank: number | null; hired_company: string | null;
  applications: number; interviews: number; position: number;
};
type Activity = {
  id: string; event_type: 'application' | 'interview' | 'overtake' | 'employment'; actor_user_id: string;
  display_name: string; avatar: string; colour: string; company_name: string | null;
  interview_round: number | null; metadata: { target_name?: string }; created_at: string;
  reactions: Record<string, number>;
};
type AppRecord = { id: string; company_name: string; created_at: string; deleted_at: string | null };
type Interview = { id: string; company_name: string; round_number: number; created_at: string };

const reactions = ['🔥', '💀', '🍞', '👀', '🫡', '🎉'];
const relative = (date: string) => {
  const seconds = Math.max(0, Math.floor((Date.now() - new Date(date).getTime()) / 1000));
  if (seconds < 60) return 'just now';
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h`;
  return `${Math.floor(seconds / 86400)}d`;
};
const activityCopy = (item: Activity) => {
  if (item.event_type === 'application') return <>applied to <b>{item.company_name}</b>. Someone&apos;s actually trying.</>;
  if (item.event_type === 'interview') return <>logged round {item.interview_round} at <b>{item.company_name}</b>.</>;
  if (item.event_type === 'overtake') return <>overtook <b>{item.metadata?.target_name || 'someone'}</b>. Absolute scenes.</>;
  return <>accepted an offer at <b>{item.company_name}</b>. FIRST TO THE BREAD.</>;
};

function Dialog({ title, children, onClose }: { title: string; children: React.ReactNode; onClose: () => void }) {
  return <div className="race-dialog-backdrop" role="presentation" onMouseDown={onClose}>
    <section className="race-dialog" role="dialog" aria-modal="true" aria-label={title} onMouseDown={event => event.stopPropagation()}>
      <header><h2>{title}</h2><button onClick={onClose} aria-label="Close">×</button></header>{children}
    </section>
  </div>;
}

export function RaceDashboard({ group, userId, onSignOut }: { group: Group; userId: string; onSignOut: () => Promise<void> }) {
  const [view, setView] = useState<View>('dashboard');
  const [metric, setMetric] = useState<Metric>('applications');
  const [standings, setStandings] = useState<Standing[]>([]);
  const [activity, setActivity] = useState<Activity[]>([]);
  const [applications, setApplications] = useState<AppRecord[]>([]);
  const [interviews, setInterviews] = useState<Interview[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [logKind, setLogKind] = useState<'application' | 'interview' | 'hired' | null>(null);
  const [company, setCompany] = useState('');
  const [round, setRound] = useState(1);
  const [busy, setBusy] = useState(false);
  const [historyTab, setHistoryTab] = useState<Metric>('applications');

  const refresh = useCallback(async () => {
    if (!supabase) return;
    const [board, feed, apps, ints] = await Promise.all([
      supabase.rpc('race_leaderboard', { p_group: group.id, p_metric: metric }),
      supabase.rpc('race_activity', { p_group: group.id, p_limit: 30, p_offset: 0 }),
      supabase.from('applications').select('id,company_name,created_at,deleted_at').eq('group_id', group.id).eq('user_id', userId).order('created_at', { ascending: false }),
      supabase.from('interviews').select('id,company_name,round_number,created_at').eq('group_id', group.id).eq('user_id', userId).order('created_at', { ascending: false }),
    ]);
    if (board.error) throw board.error;
    if (feed.error) throw feed.error;
    setStandings((board.data || []) as Standing[]);
    setActivity((feed.data || []) as Activity[]);
    setApplications((apps.data || []) as AppRecord[]);
    setInterviews((ints.data || []) as Interview[]);
  }, [group.id, metric, userId]);

  useEffect(() => {
    let active = true;
    setLoading(true); setError('');
    refresh().catch(err => active && setError(message(err))).finally(() => active && setLoading(false));
    return () => { active = false; };
  }, [refresh]);

  useEffect(() => {
    if (!supabase) return;
    const client = supabase;
    const channel = client.channel(`active-race-${group.id}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'applications', filter: `group_id=eq.${group.id}` }, () => { void refresh(); })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'interviews', filter: `group_id=eq.${group.id}` }, () => { void refresh(); })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'activity_events', filter: `group_id=eq.${group.id}` }, () => { void refresh(); })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'memberships', filter: `group_id=eq.${group.id}` }, () => { void refresh(); })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'activity_reactions' }, () => { void refresh(); })
      .subscribe();
    return () => { void client.removeChannel(channel); };
  }, [group.id, refresh]);

  const me = standings.find(person => person.user_id === userId);
  const count = (person: Standing) => metric === 'applications' ? person.applications : person.interviews;
  const max = Math.max(1, ...standings.map(count));
  const finishers = standings.filter(person => person.status === 'employed').sort((a, b) => (a.hired_rank || 99) - (b.hired_rank || 99));
  const rivalry = useMemo(() => {
    if (!me) return '';
    if (standings.length === 1) return 'Solo warm-up. Invite someone worth beating.';
    const leader = standings[0];
    if (me.position === 1) return 'You’re leading the pack. Don’t get comfortable.';
    const ahead = standings.find(person => person.position < me.position && count(person) >= count(me));
    if (!ahead) return 'Keep moving. The pack is right there.';
    const gap = Math.max(1, count(ahead) - count(me) + 1);
    return count(ahead) === count(me) ? `You’re tied with ${ahead.display_name}. One more puts you ahead.` : `${gap} more ${metric} to overtake ${ahead.display_name}.`;
  }, [me, metric, standings]);

  const toast = (text: string) => { setNotice(text); window.setTimeout(() => setNotice(''), 3500); };
  const submitLog = async (event: FormEvent) => {
    event.preventDefault(); if (!supabase || !logKind) return;
    setBusy(true);
    const args = logKind === 'application' ? { p_group: group.id, p_company: company } : logKind === 'interview' ? { p_group: group.id, p_company: company, p_round: round } : { p_group: group.id, p_company: company };
    const rpc = logKind === 'application' ? 'quick_log_application' : logKind === 'interview' ? 'quick_log_interview' : 'confirm_employment';
    const { error: rpcError } = await supabase.rpc(rpc, args as never);
    setBusy(false);
    if (rpcError) return toast(message(rpcError));
    if (logKind === 'hired') celebrate(true); else celebrate();
    toast(logKind === 'hired' ? 'You’re officially hired! Massive.' : logKind === 'interview' ? 'Interview round logged.' : 'Application logged. Keep cooking.');
    setCompany(''); setRound(1); setLogKind(null); await refresh();
  };
  const removeApplication = async (id: string) => { if (!supabase || !confirm('Delete this application?')) return; const { error: rpcError } = await supabase.rpc('remove_application', { p_id: id }); if (rpcError) toast(message(rpcError)); else { toast('Application deleted.'); await refresh(); } };
  const removeInterview = async (id: string) => { if (!supabase || !confirm('Delete this interview?')) return; const { error: rpcError } = await supabase.rpc('remove_interview', { p_id: id }); if (rpcError) toast(message(rpcError)); else { toast('Interview deleted.'); await refresh(); } };
  const editApplication = async (item: AppRecord) => { const companyName = window.prompt('Company name', item.company_name)?.trim(); if (!supabase || !companyName) return; const { error: rpcError } = await supabase.rpc('rename_application', { p_id: item.id, p_company: companyName }); if (rpcError) toast(message(rpcError)); else { toast('Application updated.'); await refresh(); } };
  const editInterview = async (item: Interview) => { const companyName = window.prompt('Company name', item.company_name)?.trim(); if (!supabase || !companyName) return; const nextRound = Number(window.prompt('Interview round', String(item.round_number))); if (!Number.isInteger(nextRound) || nextRound < 1) return; const { error: rpcError } = await supabase.rpc('update_interview', { p_id: item.id, p_company: companyName, p_round: nextRound }); if (rpcError) toast(message(rpcError)); else { toast('Interview updated.'); await refresh(); } };
  const react = async (eventId: string, emoji: string) => { if (!supabase) return; const { error: rpcError } = await supabase.rpc('toggle_activity_reaction', { p_event: eventId, p_emoji: emoji }); if (rpcError) toast(message(rpcError)); else await refresh(); };

  if (loading) return <main className="race-app-loading"><div className="spinner"/><p>Loading the race…</p></main>;
  if (error) return <main className="race-app-loading"><h1>Couldn’t load the race</h1><p>{error}</p><button onClick={() => void refresh()}>Try again</button></main>;

  return <main className="race-app">
    <header className="race-app-header"><Logo tone="onLight" size={34}/><nav aria-label="Main navigation">{(['dashboard', 'feed', 'applications'] as View[]).map(item => <button className={view === item ? 'active' : ''} key={item} onClick={() => setView(item)}><span aria-hidden="true">{item === 'dashboard' ? '◫' : item === 'feed' ? '◌' : '▤'}</span>{item === 'applications' ? 'My applications' : item}</button>)}</nav><div><button className="header-log" onClick={() => setLogKind('application')}>+ Log</button><button className="profile-menu" onClick={() => void onSignOut()} aria-label="Sign out">↗</button></div></header>
    {notice && <div className="race-toast" role="status">{notice}</div>}
    {view === 'dashboard' && <section className="race-dashboard">
      <div className="race-hero"><p>THE BREADS UP RACE</p><h1>{me ? `You’re #${me.position}.` : 'The race is on.'}</h1><strong>{rivalry}</strong><button onClick={() => setLogKind('application')}>+ Log an application</button></div>
      <div className="metric-tabs" role="tablist"><button className={metric === 'applications' ? 'active' : ''} onClick={() => setMetric('applications')} role="tab">Applications</button><button className={metric === 'interviews' ? 'active' : ''} onClick={() => setMetric('interviews')} role="tab">Interviews</button></div>
      <div className="race-grid"><section className="leaderboard"><div className="section-heading"><div><p>LIVE STANDINGS</p><h2>{metric === 'applications' ? 'Application league' : 'Interview league'}</h2></div><button className="text-button" onClick={() => setLogKind(metric === 'applications' ? 'application' : 'interview')}>+ Log {metric === 'applications' ? 'application' : 'interview'}</button></div>
        {standings.map(person => <article className={`standing ${person.user_id === userId ? 'mine' : ''}`} key={person.user_id}><b className="standing-rank">#{person.position}</b><Avatar name={person.display_name} colour={person.colour} id={person.user_id} avatar={person.avatar}/><div className="standing-name"><strong>{person.display_name}{person.user_id === userId ? ' (you)' : ''}</strong>{person.status === 'employed' && <span>✓ employed</span>}</div><div className="standing-progress"><i><span style={{ width: `${(count(person) / max) * 100}%` }}/></i></div><b className="standing-count">{count(person)}<small>{metric}</small></b></article>)}
      </section><aside className="dashboard-aside"><section className="quick-actions"><button onClick={() => setLogKind('application')}>+ Application</button><button onClick={() => setLogKind('interview')}>◷ Interview</button><button className="hired" onClick={() => setLogKind('hired')}>★ I got hired!</button></section><section className="activity-preview"><div className="section-heading"><h2>Latest moves</h2><button className="text-button" onClick={() => setView('feed')}>See all</button></div>{activity.slice(0, 3).map(item => <p key={item.id}><b>{item.display_name}</b> {activityCopy(item)} <time>{relative(item.created_at)}</time></p>)}{!activity.length && <p className="quiet">The feed is quiet. Make the first move.</p>}</section></aside></div>
      <section className="finishers"><div className="section-heading"><div><p>HALL OF FAME</p><h2>{finishers.length ? 'Freshly employed' : 'No hires yet'}</h2></div></div>{finishers.length ? <div className="podium">{finishers.slice(0, 3).map(person => <article key={person.user_id}><b>#{person.hired_rank}</b><Avatar name={person.display_name} colour={person.colour} id={person.user_id} avatar={person.avatar}/><strong>{person.display_name}</strong><small>{person.hired_company}</small></article>)}</div> : <p>Be the first one to escape the group chat.</p>}</section>
    </section>}
    {view === 'feed' && <section className="feed-page"><div className="page-title"><p>LIVE COMMENTARY</p><h1>Feed</h1></div>{activity.map(item => <article className="activity-card" key={item.id}><Avatar name={item.display_name} colour={item.colour} id={item.actor_user_id} avatar={item.avatar}/><div><p><b>{item.display_name}</b> {activityCopy(item)}</p><time>{relative(item.created_at)}</time><div className="reaction-bar">{reactions.map(emoji => <button onClick={() => void react(item.id, emoji)} key={emoji}>{emoji}{item.reactions?.[emoji] ? <small>{item.reactions[emoji]}</small> : null}</button>)}</div></div></article>)}{!activity.length && <p className="empty-state">Nothing yet. Go create some workplace lore.</p>}</section>}
    {view === 'applications' && <section className="history-page"><div className="page-title"><p>YOUR PAPER TRAIL</p><h1>My applications</h1><button onClick={() => setLogKind('application')}>+ Add application</button></div><div className="metric-tabs"><button className={historyTab === 'applications' ? 'active' : ''} onClick={() => setHistoryTab('applications')}>Applications</button><button className={historyTab === 'interviews' ? 'active' : ''} onClick={() => setHistoryTab('interviews')}>Interviews</button></div>{historyTab === 'applications' ? <div className="history-list">{applications.filter(item => !item.deleted_at).map(item => <article key={item.id}><div><b>{item.company_name}</b><small>{new Date(item.created_at).toLocaleDateString('en-AU')}</small></div><aside><button onClick={() => void editApplication(item)}>Edit</button><button onClick={() => void removeApplication(item.id)}>Delete</button></aside></article>)}{!applications.some(item => !item.deleted_at) && <p className="empty-state">No applications yet. Start with one.</p>}</div> : <div className="history-list">{interviews.map(item => <article key={item.id}><div><b>{item.company_name}</b><small>Round {item.round_number} · {new Date(item.created_at).toLocaleDateString('en-AU')}</small></div><aside><button onClick={() => void editInterview(item)}>Edit</button><button onClick={() => void removeInterview(item.id)}>Delete</button></aside></article>)}{!interviews.length && <p className="empty-state">No interviews yet. Manifest one.</p>}</div>}</section>}
    <nav className="mobile-race-nav" aria-label="Main navigation">{(['dashboard', 'feed', 'applications'] as View[]).map(item => <button key={item} className={view === item ? 'active' : ''} onClick={() => setView(item)}><span aria-hidden="true">{item === 'dashboard' ? '◫' : item === 'feed' ? '◌' : '▤'}</span>{item === 'applications' ? 'Apps' : item}</button>)}<button className="mobile-log" onClick={() => setLogKind('application')} aria-label="Log an application">＋</button></nav>
    {logKind && <Dialog title={logKind === 'hired' ? 'You got hired?!' : logKind === 'interview' ? 'Log interview round' : 'Log an application'} onClose={() => setLogKind(null)}><form className="quick-log-form" onSubmit={submitLog}><p>{logKind === 'hired' ? 'This marks you as employed. Make sure it is real.' : logKind === 'interview' ? 'Every round counts. Keep climbing.' : 'Company name only. Fast fingers win races.'}</p><label>Company<input autoFocus maxLength={80} required value={company} onChange={event => setCompany(event.target.value)} placeholder="e.g. Canva"/></label>{logKind === 'interview' && <label>Round<input type="number" min="1" max="99" value={round} onChange={event => setRound(Number(event.target.value))}/></label>}<button disabled={busy}>{busy ? 'Saving…' : logKind === 'hired' ? 'Confirm: I got hired!' : 'Log it'}</button></form></Dialog>}
  </main>;
}
