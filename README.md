# Roku SliceDB

Roku SliceDB is a lightweight, file-backed key/value record store for BrightScript.

It is designed for large datasets where you only want small index metadata in memory and lazy-load payloads from disk by byte range.

## Highlights
- Generic (not cue-specific)
- Single-file format with fixed header + JSON index + framed payloads
- `roByteArray.ReadFile(path, offset, length)` slice reads
- Multi-generation `StoreRegistry` with newest-wins resolution by record id
- Chunked compaction with snapshot-version guard and abort support
- Works in SceneGraph apps

## Repo Layout
- `src/` Roku app source (runnable sample)
- `tools/` local generator/validator for mock DB files
- `fixtures/mock/` generated mock DB files

## DB File Format (v1)
- Header: 128 bytes
  - `magic` (8 bytes): `RSDBV001`
  - `version` (u32 LE)
  - `indexOffset` (u32 LE)
  - `indexLength` (u32 LE)
  - `payloadOffset` (u32 LE)
  - `payloadLength` (u32 LE)
- Index: UTF-8 JSON with `byId` and `byIndex`
- Payload: framed records `[u32le length][json bytes]`

## Run the Roku sample app
1. Zip the `src/` folder as a Roku package payload.
2. Sideload to device.
3. Open telnet console (`8085`) and watch logs.

The sample scene will:
- build a small mock DB in `tmp:/sample.rsdb`
- open it with `RangeDb`
- run a few assertions

## Generate a larger mock file locally
```bash
cd /Users/chad/Projects/chadacious/roku-slicedb
node ./tools/generate-mock-db.mjs 3000 ./fixtures/mock/cues-3000.rsdb
node ./tools/validate-mock-db.mjs ./fixtures/mock/cues-3000.rsdb
```
