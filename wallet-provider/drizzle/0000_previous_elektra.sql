CREATE TABLE "wallet_instances" (
	"instance_id" uuid PRIMARY KEY NOT NULL,
	"public_jwk" jsonb NOT NULL,
	"platform" varchar(20) NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"revoked" boolean DEFAULT false NOT NULL,
	"revoked_at" timestamp
);
