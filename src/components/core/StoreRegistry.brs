function StoreRegistry() as object
    reg = {
        "stores": {}
        "generationOrder": []
        "resolverById": {}
        "mergedOrder": []
        "version": 1
    }
    return reg
end function

sub StoreRegistry_addGeneration(reg as object, generationId as string, path as string)
    store = RangeDb(path)
    reg["stores"][generationId] = store
    reg["generationOrder"].Push(generationId)

    for each meta in store["indexObj"]["byIndex"]
        id = meta.id
        resolver = {
            "generationId": generationId
            "meta": meta
        }

        isNew = reg["resolverById"][id] = invalid
        reg["resolverById"][id] = resolver
        if isNew then reg["mergedOrder"].Push(id)
    end for

    reg["version"] = reg["version"] + 1
end sub

sub StoreRegistry_removeGeneration(reg as object, generationId as string)
    reg["stores"].Delete(generationId)

    nextOrder = []
    for each id in reg["generationOrder"]
        if id <> generationId then nextOrder.Push(id)
    end for
    reg["generationOrder"] = nextOrder

    ' Removing a generation can expose older values, so rebuild resolver state.
    StoreRegistry_rebuildResolver(reg)
    reg["version"] = reg["version"] + 1
end sub

sub StoreRegistry_swapWithCompactedGeneration(reg as object, compactedGenerationId as string, compactedPath as string, removeGenerationIds as object)
    ' Add the compacted snapshot first so reads can continue without gaps.
    StoreRegistry_addGeneration(reg, compactedGenerationId, compactedPath)

    for each id in removeGenerationIds
        if id <> compactedGenerationId then StoreRegistry_removeGeneration(reg, id)
    end for
end sub

function StoreRegistry_beginCompactionSnapshot(reg as object) as object
    snapshotIds = []
    for each id in reg["generationOrder"]
        snapshotIds.Push(id)
    end for

    return {
        "version": reg["version"]
        "generationIds": snapshotIds
    }
end function

function StoreRegistry_buildCompactionRequest(reg as object, snapshot as object, pathPrefix as string, maxRecordsPerChunk as integer) as object
    generationPaths = {}
    for each generationId in snapshot["generationIds"]
        generationPaths[generationId] = reg["stores"][generationId]["path"]
    end for

    mergedOrder = []
    resolverById = {}
    for each id in reg["mergedOrder"]
        mergedOrder.Push(id)
        resolver = reg["resolverById"][id]
        resolverById[id] = {
            "generationId": resolver["generationId"]
            "meta": {
                "id": resolver["meta"]["id"]
                "o": resolver["meta"]["o"]
                "l": resolver["meta"]["l"]
            }
        }
    end for

    return {
        "snapshotVersion": snapshot["version"]
        "generationIds": snapshot["generationIds"]
        "generationPaths": generationPaths
        "mergedOrder": mergedOrder
        "resolverById": resolverById
        "pathPrefix": pathPrefix
        "maxRecordsPerChunk": maxRecordsPerChunk
    }
end function

function StoreRegistry_commitChunkedCompaction(reg as object, result as object, removeGenerationIds as object) as boolean
    if result["aborted"] then return false
    if result["snapshotVersion"] <> reg["version"] then return false

    i = 0
    while i < result["chunkGenerationIds"].Count()
        StoreRegistry_addGeneration(reg, result["chunkGenerationIds"][i], result["chunkPaths"][i])
        i = i + 1
    end while

    for each id in removeGenerationIds
        StoreRegistry_removeGeneration(reg, id)
    end for

    return true
end function

function StoreRegistry_getById(reg as object, id as string) as dynamic
    resolver = reg["resolverById"][id]
    store = reg["stores"][resolver["generationId"]]
    return RangeDb_readPayload(store, resolver["meta"])
end function

function StoreRegistry_getMetaById(reg as object, id as string) as dynamic
    return reg["resolverById"][id]["meta"]
end function

function StoreRegistry_getByMergedIndex(reg as object, i as integer) as dynamic
    id = reg["mergedOrder"][i]
    return StoreRegistry_getById(reg, id)
end function

sub StoreRegistry_rebuildResolver(reg as object)
    reg["resolverById"] = {}
    reg["mergedOrder"] = []

    ' Replay generations in order; later generations override earlier ids.
    for each generationId in reg["generationOrder"]
        store = reg["stores"][generationId]
        for each meta in store["indexObj"]["byIndex"]
            id = meta.id
            resolver = {
                "generationId": generationId
                "meta": meta
            }

            isNew = reg["resolverById"][id] = invalid
            reg["resolverById"][id] = resolver
            if isNew then reg["mergedOrder"].Push(id)
        end for
    end for
end sub
