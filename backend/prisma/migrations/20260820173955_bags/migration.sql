-- AlterTable
ALTER TABLE "items" ADD COLUMN     "bagUuid" UUID;

-- CreateTable
CREATE TABLE "bags" (
    "uuid" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "tripUuid" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "updatedAt" BIGINT NOT NULL DEFAULT 0,
    "deletedAt" BIGINT,

    CONSTRAINT "bags_pkey" PRIMARY KEY ("uuid")
);

-- CreateIndex
CREATE INDEX "bags_userId_updatedAt_idx" ON "bags"("userId", "updatedAt");

-- CreateIndex
CREATE INDEX "bags_tripUuid_idx" ON "bags"("tripUuid");

-- CreateIndex
CREATE INDEX "items_bagUuid_idx" ON "items"("bagUuid");

-- AddForeignKey
ALTER TABLE "items" ADD CONSTRAINT "items_bagUuid_fkey" FOREIGN KEY ("bagUuid") REFERENCES "bags"("uuid") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bags" ADD CONSTRAINT "bags_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bags" ADD CONSTRAINT "bags_tripUuid_fkey" FOREIGN KEY ("tripUuid") REFERENCES "trips"("uuid") ON DELETE CASCADE ON UPDATE CASCADE;
