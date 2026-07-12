import { SetMetadata } from '@nestjs/common';

export const DPOP_TYPE = 'dpop_type';

/** Marks a route as DPoP-protected. 'as' = token/PAR (no `ath`); 'rs' = credential (requires `ath` + token binding). */
export const Dpop = (type: 'as' | 'rs') => SetMetadata(DPOP_TYPE, type);
