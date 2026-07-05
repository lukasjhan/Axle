// End-to-end exercise of the Wallet Provider: nonce -> register -> PoP -> WUA -> verify -> key attestation.
import * as jose from 'jose';

const BASE = process.env.BASE ?? 'http://localhost:3200';
const ISS = 'https://wallet-provider.hopae.dev';
const post = (path, body) =>
  fetch(`${BASE}${path}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
const assert = (cond, msg) => { if (!cond) throw new Error(`assertion failed: ${msg}`); };

async function main() {
  // 1) challenge + wallet instance key
  const { nonce } = await (await fetch(`${BASE}/nonce`)).json();
  const { publicKey, privateKey } = await jose.generateKeyPair('ES256', { extractable: true });
  const instanceJwk = await jose.exportJWK(publicKey);

  // 2) register instance (dev integrity token)
  const reg = await (await post('/wallet-instances', { instanceKey: instanceJwk, integrityToken: `dev-integrity:${nonce}`, nonce })).json();
  assert(reg.instanceId, 'instanceId returned');
  console.log('registered:', reg.instanceId);

  // 3) PoP over a fresh nonce, signed by the instance key
  const { nonce: popNonce } = await (await fetch(`${BASE}/nonce`)).json();
  const pop = await new jose.SignJWT({ nonce: popNonce })
    .setProtectedHeader({ typ: 'oauth-client-attestation-pop+jwt', alg: 'ES256' })
    .setAudience(ISS).setIssuedAt().sign(privateKey);

  // 4) obtain the WUA
  const wuaResp = await (await post('/wallet-attestation', { instanceId: reg.instanceId, pop })).json();
  assert(wuaResp.wallet_attestation, 'WUA returned');
  const wua = wuaResp.wallet_attestation;

  // 5) verify the WUA: header, x5c, signature, cnf binding
  const header = jose.decodeProtectedHeader(wua);
  assert(header.typ === 'oauth-client-attestation+jwt', 'WUA typ');
  assert(Array.isArray(header.x5c) && header.x5c.length === 2, 'x5c = [signer, CA]');
  const signerPub = await jose.importX509(`-----BEGIN CERTIFICATE-----\n${header.x5c[0]}\n-----END CERTIFICATE-----`, 'ES256');
  const { payload } = await jose.jwtVerify(wua, signerPub, { issuer: ISS });
  assert(JSON.stringify(payload.cnf.jwk) === JSON.stringify(instanceJwk), 'cnf.jwk binds the instance key');
  console.log(`WUA verified: iss=${payload.iss} sub=${payload.sub} aal=${payload.aal}`);

  // 6) PoP replay must fail (nonce single-use)
  const replay = await post('/wallet-attestation', { instanceId: reg.instanceId, pop });
  assert(replay.status >= 400, 'PoP replay rejected');
  console.log('replay rejected:', replay.status);

  // 7) key attestation (issuer c_nonce passed through)
  const { publicKey: credPub } = await jose.generateKeyPair('ES256', { extractable: true });
  const credJwk = await jose.exportJWK(credPub);
  const kaResp = await (await post('/key-attestation', { attestedKeys: [credJwk], nonce: 'c-nonce-xyz' })).json();
  const kaHeader = jose.decodeProtectedHeader(kaResp.key_attestation);
  const kaPub = await jose.importX509(`-----BEGIN CERTIFICATE-----\n${kaHeader.x5c[0]}\n-----END CERTIFICATE-----`, 'ES256');
  const { payload: ka } = await jose.jwtVerify(kaResp.key_attestation, kaPub, { issuer: ISS });
  assert(kaHeader.typ === 'keyattestation+jwt', 'key attestation typ');
  assert(ka.nonce === 'c-nonce-xyz' && Array.isArray(ka.attested_keys), 'key attestation binds keys + nonce');
  console.log('key attestation verified: attested_keys=%d nonce=%s', ka.attested_keys.length, ka.nonce);

  console.log('\n✅ ALL WALLET PROVIDER FLOWS PASSED');
}
main().catch((e) => { console.error('❌', e.message); process.exit(1); });
