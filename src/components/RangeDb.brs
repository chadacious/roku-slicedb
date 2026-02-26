function RangeDb(path as string) as object
    db = {
        "path": path
        "headerSize": 128
        "indexObj": invalid
    }
    RangeDb_open(db)
    return db
end function

sub RangeDb_open(db as object)
    headerBytes = CreateObject("roByteArray")
    ok = headerBytes.ReadFile(db.path, 0, db.headerSize)
    if not ok then stop

    headerText = headerBytes.ToAsciiString()
    magic = Left(headerText, 8)
    if magic <> "RSDBV001" then stop

    indexOffset = val(Mid(headerText, 9, 10))
    indexLength = val(Mid(headerText, 19, 10))

    indexBytes = CreateObject("roByteArray")
    ok = indexBytes.ReadFile(db.path, indexOffset, indexLength)
    if not ok then stop

    db["indexObj"] = ParseJson(indexBytes.ToAsciiString())
end sub

function RangeDb_getMetaById(db as object, id as string) as dynamic
    return db.indexObj.byId[id]
end function

function RangeDb_getMetaByIndex(db as object, i as integer) as dynamic
    return db.indexObj.byIndex[i]
end function

function RangeDb_getById(db as object, id as string) as dynamic
    meta = RangeDb_getMetaById(db, id)
    return RangeDb_readPayload(db, meta)
end function

function RangeDb_getByIndex(db as object, i as integer) as dynamic
    meta = RangeDb_getMetaByIndex(db, i)
    return RangeDb_readPayload(db, meta)
end function

function RangeDb_readPayload(db as object, meta as object) as dynamic
    return ParseJson(RangeDb_readPayloadText(db, meta))
end function

function RangeDb_readPayloadText(db as object, meta as object) as string
    payloadBytes = CreateObject("roByteArray")
    ok = payloadBytes.ReadFile(db.path, meta.o, meta.l)
    if not ok then stop
    return payloadBytes.ToAsciiString()
end function

function RangeDb_pad10(n as integer) as string
    s = n.ToStr()
    while Len(s) < 10
        s = "0" + s
    end while
    return s
end function

sub buildStoreFile(path as string, records as object)
    entries = []
    for each record in records
        entries.Push({
            "id": record.id
            "payloadText": FormatJson(record)
        })
    end for
    buildStoreFileFromPayloadEntries(path, entries)
end sub

sub buildStoreFileFromPayloadEntries(path as string, entries as object)
    headerSize = 128
    payloadOffset = headerSize
    payloadBytes = CreateObject("roByteArray")
    byIndex = []
    byIdParts = []
    byIndexParts = []
    offset = payloadOffset

    for each entry in entries
        itemJson = entry.payloadText
        itemBytes = CreateObject("roByteArray")
        itemBytes.FromAsciiString(itemJson)
        itemLen = itemBytes.Count()

        meta = {
            "id": entry.id
            "o": offset
            "l": itemLen
        }
        byIndex.Push(meta)

        byIdParts.Push(Chr(34) + entry.id + Chr(34) + ":" + "{" + Chr(34) + "id" + Chr(34) + ":" + Chr(34) + entry.id + Chr(34) + "," + Chr(34) + "o" + Chr(34) + ":" + offset.ToStr() + "," + Chr(34) + "l" + Chr(34) + ":" + itemLen.ToStr() + "}")
        byIndexParts.Push("{" + Chr(34) + "id" + Chr(34) + ":" + Chr(34) + entry.id + Chr(34) + "," + Chr(34) + "o" + Chr(34) + ":" + offset.ToStr() + "," + Chr(34) + "l" + Chr(34) + ":" + itemLen.ToStr() + "}")

        payloadBytes.Append(itemBytes)
        offset = offset + itemLen
    end for

    indexJson = "{" + Chr(34) + "byId" + Chr(34) + ":{" + RangeDb_join(byIdParts, ",") + "}," + Chr(34) + "byIndex" + Chr(34) + ":[" + RangeDb_join(byIndexParts, ",") + "]}"

    indexBytes = CreateObject("roByteArray")
    indexBytes.FromAsciiString(indexJson)
    indexOffset = payloadOffset + payloadBytes.Count()

    headerText = "RSDBV001" + RangeDb_pad10(indexOffset) + RangeDb_pad10(indexBytes.Count()) + RangeDb_pad10(payloadOffset) + RangeDb_pad10(payloadBytes.Count())
    while Len(headerText) < headerSize
        headerText = headerText + " "
    end while

    header = CreateObject("roByteArray")
    header.FromAsciiString(headerText)

    out = CreateObject("roByteArray")
    out.Append(header)
    out.Append(payloadBytes)
    out.Append(indexBytes)
    out.WriteFile(path)
end sub

sub buildSampleDb(path as string)
    records = [
        {
            "id": "a"
            "value": 101
        }
        {
            "id": "b"
            "value": 202
        }
    ]
    buildStoreFile(path, records)
end sub

function buildGenerationSelfTestFiles() as object
    basePath = "tmp:/store-base.rsdb"
    gen1Path = "tmp:/store-gen1.rsdb"
    compactedPath = "tmp:/store-compacted.rsdb"

    baseRecords = [
        {
            "id": "a"
            "value": 101
        }
        {
            "id": "b"
            "value": 202
        }
    ]

    gen1Records = [
        {
            "id": "b"
            "value": 999
        }
        {
            "id": "c"
            "value": 303
        }
    ]

    buildStoreFile(basePath, baseRecords)
    buildStoreFile(gen1Path, gen1Records)
    ' Compacted generation represents resolved latest state.
    buildStoreFile(compactedPath, [
        {
            "id": "a"
            "value": 101
        }
        {
            "id": "b"
            "value": 999
        }
        {
            "id": "c"
            "value": 303
        }
    ])

    return {
        "basePath": basePath
        "gen1Path": gen1Path
        "compactedPath": compactedPath
    }
end function

function RangeDb_join(parts as object, separator as string) as string
    if parts.Count() = 0 then return ""
    output = parts[0]
    for i = 1 to parts.Count() - 1
        output = output + separator + parts[i]
    end for
    return output
end function
