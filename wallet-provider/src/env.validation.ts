import { plainToInstance } from 'class-transformer';
import { IsNotEmpty, IsOptional, IsString, validateSync } from 'class-validator';

class EnvironmentVariables {
  @IsString()
  @IsNotEmpty()
  STAGE: string;

  @IsString()
  @IsNotEmpty()
  PORT: string;

  @IsString()
  @IsNotEmpty()
  DATABASE_URL: string;

  /** The Wallet Provider issuer/base URL — the `iss` of the WUA/key-attestation JWTs and the PoP audience. */
  @IsString()
  @IsNotEmpty()
  WP_ISSUER: string;

  /** Android app package for real Play Integrity verification (else the dev-integrity stub is used). */
  @IsOptional()
  @IsString()
  PLAY_INTEGRITY_PACKAGE_NAME?: string;

  /** Service-account key path for Google decode (Play Integrity). Consumed by google-auth-library directly. */
  @IsOptional()
  @IsString()
  GOOGLE_APPLICATION_CREDENTIALS?: string;
}

export function validate(config: Record<string, unknown>) {
  const validated = plainToInstance(EnvironmentVariables, config, {
    enableImplicitConversion: true,
  });
  const errors = validateSync(validated, { skipMissingProperties: false });
  if (errors.length > 0) {
    throw new Error(
      `Environment validation failed:\n${errors.map((e) => `  - ${Object.values(e.constraints ?? {}).join(', ')}`).join('\n')}`,
    );
  }
  return validated;
}
