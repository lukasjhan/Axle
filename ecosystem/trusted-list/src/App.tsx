import { useState } from 'react';
import { Check, Copy, Download } from 'lucide-react';

import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { cn } from '@/lib/utils';

// Canonical production origin the curl commands point at (the site itself may be served from a preview URL).
// Set VITE_SITE_URL at build time (e.g. Vercel env); falls back to the sandbox's production domain.
const SITE = import.meta.env.VITE_SITE_URL ?? 'https://trust.hopae.dev';

const FORMATS = [
  { key: 'jws', label: 'Compact JWS', hint: 'protected.payload.signature' },
  { key: 'jades.json', label: 'JAdES (JSON)', hint: 'Flattened JWS JSON serialization' },
] as const;

interface TrustList {
  slug: string;
  name: string;
  standard: string;
  description: string;
  available: boolean;
}

// The sandbox's trust services. Wallet Providers is live; the others are placeholders for the ecosystem to come.
const LISTS: TrustList[] = [
  {
    slug: 'wallet-providers',
    name: 'Wallet Providers',
    standard: 'ETSI TS 119 602 · Annex E',
    description: 'Trusted wallet solution providers. Wallet-unit attestations (WUAs) chain to the certificates on this list.',
    available: true,
  },
  {
    slug: 'pid-issuers',
    name: 'PID Issuers',
    standard: 'ETSI TS 119 602',
    description: 'Issuers of Person Identification Data (PID) credentials.',
    available: false,
  },
  {
    slug: 'registrar',
    name: 'Registrar',
    standard: 'ETSI TS 119 602',
    description: 'Registered relying parties and their trust anchors.',
    available: false,
  },
];

function CopyButton({ text, className }: { text: string; className?: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <Button
      variant="ghost"
      size="icon"
      className={cn('h-7 w-7 shrink-0 text-slate-300 hover:bg-slate-700 hover:text-white', className)}
      aria-label="Copy curl command"
      onClick={() => {
        navigator.clipboard?.writeText(text);
        setCopied(true);
        setTimeout(() => setCopied(false), 1500);
      }}
    >
      {copied ? <Check className="text-green-400" /> : <Copy />}
    </Button>
  );
}

export default function App() {
  return (
    <div className="min-h-screen bg-background">
      <div className="mx-auto max-w-3xl px-6 py-16">
        <header className="mb-10">
          <p className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">Hopae EUDI Sandbox</p>
          <h1 className="mt-2 text-3xl font-semibold tracking-tight">Trust Services</h1>
          <p className="mt-3 max-w-xl text-sm leading-relaxed text-muted-foreground">
            JAdES-signed Trusted Lists (ETSI TS 119 602) for the Hopae EUDI sandbox. Download the signed list
            for a service type, or fetch it with curl.
          </p>
        </header>

        <div className="space-y-4">
          {LISTS.map((list) => (
            <Card key={list.slug} className={cn(!list.available && 'opacity-60')}>
              <CardHeader>
                <div className="flex items-center gap-3">
                  <CardTitle className="text-xl">{list.name}</CardTitle>
                  {list.available ? (
                    <span className="rounded-full bg-green-100 px-2 py-0.5 text-xs font-medium text-green-700">Available</span>
                  ) : (
                    <span className="rounded-full bg-muted px-2 py-0.5 text-xs font-medium text-muted-foreground">Coming soon</span>
                  )}
                </div>
                <CardDescription className="flex flex-col gap-1 pt-1">
                  <span className="font-mono text-xs">{list.standard}</span>
                  <span>{list.description}</span>
                </CardDescription>
              </CardHeader>

              {list.available && (
                <CardContent className="space-y-3">
                  {FORMATS.map((f) => {
                    const file = `${list.slug}.${f.key}`;
                    const curl = `curl -O ${SITE}/tl/${file}`;
                    return (
                      <div key={f.key} className="rounded-lg border bg-muted/30 p-3">
                        <div className="flex items-center justify-between gap-3">
                          <div>
                            <div className="text-sm font-medium">{f.label}</div>
                            <div className="text-xs text-muted-foreground">{f.hint}</div>
                          </div>
                          <Button asChild size="sm" variant="outline" className="shrink-0">
                            <a href={`/tl/${file}`} download={file}>
                              <Download />
                              Download
                            </a>
                          </Button>
                        </div>
                        <div className="relative mt-3">
                          <pre className="whitespace-pre-wrap break-all rounded-md bg-slate-900 py-2 pl-3 pr-10 font-mono text-xs leading-relaxed text-slate-50">{curl}</pre>
                          <CopyButton text={curl} className="absolute right-1 top-1" />
                        </div>
                      </div>
                    );
                  })}
                </CardContent>
              )}
            </Card>
          ))}
        </div>

        <footer className="mt-12 border-t pt-6 text-xs leading-relaxed text-muted-foreground">
          <p>
            The Scheme Operator signing key is held offline; each list is re-issued at least every 6 months
            (Annex E nextUpdate).
          </p>
          <p className="mt-1 font-mono">
            ETSI TS 119 602 · ETSI TS 119 182-1 (JAdES) · sandbox — not a production trust list.
          </p>
        </footer>
      </div>
    </div>
  );
}
