function StoreFile_pad10(n as integer) as string
    s = n.ToStr()
    while Len(s) < 10
        s = "0" + s
    end while
    return s
end function

function StoreFile_join(parts as object, separator as string) as string
    if parts.Count() = 0 then return ""
    output = parts[0]
    for i = 1 to parts.Count() - 1
        output = output + separator + parts[i]
    end for
    return output
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
    byIdParts = []
    byIndexParts = []
    offset = payloadOffset

    for each entry in entries
        itemBytes = CreateObject("roByteArray")
        itemBytes.FromAsciiString(entry.payloadText)
        itemLen = itemBytes.Count()

        byIdParts.Push(Chr(34) + entry.id + Chr(34) + ":" + "{" + Chr(34) + "id" + Chr(34) + ":" + Chr(34) + entry.id + Chr(34) + "," + Chr(34) + "o" + Chr(34) + ":" + offset.ToStr() + "," + Chr(34) + "l" + Chr(34) + ":" + itemLen.ToStr() + "}")
        byIndexParts.Push("{" + Chr(34) + "id" + Chr(34) + ":" + Chr(34) + entry.id + Chr(34) + "," + Chr(34) + "o" + Chr(34) + ":" + offset.ToStr() + "," + Chr(34) + "l" + Chr(34) + ":" + itemLen.ToStr() + "}")

        payloadBytes.Append(itemBytes)
        offset = offset + itemLen
    end for

    indexJson = "{" + Chr(34) + "byId" + Chr(34) + ":{" + StoreFile_join(byIdParts, ",") + "}," + Chr(34) + "byIndex" + Chr(34) + ":[" + StoreFile_join(byIndexParts, ",") + "]}"

    indexBytes = CreateObject("roByteArray")
    indexBytes.FromAsciiString(indexJson)
    indexOffset = payloadOffset + payloadBytes.Count()

    headerText = "RSDBV001" + StoreFile_pad10(indexOffset) + StoreFile_pad10(indexBytes.Count()) + StoreFile_pad10(payloadOffset) + StoreFile_pad10(payloadBytes.Count())
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
