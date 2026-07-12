import { CanActivate, ExecutionContext, Injectable, Logger } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ConfigService } from '@nestjs/config';
import { createHash } from 'node:crypto';
import { calculateJwkThumbprint, importJWK, jwtVerify, type JWK } from 'jose';
import { SessionStore } from '../session/session.store';
import { IssuerJwtService } from '../jwt/issuer-jwt.service';
import { OAuthError } from '../vci/oauth-error';
import { DpopNonceService } from './dpop-nonce.service';
import { DPOP_TYPE } from './dpop.decorator';

const norm = (u: string) => u.replace(/\/+$/, '');
const s256 = (v: string) => createHash('sha256').update(v).digest('base64url');

/**
 * OAuth 2.0 DPoP (RFC 9449, HAIP-mandated). Verifies the `dpop` proof (typ/alg/jwk, htm, htu, freshness, jti
 * replay), enforces the server-provided DPoP-Nonce challenge, and for resource endpoints checks `ath` and the
 * access-token→key binding (`cnf.jkt`). Exposes `request.dpopJkt`. Every DPoP response carries a fresh
 * DPoP-Nonce so wallets can (re)challenge.
 */
@Injectable()
export class DpopGuard implements CanActivate {
  private readonly logger = new Logger(DpopGuard.name);

  constructor(
    private readonly reflector: Reflector,
    private readonly nonces: DpopNonceService,
    private readonly store: SessionStore,
    private readonly issuerJwt: IssuerJwtService,
    private readonly config: ConfigService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const type = this.reflector.get<'as' | 'rs'>(DPOP_TYPE, context.getHandler());
    const req = context.switchToHttp().getRequest();
    const res = context.switchToHttp().getResponse();

    // Always hand the wallet a fresh nonce (RFC 9449 §8/§9) so it can retry the challenge.
    const freshNonce = await this.nonces.issue();
    res.header('DPoP-Nonce', freshNonce);

    const challengeStatus = type === 'rs' ? 401 : 400;
    const proof: string | undefined = Array.isArray(req.headers['dpop']) ? req.headers['dpop'][0] : req.headers['dpop'];
    if (!proof) throw new OAuthError('use_dpop_nonce', 'DPoP proof required', challengeStatus);

    let payload: Record<string, unknown>;
    let jwk: JWK;
    try {
      const parts = JSON.parse(Buffer.from(proof.split('.')[0], 'base64url').toString());
      if (parts.typ !== 'dpop+jwt' || parts.alg !== 'ES256' || !parts.jwk || parts.jwk.d) {
        throw new Error('bad dpop header');
      }
      jwk = parts.jwk;
      const verified = await jwtVerify(proof, await importJWK(jwk, 'ES256'), { typ: 'dpop+jwt' });
      payload = verified.payload as Record<string, unknown>;
    } catch (e) {
      this.logger.warn(`dpop proof invalid: ${(e as Error).message}`);
      throw new OAuthError('invalid_dpop_proof', 'DPoP proof verification failed', challengeStatus);
    }

    // htm / htu / freshness
    const now = Math.floor(Date.now() / 1000);
    const path = (req.url as string).split('?')[0];
    const expectedHtu = new URL(this.config.getOrThrow<string>('ISSUER_BASE_URL')).origin + path;
    if (payload.htm !== req.method) throw new OAuthError('invalid_dpop_proof', 'htm mismatch', challengeStatus);
    if (norm(String(payload.htu)) !== norm(expectedHtu)) {
      throw new OAuthError('invalid_dpop_proof', 'htu mismatch', challengeStatus);
    }
    if (typeof payload.iat !== 'number' || Math.abs(now - payload.iat) > 60) {
      throw new OAuthError('invalid_dpop_proof', 'iat out of window', challengeStatus);
    }

    // Server-provided nonce challenge.
    if (!(await this.nonces.isValid(payload.nonce as string | undefined))) {
      throw new OAuthError('use_dpop_nonce', 'DPoP nonce required', challengeStatus);
    }

    // Single-use jti.
    if (!payload.jti || !(await this.store.setOnce(`dpop:jti:${payload.jti}`, 600))) {
      throw new OAuthError('invalid_dpop_proof', 'DPoP proof replay', challengeStatus);
    }

    const jkt = await calculateJwkThumbprint(jwk, 'sha256');

    // Resource endpoint: verify ath + access-token binding.
    if (type === 'rs') {
      const auth: string | undefined = req.headers['authorization'];
      const token = auth?.startsWith('DPoP ') ? auth.slice(5) : undefined;
      if (!token) throw new OAuthError('invalid_token', 'DPoP-bound access token required', 401);
      if (payload.ath !== s256(token)) throw new OAuthError('invalid_dpop_proof', 'ath mismatch', 401);
      let tokenPayload;
      try {
        tokenPayload = await this.issuerJwt.verify(token, { typ: 'at+jwt' });
      } catch {
        throw new OAuthError('invalid_token', 'access token invalid', 401);
      }
      if ((tokenPayload.cnf as { jkt?: string } | undefined)?.jkt !== jkt) {
        throw new OAuthError('invalid_token', 'access token not bound to this key', 401);
      }
      req.accessToken = tokenPayload;
    }

    req.dpopJkt = jkt;
    return true;
  }
}
