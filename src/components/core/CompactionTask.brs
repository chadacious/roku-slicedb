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
        payloadBytes = CreateObject("roByteArray")
        ok = payloadBytes.ReadFile(sourcePath, resolver["meta"]["o"], resolver["meta"]["l"])
        if not ok then stop

        entries.Push({
            "id": id
            "payloadBytes": payloadBytes
        })

        if entries.Count() >= req["maxRecordsPerChunk"]
            chunkId = "cmp-" + chunkIndex.ToStr()
            chunkPath = req["pathPrefix"] + "-" + chunkIndex.ToStr() + ".rsdb"
            buildStoreFileFromPayloadEntries(chunkPath, entries)
            chunkGenerationIds.Push(chunkId)
            chunkPaths.Push(chunkPath)
            chunkIndex = chunkIndex + 1
            entries = []
        end if
    end for

    if entries.Count() > 0
        chunkId = "cmp-" + chunkIndex.ToStr()
        chunkPath = req["pathPrefix"] + "-" + chunkIndex.ToStr() + ".rsdb"
        buildStoreFileFromPayloadEntries(chunkPath, entries)
        chunkGenerationIds.Push(chunkId)
        chunkPaths.Push(chunkPath)
    end if

    m.top.response = {
        "aborted": false
        "snapshotVersion": req["snapshotVersion"]
        "chunkGenerationIds": chunkGenerationIds
        "chunkPaths": chunkPaths
    }
    print "[SliceDB] CompactionTask run complete"
end sub
