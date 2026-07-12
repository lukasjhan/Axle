// Verifies every generated Trusted List the way a wallet / verifier would: check the JAdES signature against
// the embedded signer cert, confirm §6.8 (signer C == Scheme Territory, O == Scheme operator name), and that
// the list is still fresh (now < nextUpdate). Prints the listed entities. Exits non-zero if any list fails.
//   npm run verify:tl
//
// Verified with node crypto rather than jose: JAdES marks `sigT` critical (crit), which jose rejects as an
// unrecognized extension — a JAdES-aware verifier validates the ES256 signature directly instead.
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { X509Certificate, verify as cryptoVerify } from 'node:crypto';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const tlDir = join(root, 'public/tl');

const files = readdirSync(tlDir).filter((f) => f.endsWith('.jades.json')).sort();
let allOk = true;

for (const file of files) {
  const jades = JSON.parse(readFileSync(join(tlDir, file), 'utf8'));
  const header = JSON.parse(Buffer.from(jades.protected, 'base64url').toString());
  const cert = new X509Certificate(`-----BEGIN CERTIFICATE-----\n${header.x5c[0]}\n-----END CERTIFICATE-----`);

  // JAdES ES256 signature = raw R||S (ieee-p1363) over `${protected}.${payload}`.
  const signingInput = Buffer.from(`${jades.protected}.${jades.payload}`);
  const sigValid = cryptoVerify('sha256', signingInput, { key: cert.publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(jades.signature, 'base64url'));

  const lote = JSON.parse(Buffer.from(jades.payload, 'base64url').toString());
  const info = lote.listAndSchemeInformation;
  const subject = cert.subject.replaceAll('\n', ', ');
  const cMatch = new RegExp(`(^|, )C=${info.schemeTerritory}(,|$)`).test(subject);
  const oMatch = subject.includes(`O=${info.schemeOperatorName}`);
  const fresh = new Date(info.nextUpdate) > new Date();
  const ok = sigValid && cMatch && oMatch && fresh;
  allOk = allOk && ok;

  console.log(`\n${ok ? '✓' : '✗'} ${file}  —  ${info.schemeName}`);
  console.log('  signature:', sigValid ? 'valid (x5c[0])' : 'INVALID', `· x5t#S256=${header['x5t#S256'] ? 'yes' : 'no'} · crit=${JSON.stringify(header.crit)}`);
  console.log(`  §6.8 bind: C==${info.schemeTerritory}→${cMatch} · O==${info.schemeOperatorName}→${oMatch} · fresh(<${info.nextUpdate.slice(0, 10)})→${fresh}`);
  for (const e of lote.trustedEntitiesList) {
    for (const s of e.trustedEntityServices) {
      console.log(`    · ${e.trustedEntityInformation.teName} — ${s.serviceName}  [${s.serviceDigitalIdentity.x509SubjectName}]`);
    }
  }
}

console.log(`\n${allOk ? '✓ all lists verified' : '✗ one or more lists FAILED'} (${files.length} lists)`);
process.exit(allOk ? 0 : 1);
