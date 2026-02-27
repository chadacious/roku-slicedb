sub init()
    m.top.functionName = "runBuild"
end sub

sub runBuild()
    req = m.top.request
    t = CreateObject("roTimespan")
    t.Mark()

    entries = []
    records = []
    totalPayloadBytes = 0
    i = 0
    while i < req["count"]
        recordIndex = req["startIndex"] + i
        id = buildStressId(req, recordIndex)
        payloadLen = req["payloadMin"] + ((recordIndex * 37 + req["revision"] * 17) mod (req["payloadMax"] - req["payloadMin"] + 1))
        payloadObj = buildStressPayloadObject(id, req["operation"], req["revision"], payloadLen)
        payloadText = FormatJson(payloadObj)
        totalPayloadBytes = totalPayloadBytes + Len(payloadText)

        entries.Push({
            "id": id
            "payloadText": payloadText
        })
        if req["emitRecordObjects"]
            records.Push({
                "id": id
                "payload": payloadObj
            })
        end if
        i = i + 1
    end while

    if req["writeStoreFile"]
        buildStoreFileFromPayloadEntries(req["path"], entries)
    end if

    m.top.response = {
        "operation": req["operation"]
        "path": req["path"]
        "count": req["count"]
        "revision": req["revision"]
        "elapsedMs": t.TotalMilliseconds()
        "totalPayloadBytes": totalPayloadBytes
        "records": records
    }
end sub

function buildStressId(req as object, recordIndex as integer) as string
    if req["operation"] = "add"
        return "rec-new-" + recordIndex.ToStr()
    end if
    return "rec-" + recordIndex.ToStr()
end function

function buildStressPayloadObject(id as string, operation as string, revision as integer, payloadLen as integer) as object
    blob = buildBlob(payloadLen)
    payload = {
        "id": id
        "op": operation
        "rev": revision
        "text": blob
    }
    return payload
end function

function buildBlob(targetLen as integer) as string
    chunk = "abcdefghijklmnopqrstuvwxyz0123456789"
    text = ""
    while Len(text) < targetLen
        text = text + chunk
    end while
    return Left(text, targetLen)
end function
