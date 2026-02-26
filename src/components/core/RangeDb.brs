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
