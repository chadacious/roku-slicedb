#!/usr/bin/env node
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const count = Number(process.argv[2] || 100);
const outPath = resolve(process.argv[3] || './fixtures/mock/sample.rsdb');

const headerSize = 128;
const payloadFrames = [];
const byId = {};
const byIndex = [];

let cursor = headerSize;

for (let i = 0; i < count; i += 1) {
  const id = `cue-${i}`;
  const payloadObj = {
    id,
    value: i,
    lang: i % 2 === 0 ? 'en' : 'es',
    text: `Sample payload ${i}`,
  };

  const payload = Buffer.from(JSON.stringify(payloadObj), 'utf8');
  const frame = Buffer.allocUnsafe(4 + payload.length);
  frame.writeUInt32LE(payload.length, 0);
  payload.copy(frame, 4);

  payloadFrames.push(frame);

  const meta = { id, o: cursor, l: payload.length };
  byId[id] = meta;
  byIndex.push(meta);

  cursor += frame.length;
}

const payloadBlock = Buffer.concat(payloadFrames);
const indexBuf = Buffer.from(JSON.stringify({ byId, byIndex }), 'utf8');
const indexOffset = headerSize + payloadBlock.length;

const header = Buffer.alloc(headerSize);
header.write('RSDBV001', 0, 'ascii');
header.writeUInt32LE(1, 8);
header.writeUInt32LE(indexOffset, 12);
header.writeUInt32LE(indexBuf.length, 16);
header.writeUInt32LE(headerSize, 20);
header.writeUInt32LE(payloadBlock.length, 24);

const fileBuf = Buffer.concat([header, payloadBlock, indexBuf]);
mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, fileBuf);

console.log(`Wrote ${count} records to ${outPath} (${fileBuf.length} bytes)`);
