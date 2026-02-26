#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const filePath = resolve(process.argv[2] || './fixtures/mock/sample.rsdb');
const buf = readFileSync(filePath);

const magic = buf.subarray(0, 8).toString('ascii');
if (magic !== 'RSDBV001') throw new Error(`Invalid magic: ${magic}`);

const indexOffset = buf.readUInt32LE(12);
const indexLength = buf.readUInt32LE(16);
const index = JSON.parse(buf.subarray(indexOffset, indexOffset + indexLength).toString('utf8'));

const first = index.byIndex[0];
const payloadLen = buf.readUInt32LE(first.o);
const payload = JSON.parse(buf.subarray(first.o + 4, first.o + 4 + payloadLen).toString('utf8'));

console.log({
  filePath,
  bytes: buf.length,
  records: index.byIndex.length,
  firstId: first.id,
  firstPayloadId: payload.id,
});
