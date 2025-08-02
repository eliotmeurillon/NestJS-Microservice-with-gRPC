import { PRODUCTS_PACKAGE_NAME } from './../../../../types/proto/products';
import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { ClientsModule, Transport } from '@nestjs/microservices';
import { join } from 'path';
import { ProductController } from './product/product.controller';

@Module({
  imports: [
    ClientsModule.register([
      {
        name: PRODUCTS_PACKAGE_NAME,
        transport: Transport.GRPC,
        options: {
          package: PRODUCTS_PACKAGE_NAME,
          protoPath: join(__dirname, 'proto/products.proto'),
          url: process.env.PRODUCTS_SERVICE_URL || 'localhost:5001',
        },
      },
    ]),
  ],
  controllers: [AppController, ProductController],
  providers: [AppService],
})
export class AppModule {}
