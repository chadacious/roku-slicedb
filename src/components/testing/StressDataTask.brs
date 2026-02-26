sub init()
    m.top.functionName = "runBuild"
end sub

sub runBuild()
    req = m.top.request
    t = CreateObject("roTimespan")
    t.Mark()

    entries = []
    totalPayloadBytes = 0
    i = 0
    while i < req["count"]
        recordIndex = req["startIndex"] + i
        id = buildStressId(req, recordIndex)
        payloadLen = req["payloadMin"] + ((recordIndex * 37 + req["revision"] * 17) mod (req["payloadMax"] - req["payloadMin"] + 1))
        payloadText = buildStressPayloadText(id, req["operation"], req["revision"], payloadLen)
        totalPayloadBytes = totalPayloadBytes + Len(payloadText)

        entries.Push({
            "id": id
            "payloadText": payloadText
        })
        i = i + 1
    end while

    buildStoreFileFromPayloadEntries(req["path"], entries)

    m.top.response = {
        "operation": req["operation"]
        "path": req["path"]
        "count": req["count"]
        "revision": req["revision"]
        "elapsedMs": t.TotalMilliseconds()
        "totalPayloadBytes": totalPayloadBytes
    }
end sub

function buildStressId(req as object, recordIndex as integer) as string
    if req["operation"] = "add"
        return "rec-new-" + recordIndex.ToStr()
    end if
    return "rec-" + recordIndex.ToStr()
end function

function buildStressPayloadText(id as string, operation as string, revision as integer, payloadLen as integer) as string
    blob = buildBlob(payloadLen)
    payload = {
        "id": id
        "op": operation
        "rev": revision
        "text": blob
    }
    return FormatJson(payload)
end function

function buildBlob(targetLen as integer) as string
    chunk = "abcdefghijklmnopqrstuvwxyz0123456789"
    text = ""
    while Len(text) < targetLen
        text = text + chunk
    end while
    return Left(text, targetLen)
end function
