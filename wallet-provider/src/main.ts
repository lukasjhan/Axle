import { NestFactory } from '@nestjs/core';
import { Logger, ValidationPipe } from '@nestjs/common';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.enableShutdownHooks();
  app.enableCors();
  app.useGlobalPipes(new ValidationPipe({ whitelist: false, transform: true }));
  app.setGlobalPrefix('wp');

  const port = process.env.PORT ?? 3200;
  await app.listen(port, '0.0.0.0');
  new Logger('Bootstrap').log(`EUDI Wallet Provider listening on :${port} (prefix /wp)`);
}
void bootstrap();
