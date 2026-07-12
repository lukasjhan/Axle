import { Body, Controller, Get, Header, Param, Post, Res, UseGuards } from '@nestjs/common';
import type { FastifyReply } from 'fastify';
import { AdminApiKeyGuard } from '../common/admin-api-key.guard';
import { StatusListService } from './status-list.service';

@Controller('status-lists')
export class StatusListController {
  constructor(private readonly statusList: StatusListService) {}

  /** IETF Token Status List — the signed Status List Token (media type `application/statuslist+jwt`). */
  @Get(':id')
  async get(@Param('id') id: string, @Res() reply: FastifyReply) {
    const token = await this.statusList.statusListToken(id);
    void reply.header('Content-Type', 'application/statuslist+jwt').header('Cache-Control', 'no-store').send(token);
  }

  /** Admin: revoke a credential by its status index. */
  @Post('revoke')
  @UseGuards(AdminApiKeyGuard)
  @Header('Cache-Control', 'no-store')
  async revoke(@Body() body: { status_idx: number }) {
    const ok = await this.statusList.revoke(Number(body.status_idx));
    return { revoked: ok, status_idx: body.status_idx };
  }
}
