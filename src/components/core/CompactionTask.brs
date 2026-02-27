sub init()
    m.top.functionName = "runCompaction"
end sub

sub runCompaction()
    print "[SliceDB] CompactionTask run start"
    req = m.top.request
    entries = []
    chunkPaths = []
    chunkGenerationIds = []
    chunkIndex = 0
    chunkPayloadBytes = 0
    maxPayloadBytesPerChunk = req["maxPayloadBytesPerChunk"]
    if maxPayloadBytesPerChunk = invalid then maxPayloadBytesPerChunk = 0

    for each id in req["mergedOrder"]
        if m.top.abortCompaction then
            print "[SliceDB] CompactionTask aborted"
            m.top.response = {
                "aborted": true
                "snapshotVersion": req["snapshotVersion"]
                "chunkGenerationIds": []
                "chunkPaths": []
            }
            return
        end if

        resolver = req["resolverById"][id]
        sourcePath = req["generationPaths"][resolver["generationId"]]
        recordPayloadBytes = resolver["meta"]["l"]

        if entries.Count() > 0 and maxPayloadBytesPerChunk > 0 and (chunkPayloadBytes + recordPayloadBytes) > maxPayloadBytesPerChunk
            flushChunk(req["pathPrefix"], entries, chunkGenerationIds, chunkPaths, chunkIndex)
            chunkIndex = chunkIndex + 1
            entries = []
            chunkPayloadBytes = 0
        end if

        payloadBytes = CreateObject("roByteArray")
        ok = payloadBytes.ReadFile(sourcePath, resolver["meta"]["o"], recordPayloadBytes)
        if not ok then stop

        entries.Push({
            "id": id
            "payloadBytes": payloadBytes
        })
        chunkPayloadBytes = chunkPayloadBytes + recordPayloadBytes

        if entries.Count() >= req["maxRecordsPerChunk"] or (maxPayloadBytesPerChunk > 0 and chunkPayloadBytes >= maxPayloadBytesPerChunk)
            flushChunk(req["pathPrefix"], entries, chunkGenerationIds, chunkPaths, chunkIndex)
            chunkIndex = chunkIndex + 1
            entries = []
            chunkPayloadBytes = 0
        end if
    end for

    if entries.Count() > 0
        flushChunk(req["pathPrefix"], entries, chunkGenerationIds, chunkPaths, chunkIndex)
    end if

    m.top.response = {
        "aborted": false
        "snapshotVersion": req["snapshotVersion"]
        "chunkGenerationIds": chunkGenerationIds
        "chunkPaths": chunkPaths
    }
    print "[SliceDB] CompactionTask run complete"
end sub

sub flushChunk(pathPrefix as string, entries as object, chunkGenerationIds as object, chunkPaths as object, chunkIndex as integer)
    chunkId = "cmp-" + chunkIndex.ToStr()
    chunkPath = pathPrefix + "-" + chunkIndex.ToStr() + ".rsdb"
    buildStoreFileFromPayloadEntries(chunkPath, entries)
    chunkGenerationIds.Push(chunkId)
    chunkPaths.Push(chunkPath)
end sub
