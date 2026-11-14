import { createCodiQr } from '../src/lib/pey.js';

async function main(): Promise<void> {
  const result = await createCodiQr({
    amountCents: 1,
    concept: 'smoke',
    numRef: '1000001',
    expirationSec: 600,
    metadata: { smoke: true },
  });

  console.log(
    JSON.stringify({
      id: result.id,
      qrStringLength: result.qrString.length,
    })
  );
}

main().catch((err: unknown) => {
  const message = err instanceof Error ? err.message : 'Unknown error';
  console.error(`pey smoke failed: ${message}`);
  process.exit(1);
});
