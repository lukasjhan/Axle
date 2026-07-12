// Builds + JAdES-signs the Trusted List and writes it into public/tl/ (static, served by the Vite site /
// Vercel). Re-run whenever an entity changes or at least every 6 months (Annex E nextUpdate), then commit.
//   npm run gen:tl
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { buildLote } from './build-lote.mjs';
import { signJades } from './sign-jades.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');

let soKeystore;
try {
  soKeystore = JSON.parse(readFileSync(join(root, 'secrets/so-keystore.json'), 'utf8'));
} catch {
  console.error('missing secrets/so-keystore.json — run `npm run gen:so-key` first');
  process.exit(1);
}

const at = new Date();
const lote = buildLote(root, at);
const jades = signJades(lote, soKeystore, at);
const jadesStr = JSON.stringify(jades, null, 2);

// Two artifacts are published, both signed: the JAdES JSON serialization and its compact form.
writeFileSync(join(root, 'public/tl/wallet-providers.jades.json'), jadesStr + '\n'); // JAdES JSON serialization

// Compact JWS (protected.payload.signature) — the machine distribution point referenced by the scheme's
// distributionPoints / selfPointerUri. Valid here because the JAdES has no (populated) unprotected header.
const jws = `${jades.protected}.${jades.payload}.${jades.signature}`;
writeFileSync(join(root, 'public/tl/wallet-providers.jws'), jws + '\n');

const info = lote.listAndSchemeInformation;
console.log('Trusted List generated → public/tl/');
console.log(`  ${info.schemeName}`);
console.log(`  seq #${info.loteSequenceNumber} · issued ${info.listIssueDateTime.slice(0, 10)} · next update ${info.nextUpdate.slice(0, 10)}`);
console.log(`  entities: ${lote.trustedEntitiesList.map((e) => e.trustedEntityInformation.teName).join(', ')}`);
console.log(`  wallet-providers.jades.json (${jadesStr.length} bytes) + .jws (compact)`);
