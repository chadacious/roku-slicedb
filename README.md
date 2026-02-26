# Roku SliceDB

Roku SliceDB is a lightweight, file-backed key/value record store for BrightScript.

It is designed for large datasets where you only want small index metadata in memory and lazy-load payloads from disk by byte range.

## Highlights
- Generic (not cue-specific)
- Single-file format with fixed header + JSON index + payload bytes
- `roByteArray.ReadFile(path, offset, length)` slice reads
- Multi-generation `StoreRegistry` with newest-wins resolution by record id
- Task-based chunked compaction with snapshot-version guard and abort support
- Works in SceneGraph apps

## Repo Layout
- `src/` Roku app source (runnable stress harness by default)
- `src/components/core/` reusable runtime components to copy into other projects
- `src/components/testing/` self-test/stress-test harness files
- `tools/` local generator/validator for mock DB files
- `fixtures/mock/` generated mock DB files

## DB File Format (v1)
- Header: 128 bytes
  - `magic` (8 bytes): `RSDBV001`
  - `indexOffset` (ascii padded numeric field)
  - `indexLength` (ascii padded numeric field)
  - `payloadOffset` (ascii padded numeric field)
  - `payloadLength` (ascii padded numeric field)
- Index: UTF-8 JSON with `byId` and `byIndex`
- Payload: concatenated JSON payload bytes (slice by stored offset/length)

## Run the Roku sample app
1. Zip the `src/` folder as a Roku package payload.
2. Sideload to device.
3. Open telnet console (`8085`) and watch logs.

The default test scene runs a stress flow:
- build base generation: 3200 variable-size records (~10MB payload)
- apply update generation: 1000 record updates
- apply add generation: 100 new records
- run compaction abort test (abort + rejected commit)
- run compaction retry
- run 1000-record updates at 5 second intervals (3 cycles), compacting each cycle

Expected completion log:
- `[SliceDB] stress-test PASS`

Metric logs include:
- `build.operation=... count=... bytes=... ms=...`
- `compaction.ms=... aborted=... chunks=...`
- `compaction.commitMs=... mergedCount=...`

## Integrating Into Another Project
Copy files from:
- `src/components/core/`

Do not copy:
- `src/components/testing/` (test harness only)

## Generate a larger mock file locally
```bash
cd /Users/chad/Projects/chadacious/roku-slicedb
node ./tools/generate-mock-db.mjs 3000 ./fixtures/mock/cues-3000.rsdb
node ./tools/validate-mock-db.mjs ./fixtures/mock/cues-3000.rsdb
```
