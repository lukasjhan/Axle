import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

/**
 * Protects admin-only endpoints (revoke). Fail-closed: if `ADMIN_API_KEY` is unset the endpoint is DENIED
 * (not left open) — set the key to enable admin access.
 */
@Injectable()
export class AdminApiKeyGuard implements CanActivate {
  constructor(private readonly config: ConfigService) {}

  canActivate(context: ExecutionContext): boolean {
    const expected = this.config.get<string>('ADMIN_API_KEY');
    if (!expected) throw new UnauthorizedException('admin endpoint disabled: ADMIN_API_KEY is not configured');
    const req = context.switchToHttp().getRequest();
    if (req.headers['x-api-key'] !== expected) throw new UnauthorizedException('invalid admin api key');
    return true;
  }
}
