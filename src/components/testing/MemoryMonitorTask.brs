sub init()
    m.top.functionName = "runMemoryMonitor"
end sub

sub runMemoryMonitor()
    port = CreateObject("roMessagePort")
    m.top.ObserveField("snapshotRequest", port)

    monitor = invalid
    try
        monitor = CreateObject("roAppMemoryMonitor")
    catch e
        monitor = invalid
    end try

    supported = monitor <> invalid
    if supported
        monitor.SetMessagePort(port)
        monitor.EnableMemoryWarningEvent(true)
    end if

    sendSnapshot(monitor, "status", {
        "tag": "startup"
    })

    while true
        msg = wait(0, port)
        msgType = type(msg)

        if msgType = "roAppMemoryMonitorEvent"
            sendSnapshot(monitor, "warning", {
                "tag": "memory-warning"
            })
        else if msgType = "roSGNodeEvent"
            field = msg.GetField()
            if field = "snapshotRequest"
                req = msg.GetData()
                sendSnapshot(monitor, "requested", req)
            end if
        end if
    end while
end sub

sub sendSnapshot(monitor as dynamic, reason as string, req = invalid as dynamic)
    if req = invalid then req = {}
    sendUIMessage({
        "type": "MEMORY_SNAPSHOT"
        "reason": reason
        "tag": req["tag"]
        "availableMemoryMb": getAvailableMemoryMb(monitor)
        "channelMemoryLimit": getChannelMemoryLimit(monitor)
        "memoryLimitPercent": getMemoryLimitPercent(monitor)
    })
end sub

function getAvailableMemoryMb(monitor as dynamic) as dynamic
    if monitor = invalid then return invalid
    value = invalid
    try
        value = monitor.GetChannelAvailableMemory()
    catch e
        value = invalid
    end try
    return value
end function

function getChannelMemoryLimit(monitor as dynamic) as dynamic
    if monitor = invalid then return invalid
    value = invalid
    try
        value = monitor.GetChannelMemoryLimit()
    catch e
        value = invalid
    end try
    return value
end function

function getMemoryLimitPercent(monitor as dynamic) as dynamic
    if monitor = invalid then return invalid
    value = invalid
    try
        value = monitor.GetMemoryLimitPercent()
    catch e
        value = invalid
    end try
    return value
end function

sub sendUIMessage(message as object)
    m.top.uiMessage = message
end sub
