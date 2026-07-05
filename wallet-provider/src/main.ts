import { NestFactory } from '@nestjs/core';
import { Logger } from '@nestjs/common';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  const port = process.env.PORT ?? 3200;
  await app.listen(port);
  new Logger('Bootstrap').log(`EUDI Wallet Provider listening on :${port}`);
}
void bootstrap();
