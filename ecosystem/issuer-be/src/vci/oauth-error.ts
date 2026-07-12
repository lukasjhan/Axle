import { HttpException } from '@nestjs/common';

/** An OAuth 2.0 / OpenID4VCI error response ({ error, error_description }) with the right HTTP status. */
export class OAuthError extends HttpException {
  constructor(error: string, description?: string, status = 400) {
    super({ error, ...(description ? { error_description: description } : {}) }, status);
  }
}
