import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

/** Protects admin-only endpoints (revoke). If `ADMIN_API_KEY` is unset the endpoints are open (dev only). */
@Injectable()
export class AdminApiKeyGuard implements CanActivate {
  constructor(private readonly config: ConfigService) {}

  canActivate(context: ExecutionContext): boolean {
    const expected = this.config.get<string>('ADMIN_API_KEY');
    if (!expected) return true;
    const req = context.switchToHttp().getRequest();
    if (req.headers['x-api-key'] !== expected) throw new UnauthorizedException('invalid admin api key');
    return true;
  }
}
