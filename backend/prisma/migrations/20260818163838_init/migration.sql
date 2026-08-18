-- CreateTable
CREATE TABLE "users" (
    "id" UUID NOT NULL,
    "email" TEXT NOT NULL,
    "passwordHash" TEXT,
    "emailVerified" BOOLEAN NOT NULL DEFAULT false,
    "displayName" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "identities" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "provider" TEXT NOT NULL,
    "subject" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "identities_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "refresh_tokens" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "revokedAt" TIMESTAMP(3),
    "replacedById" UUID,
    "userAgent" TEXT,

    CONSTRAINT "refresh_tokens_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "trips" (
    "uuid" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "startDate" BIGINT NOT NULL,
    "endDate" BIGINT NOT NULL,
    "updatedAt" BIGINT NOT NULL DEFAULT 0,
    "deletedAt" BIGINT,

    CONSTRAINT "trips_pkey" PRIMARY KEY ("uuid")
);

-- CreateTable
CREATE TABLE "stays" (
    "uuid" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "tripUuid" UUID NOT NULL,
    "hotelName" TEXT NOT NULL,
    "checkInAt" BIGINT NOT NULL,
    "checkOutAt" BIGINT NOT NULL,
    "updatedAt" BIGINT NOT NULL DEFAULT 0,
    "deletedAt" BIGINT,

    CONSTRAINT "stays_pkey" PRIMARY KEY ("uuid")
);

-- CreateTable
CREATE TABLE "transport_legs" (
    "uuid" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "tripUuid" UUID NOT NULL,
    "type" TEXT NOT NULL,
    "departureAt" BIGINT NOT NULL,
    "fromLocation" TEXT NOT NULL,
    "toLocation" TEXT NOT NULL,
    "updatedAt" BIGINT NOT NULL DEFAULT 0,
    "deletedAt" BIGINT,

    CONSTRAINT "transport_legs_pkey" PRIMARY KEY ("uuid")
);

-- CreateTable
CREATE TABLE "items" (
    "uuid" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "tripUuid" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "category" TEXT NOT NULL DEFAULT 'other',
    "quantity" INTEGER NOT NULL DEFAULT 1,
    "packed" BOOLEAN NOT NULL DEFAULT false,
    "updatedAt" BIGINT NOT NULL DEFAULT 0,
    "deletedAt" BIGINT,

    CONSTRAINT "items_pkey" PRIMARY KEY ("uuid")
);

-- CreateTable
CREATE TABLE "packing_lists" (
    "uuid" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "createdAt" BIGINT NOT NULL,
    "updatedAt" BIGINT NOT NULL DEFAULT 0,
    "deletedAt" BIGINT,

    CONSTRAINT "packing_lists_pkey" PRIMARY KEY ("uuid")
);

-- CreateTable
CREATE TABLE "packing_list_items" (
    "uuid" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "listUuid" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "category" TEXT NOT NULL DEFAULT 'other',
    "quantity" INTEGER NOT NULL DEFAULT 1,
    "updatedAt" BIGINT NOT NULL DEFAULT 0,
    "deletedAt" BIGINT,

    CONSTRAINT "packing_list_items_pkey" PRIMARY KEY ("uuid")
);

-- CreateTable
CREATE TABLE "documents" (
    "uuid" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "tripUuid" UUID NOT NULL,
    "storageKey" TEXT,
    "label" TEXT NOT NULL,
    "updatedAt" BIGINT NOT NULL DEFAULT 0,
    "deletedAt" BIGINT,

    CONSTRAINT "documents_pkey" PRIMARY KEY ("uuid")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_email_key" ON "users"("email");

-- CreateIndex
CREATE INDEX "identities_userId_idx" ON "identities"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "identities_provider_subject_key" ON "identities"("provider", "subject");

-- CreateIndex
CREATE UNIQUE INDEX "refresh_tokens_tokenHash_key" ON "refresh_tokens"("tokenHash");

-- CreateIndex
CREATE INDEX "refresh_tokens_userId_idx" ON "refresh_tokens"("userId");

-- CreateIndex
CREATE INDEX "trips_userId_updatedAt_idx" ON "trips"("userId", "updatedAt");

-- CreateIndex
CREATE INDEX "stays_userId_updatedAt_idx" ON "stays"("userId", "updatedAt");

-- CreateIndex
CREATE INDEX "stays_tripUuid_idx" ON "stays"("tripUuid");

-- CreateIndex
CREATE INDEX "transport_legs_userId_updatedAt_idx" ON "transport_legs"("userId", "updatedAt");

-- CreateIndex
CREATE INDEX "transport_legs_tripUuid_idx" ON "transport_legs"("tripUuid");

-- CreateIndex
CREATE INDEX "items_userId_updatedAt_idx" ON "items"("userId", "updatedAt");

-- CreateIndex
CREATE INDEX "items_tripUuid_idx" ON "items"("tripUuid");

-- CreateIndex
CREATE INDEX "packing_lists_userId_updatedAt_idx" ON "packing_lists"("userId", "updatedAt");

-- CreateIndex
CREATE INDEX "packing_list_items_userId_updatedAt_idx" ON "packing_list_items"("userId", "updatedAt");

-- CreateIndex
CREATE INDEX "packing_list_items_listUuid_idx" ON "packing_list_items"("listUuid");

-- CreateIndex
CREATE INDEX "documents_userId_updatedAt_idx" ON "documents"("userId", "updatedAt");

-- CreateIndex
CREATE INDEX "documents_tripUuid_idx" ON "documents"("tripUuid");

-- AddForeignKey
ALTER TABLE "identities" ADD CONSTRAINT "identities_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "refresh_tokens" ADD CONSTRAINT "refresh_tokens_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "trips" ADD CONSTRAINT "trips_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stays" ADD CONSTRAINT "stays_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stays" ADD CONSTRAINT "stays_tripUuid_fkey" FOREIGN KEY ("tripUuid") REFERENCES "trips"("uuid") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "transport_legs" ADD CONSTRAINT "transport_legs_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "transport_legs" ADD CONSTRAINT "transport_legs_tripUuid_fkey" FOREIGN KEY ("tripUuid") REFERENCES "trips"("uuid") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "items" ADD CONSTRAINT "items_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "items" ADD CONSTRAINT "items_tripUuid_fkey" FOREIGN KEY ("tripUuid") REFERENCES "trips"("uuid") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "packing_lists" ADD CONSTRAINT "packing_lists_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "packing_list_items" ADD CONSTRAINT "packing_list_items_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "packing_list_items" ADD CONSTRAINT "packing_list_items_listUuid_fkey" FOREIGN KEY ("listUuid") REFERENCES "packing_lists"("uuid") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "documents" ADD CONSTRAINT "documents_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "documents" ADD CONSTRAINT "documents_tripUuid_fkey" FOREIGN KEY ("tripUuid") REFERENCES "trips"("uuid") ON DELETE CASCADE ON UPDATE CASCADE;
