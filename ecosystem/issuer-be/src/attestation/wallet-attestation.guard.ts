import { CanActivate, ExecutionContext, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { decodeProtectedHeader, importJWK, jwtVerify, type JWK } from 'jose';
import { TrustedListService } from '../trust/trusted-list.service';
import { SessionStore } from '../session/session.store';
import { OAuthError } from '../vci/oauth-error';
import { verifyX5cToAnchors } from './x5c-chain.util';

export interface AttestationResult {
  /** Wallet instance identifier (attestation `sub`) — becomes the OAuth `client_id`. */
  sub: string;
  /** The instance key bound in the attestation (`cnf.jwk`). */
  cnfJwk?: JWK;
  dev?: boolean;
}

/**
 * OAuth 2.0 Attestation-Based Client Authentication (HAIP §4.4.1, OID4VCI Appendix E) — this IS the Wallet
 * Unit Attestation (WUA) check. Verifies the `oauth-client-attestation` JWT (its x5c chains to a Wallet
 * Provider CA published in the Trusted List) plus its `oauth-client-attestation-pop` proof, and exposes
 * `request.attestation`. `DEV_ATTESTATION_BYPASS=true` accepts wallets without an attestation (local dev).
 */
@Injectable()
export class WalletAttestationGuard implements CanActivate {
  private readonly logger = new Logger(WalletAttestationGuard.name);

  constructor(
    private readonly trust: TrustedListService,
    private readonly store: SessionStore,
    private readonly config: ConfigService,
  ) {}

  private get issuer(): string {
    return this.config.getOrThrow<string>('ISSUER_BASE_URL');
  }

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const req = context.switchToHttp().getRequest();

    if (this.config.get<string>('DEV_ATTESTATION_BYPASS') === 'true') {
      const clientId = req.body?.client_id ?? 'dev-wallet';
      req.attestation = { sub: clientId, dev: true } satisfies AttestationResult;
      return true;
    }

    const attJwt: string | undefined = req.headers['oauth-client-attestation'];
    const popJwt: string | undefined = req.headers['oauth-client-attestation-pop'];
    if (!attJwt || !popJwt) {
      throw new OAuthError('invalid_client', 'missing wallet attestation headers', 401);
    }

    try {
      // 1) Attestation JWT: verify its x5c chains to a trusted Wallet Provider CA, then its own signature.
      const header = decodeProtectedHeader(attJwt);
      if (header.typ !== 'oauth-client-attestation+jwt') throw new Error('bad attestation typ');
      if (!header.x5c?.length) throw new Error('attestation missing x5c');
      const leafJwk = await verifyX5cToAnchors(header.x5c, await this.trust.getWalletProviderCAs());
      const { payload: att } = await jwtVerify(attJwt, await importJWK(leafJwk, header.alg ?? 'ES256'));
      const cnf = (att.cnf as { jwk?: JWK } | undefined)?.jwk;
      if (!att.sub || !cnf) throw new Error('attestation missing sub/cnf.jwk');

      // 2) PoP JWT: signed by the attested instance key; iss = attestation sub; aud includes this issuer.
      const { payload: pop } = await jwtVerify(popJwt, await importJWK(cnf, 'ES256'), {
        typ: 'oauth-client-attestation-pop+jwt',
      });
      if (pop.iss !== att.sub) throw new Error('pop iss != attestation sub');
      const auds = Array.isArray(pop.aud) ? pop.aud : [pop.aud];
      if (!auds.includes(this.issuer)) throw new Error('pop aud mismatch');
      if (pop.jti && !(await this.store.setOnce(`att-pop:jti:${pop.jti}`, 600))) {
        throw new Error('pop replay');
      }

      req.attestation = { sub: String(att.sub), cnfJwk: cnf } satisfies AttestationResult;
      return true;
    } catch (e) {
      this.logger.warn(`wallet attestation rejected: ${(e as Error).message}`);
      throw new OAuthError('invalid_client', 'wallet attestation verification failed', 401);
    }
  }
}
