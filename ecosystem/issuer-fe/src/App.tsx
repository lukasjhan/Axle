import { useEffect, useState } from 'react';

const BE = import.meta.env.VITE_ISSUER_BE_URL ?? 'http://localhost:3400';

interface Field {
  label: string;
  value: string;
}
interface Credential {
  id: string;
  name: string;
  format: string;
  fields: Field[];
}
interface Interaction {
  demo: boolean;
  client_id: string;
  credentials: Credential[];
}

type State =
  | { s: 'loading' }
  | { s: 'error'; msg: string }
  | { s: 'ready'; data: Interaction }
  | { s: 'submitting' }
  | { s: 'done' };

const FORMAT_LABEL: Record<string, string> = {
  'dc+sd-jwt': 'SD-JWT VC',
  mso_mdoc: 'ISO mdoc',
};

// A stylised ring — evokes an EU-official identity document without reproducing the actual EU emblem.
function Emblem() {
  return (
    <svg viewBox="0 0 48 48" className="h-9 w-9" aria-hidden="true">
      <circle cx="24" cy="24" r="22" fill="#00246b" stroke="#ffcc00" strokeWidth="1.5" />
      <rect x="14" y="17" width="20" height="14" rx="2" fill="none" stroke="#ffcc00" strokeWidth="1.6" />
      <circle cx="19.5" cy="22.5" r="2.4" fill="#ffcc00" />
      <line x1="24" y1="21" x2="30" y2="21" stroke="#ffcc00" strokeWidth="1.4" strokeLinecap="round" />
      <line x1="24" y1="24" x2="30" y2="24" stroke="#ffcc00" strokeWidth="1.4" strokeLinecap="round" />
      <line x1="16.5" y1="27.5" x2="31.5" y2="27.5" stroke="#ffcc00" strokeWidth="1.2" strokeLinecap="round" />
    </svg>
  );
}

export default function App() {
  const [state, setState] = useState<State>({ s: 'loading' });
  const session = new URLSearchParams(window.location.search).get('session');

  useEffect(() => {
    if (!session) {
      setState({ s: 'error', msg: 'Missing issuance session. Open this page from your wallet.' });
      return;
    }
    fetch(`${BE}/eudi-issuer/interaction/${session}`)
      .then((r) => {
        if (!r.ok) throw new Error(`This issuance session is invalid or has expired.`);
        return r.json();
      })
      .then((data: Interaction) => setState({ s: 'ready', data }))
      .catch((e) => setState({ s: 'error', msg: e.message }));
  }, [session]);

  async function decide(approve: boolean) {
    setState({ s: 'submitting' });
    try {
      const r = await fetch(`${BE}/eudi-issuer/interaction/${session}/decide`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ approve }),
      });
      const { redirect } = await r.json();
      setState({ s: 'done' });
      window.location.href = redirect; // back to the wallet
    } catch {
      setState({ s: 'error', msg: 'Could not complete the request. Please try again from your wallet.' });
    }
  }

  return (
    <div className="min-h-screen bg-slate-100 font-sans text-slate-900">
      {/* Demo flow banner */}
      <div className="bg-amber-400 text-amber-950">
        <div className="mx-auto max-w-2xl px-4 py-1.5 text-center text-xs font-semibold tracking-wide">
          DEMO FLOW · Sandbox — no real authentication, no real personal data
        </div>
      </div>

      {/* Official-style header */}
      <header className="bg-eu-blue text-white">
        <div className="mx-auto flex max-w-2xl items-center gap-3 px-4 py-4">
          <Emblem />
          <div className="leading-tight">
            <div className="text-[13px] font-semibold uppercase tracking-wider text-eu-gold">EUDI Wallet</div>
            <div className="text-lg font-semibold">Personal ID — Issuance</div>
          </div>
          <div className="ml-auto text-right text-[11px] text-white/70">
            Hopae EUDI Sandbox
            <br />
            Luxembourg
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-2xl px-4 py-8">
        {state.s === 'loading' && <Centered>Loading your issuance request…</Centered>}
        {state.s === 'done' && <Centered>Returning to your wallet…</Centered>}
        {state.s === 'error' && (
          <div className="rounded-xl border border-red-200 bg-red-50 p-6 text-red-800">
            <p className="font-semibold">Unable to continue</p>
            <p className="mt-1 text-sm">{state.msg}</p>
          </div>
        )}

        {(state.s === 'ready' || state.s === 'submitting') && (
          <Ready
            data={(state.s === 'ready' ? state.data : lastData(state)) as Interaction}
            busy={state.s === 'submitting'}
            onDecide={decide}
          />
        )}
      </main>
    </div>
  );
}

// Keep the last-rendered data available while submitting (avoids a flash).
let cached: Interaction | null = null;
function lastData(_: State): Interaction | null {
  return cached;
}

function Ready({ data, busy, onDecide }: { data: Interaction; busy: boolean; onDecide: (a: boolean) => void }) {
  cached = data;
  return (
    <div>
      <h1 className="text-xl font-semibold tracking-tight">Review your credential</h1>
      <p className="mt-1 text-sm text-slate-600">
        Your wallet requested the following {data.credentials.length === 1 ? 'credential' : 'credentials'}. Review
        the details, then issue {data.credentials.length === 1 ? 'it' : 'them'} to your wallet.
      </p>

      <div className="mt-6 space-y-4">
        {data.credentials.map((c) => (
          <section key={c.id} className="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
            <div className="flex items-center justify-between border-b border-slate-100 bg-slate-50 px-5 py-3">
              <h2 className="font-semibold text-eu-deep">{c.name}</h2>
              <span className="rounded-full bg-eu-blue/10 px-2.5 py-0.5 text-xs font-medium text-eu-blue">
                {FORMAT_LABEL[c.format] ?? c.format}
              </span>
            </div>
            <dl className="divide-y divide-slate-100">
              {c.fields.map((f) => (
                <div key={f.label} className="flex gap-4 px-5 py-2.5 text-sm">
                  <dt className="w-40 shrink-0 text-slate-500">{f.label}</dt>
                  <dd className="font-medium text-slate-900">{f.value}</dd>
                </div>
              ))}
            </dl>
          </section>
        ))}
      </div>

      <p className="mt-4 text-xs text-slate-500">
        Issued by the Centre des technologies de l'information de l'État (CTIE), Luxembourg — sandbox. Client:{' '}
        <span className="font-mono">{data.client_id}</span>
      </p>

      <div className="mt-6 flex flex-col gap-3 sm:flex-row-reverse">
        <button
          onClick={() => onDecide(true)}
          disabled={busy}
          className="inline-flex items-center justify-center rounded-lg bg-eu-blue px-6 py-3 font-semibold text-white shadow-sm transition hover:bg-eu-deep disabled:opacity-60"
        >
          {busy ? 'Issuing…' : 'Issue to wallet'}
        </button>
        <button
          onClick={() => onDecide(false)}
          disabled={busy}
          className="inline-flex items-center justify-center rounded-lg border border-slate-300 bg-white px-6 py-3 font-semibold text-slate-700 transition hover:bg-slate-50 disabled:opacity-60"
        >
          Cancel
        </button>
      </div>

      <footer className="mt-10 border-t border-slate-200 pt-4 text-center text-[11px] text-slate-400">
        OpenID4VCI 1.0 · HAIP · ETSI SD-JWT VC / ISO 18013-5 mdoc — Hopae EUDI Sandbox (not a production service)
      </footer>
    </div>
  );
}

function Centered({ children }: { children: React.ReactNode }) {
  return <div className="py-20 text-center text-slate-500">{children}</div>;
}
