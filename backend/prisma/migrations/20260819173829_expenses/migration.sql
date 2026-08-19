-- CreateTable
CREATE TABLE "expenses" (
    "uuid" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "tripUuid" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "amountMinor" INTEGER NOT NULL,
    "spentAt" BIGINT NOT NULL,
    "updatedAt" BIGINT NOT NULL DEFAULT 0,
    "deletedAt" BIGINT,

    CONSTRAINT "expenses_pkey" PRIMARY KEY ("uuid")
);

-- CreateIndex
CREATE INDEX "expenses_userId_updatedAt_idx" ON "expenses"("userId", "updatedAt");

-- CreateIndex
CREATE INDEX "expenses_tripUuid_idx" ON "expenses"("tripUuid");

-- AddForeignKey
ALTER TABLE "expenses" ADD CONSTRAINT "expenses_userId_fkey" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "expenses" ADD CONSTRAINT "expenses_tripUuid_fkey" FOREIGN KEY ("tripUuid") REFERENCES "trips"("uuid") ON DELETE CASCADE ON UPDATE CASCADE;
