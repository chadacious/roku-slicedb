sub init()
    m.top.backgroundURI = ""
    m.loadingSpinner = m.top.findNode("loadingSpinner")
    m.statusLabel = m.top.findNode("statusLabel")
    m.memoryLabel = m.top.findNode("memoryLabel")
    m.logContainer = m.top.findNode("logContainer")
    m.logLines = []
    m.maxLogLines = 22
    m.logLineNodes = []
    setupLogLineNodes()
    m.isBusy = true
    if m.loadingSpinner <> invalid
        m.loadingSpinner.poster.uri = "pkg:/images/loading.png"
        m.loadingSpinner.poster.blendcolor = "0xFFFFFFFF"
        m.loadingSpinner.poster.width = 80
        m.loadingSpinner.poster.height = 80
        m.loadingSpinner.visible = true
        m.loadingSpinner.control = "start"
    end if

    logLine("[SliceDB] MainScene init")

    m.reg = StoreRegistry()
    m.clearTransientState = false
    m.storageRoot = "cachefs:/"
    m.baseCount = 3200
    m.intervalUpdateCount = 1000
    m.intervalCycles = 3
    m.intervalCycleIndex = 0
    m.currentPhase = "init"

    m.bootTimer = CreateObject("roSGNode", "Timer")
    m.bootTimer.duration = 0.05
    m.bootTimer.repeat = false
    m.bootTimer.observeFieldScoped("fire", "onBootTimerFire")
    m.top.appendChild(m.bootTimer)
    m.bootTimer.control = "start"

    startMemoryMonitor()
    logLine("[SliceDB][cfg] clearTransientState=" + m.clearTransientState.ToStr())
    logLine("[SliceDB][cfg] storageRoot=" + m.storageRoot)
end sub

sub onBootTimerFire(event as object)
    setStatus("Building base generation")
    logLine("[SliceDB] stress test start")
    requestMemorySnapshot("stress-start")
    startBaseBuild()
end sub

sub startBaseBuild()
    request = {
        "operation": "base"
        "path": makeDbPath("stress-base.rsdb")
        "count": m.baseCount
        "startIndex": 0
        "revision": 0
        "payloadMin": 2200
        "payloadMax": 4300
    }
    m.currentPhase = "base"
    startStressBuildTask(request)
end sub

sub startFirstUpdateBuild()
    request = {
        "operation": "update"
        "path": makeDbPath("stress-update-1k.rsdb")
        "count": 1000
        "startIndex": 0
        "revision": 1
        "payloadMin": 1500
        "payloadMax": 4200
    }
    m.currentPhase = "update-1k"
    startStressBuildTask(request)
end sub

sub startAddBuild()
    request = {
        "operation": "add"
        "path": makeDbPath("stress-add-100.rsdb")
        "count": 100
        "startIndex": 0
        "revision": 2
        "payloadMin": 1000
        "payloadMax": 2600
    }
    m.currentPhase = "add-100"
    startStressBuildTask(request)
end sub

sub startIntervalUpdateBuild()
    startIndex = (m.intervalCycleIndex * 173) mod m.baseCount
    request = {
        "operation": "update"
        "path": makeDbPath("stress-interval-update-" + m.intervalCycleIndex.ToStr() + ".rsdb")
        "count": m.intervalUpdateCount
        "startIndex": startIndex
        "revision": 10 + m.intervalCycleIndex
        "payloadMin": 1400
        "payloadMax": 4200
    }
    m.currentPhase = "interval-update"
    startStressBuildTask(request)
end sub

sub startStressBuildTask(request as object)
    task = CreateObject("roSGNode", "StressDataTask")
    m.stressTask = task
    task.observeFieldScoped("response", "onStressBuildResponse")
    task["request"] = request
    task.control = "RUN"
end sub

sub onStressBuildResponse(event as object)
    res = event.GetData()
    if res = invalid then return

    logLine("[SliceDB][metric] build.operation=" + res["operation"] + " count=" + res["count"].ToStr() + " bytes=" + res["totalPayloadBytes"].ToStr() + " ms=" + res["elapsedMs"].ToStr())

    if m.currentPhase = "base"
        StoreRegistry_addGeneration(m.reg, "base", res["path"])
        logLine("[SliceDB][metric] mergedCount=" + m.reg["mergedOrder"].Count().ToStr())
        requestMemorySnapshot("after-base-build")
        clearStressBuildTaskState()
        setStatus("Applying first 1k updates")
        startFirstUpdateBuild()
        return
    end if

    if m.currentPhase = "update-1k"
        StoreRegistry_addGeneration(m.reg, "u1", res["path"])
        requestMemorySnapshot("after-update-1k")
        clearStressBuildTaskState()
        setStatus("Applying add +100 generation")
        startAddBuild()
        return
    end if

    if m.currentPhase = "add-100"
        StoreRegistry_addGeneration(m.reg, "add100", res["path"])
        ' First compaction run is intentionally aborted.
        requestMemorySnapshot("after-add-100")
        clearStressBuildTaskState()
        setStatus("Compaction (abort test)")
        startCompaction("post-add", true)
        return
    end if

    if m.currentPhase = "interval-update"
        genId = "u-int-" + m.intervalCycleIndex.ToStr()
        StoreRegistry_addGeneration(m.reg, genId, res["path"])
        requestMemorySnapshot("after-interval-update-" + m.intervalCycleIndex.ToStr())
        clearStressBuildTaskState()
        setStatus("Compaction after interval update")
        startCompaction("interval", false)
        return
    end if
end sub

sub startCompaction(stage as string, shouldAbort as boolean)
    snapshot = StoreRegistry_beginCompactionSnapshot(m.reg)
    request = StoreRegistry_buildCompactionRequest(m.reg, snapshot, makeDbPath("stress-cmp-" + stage + "-" + snapshot["version"].ToStr()), 500)
    requestMemorySnapshot("before-compaction-" + stage)

    m.compactionStage = stage
    m.compactionShouldAbort = shouldAbort
    m.compactionStart = CreateObject("roTimespan")
    m.compactionStart.Mark()

    task = CreateObject("roSGNode", "CompactionTask")
    m.compactionTask = task
    task.observeFieldScoped("response", "onCompactionResponse")
    task["request"] = request
    task.control = "RUN"

    if shouldAbort
        abortTimer = CreateObject("roSGNode", "Timer")
        m.abortTimer = abortTimer
        abortTimer.duration = 0.2
        abortTimer.repeat = false
        abortTimer.observeFieldScoped("fire", "onAbortTimerFire")
        m.top.appendChild(abortTimer)
        abortTimer.control = "start"
    end if
end sub

sub onAbortTimerFire(event as object)
    if m.compactionTask <> invalid
        m.compactionTask["abortCompaction"] = true
        logLine("[SliceDB][metric] compaction.abortSignal=true")
    end if
end sub

sub onCompactionResponse(event as object)
    result = event.GetData()
    if result = invalid then return

    totalMs = m.compactionStart.TotalMilliseconds()
    logLine("[SliceDB][metric] compaction.ms=" + totalMs.ToStr() + " aborted=" + result["aborted"].ToStr() + " chunks=" + result["chunkGenerationIds"].Count().ToStr())

    if result["aborted"]
        committedAbort = StoreRegistry_commitChunkedCompaction(m.reg, result, [])
        if committedAbort <> false then stop
        logLine("[SliceDB][metric] compaction.abortCommitRejected=true")
        requestMemorySnapshot("after-compaction-abort-" + m.compactionStage)

        if m.compactionStage = "post-add"
            clearCompactionTaskState()
            setStatus("Compaction retry")
            startCompaction("post-add-retry", false)
            return
        end if
    else
        beforeMs = CreateObject("roTimespan")
        beforeMs.Mark()

        removeIds = []
        for each id in result["chunkGenerationIds"]
            removeIds.Push(id)
        end for

        if m.compactionStage = "post-add" or m.compactionStage = "post-add-retry"
            removeIds = ["base", "u1", "add100"]
        else if m.compactionStage = "interval"
            removeIds = []
            for each id in m.reg["generationOrder"]
                if Left(id, 4) <> "cmp-" then removeIds.Push(id)
            end for
        end if

        committed = StoreRegistry_commitChunkedCompaction(m.reg, result, removeIds)
        if committed <> true then stop
        logLine("[SliceDB][metric] compaction.commitMs=" + beforeMs.TotalMilliseconds().ToStr() + " mergedCount=" + m.reg["mergedOrder"].Count().ToStr())
        requestMemorySnapshot("after-compaction-commit-" + m.compactionStage)

        if m.compactionStage = "post-add-retry"
            clearCompactionTaskState()
            setStatus("Interval update waves")
            startIntervalWaves()
            return
        end if

        if m.compactionStage = "interval"
            m.intervalCycleIndex = m.intervalCycleIndex + 1
            if m.intervalCycleIndex >= m.intervalCycles
                m.isBusy = false
                if m.loadingSpinner <> invalid
                    m.loadingSpinner.control = "stop"
                    m.loadingSpinner.visible = false
                end if
                setStatus("Stress test complete")
                logLine("[SliceDB] stress-test PASS")
                requestMemorySnapshot("stress-pass")
                clearCompactionTaskState()
                return
            end if

            clearCompactionTaskState()
            setStatus("Waiting 5s before next interval update")
            scheduleNextInterval()
            return
        end if
    end if
end sub

sub startIntervalWaves()
    logLine("[SliceDB] interval waves start")
    m.intervalCycleIndex = 0
    startIntervalUpdateBuild()
end sub

sub scheduleNextInterval()
    t = CreateObject("roSGNode", "Timer")
    m.intervalTimer = t
    t.duration = 5.0
    t.repeat = false
    t.observeFieldScoped("fire", "onIntervalTimerFire")
    m.top.appendChild(t)
    t.control = "start"
end sub

sub onIntervalTimerFire(event as object)
    setStatus("Running interval update " + (m.intervalCycleIndex + 1).ToStr() + "/" + m.intervalCycles.ToStr())
    startIntervalUpdateBuild()
end sub

sub startMemoryMonitor()
    m.memoryTask = CreateObject("roSGNode", "MemoryMonitorTask")
    m.memoryTask.observeFieldScoped("uiMessage", "onMemoryMonitorMessage")
    m.memoryTask.control = "RUN"
end sub

sub onMemoryMonitorMessage(event as object)
    msg = event.GetData()
    if msg = invalid then return

    mType = msg["type"]
    if mType = "MEMORY_SNAPSHOT"
        updateMemoryLabel(msg)
        logLine("[SliceDB][mem] snapshot reason=" + fmt(msg["reason"]) + " tag=" + fmt(msg["tag"]) + " availMb=" + fmt(msg["availableMemoryMb"]) + " limitMb=" + fmt(msg["channelMemoryLimit"]) + " limitPct=" + fmt(msg["memoryLimitPercent"]))
        return
    end if
end sub

sub setStatus(text as string)
    if m.statusLabel <> invalid then m.statusLabel.text = text
end sub

sub updateMemoryLabel(msg as object)
    if m.memoryLabel = invalid then return
    m.memoryLabel.text = "Memory: avail=" + fmt(msg["availableMemoryMb"]) + "MB  limit=" + fmt(msg["channelMemoryLimit"]) + "MB  pct=" + fmt(msg["memoryLimitPercent"])
end sub

sub logLine(text as string)
    print text
    m.logLines.Push(text)
    while m.logLines.Count() > m.maxLogLines
        m.logLines.Shift()
    end while
    renderLogLines()
end sub

sub setupLogLineNodes()
    if m.logContainer = invalid then return

    i = 0
    while i < m.maxLogLines
        lineNode = CreateObject("roSGNode", "Label")
        lineNode.translation = [0, i * 36]
        lineNode.width = 1800
        lineNode.height = 34
        lineNode.color = "0xFFFFFFFF"
        lineNode.text = ""
        m.logContainer.appendChild(lineNode)
        m.logLineNodes.Push(lineNode)
        i = i + 1
    end while
end sub

sub renderLogLines()
    if m.logLineNodes = invalid then return

    i = 0
    while i < m.maxLogLines
        if i < m.logLines.Count()
            m.logLineNodes[i].text = m.logLines[i]
        else
            m.logLineNodes[i].text = ""
        end if
        i = i + 1
    end while
end sub

function fmt(value as dynamic) as string
    if value = invalid then return "--"
    t = type(value)
    if t = "roString" or t = "String" then return value
    if t = "Integer" or t = "LongInteger" or t = "Float" or t = "Double" or t = "Boolean" then return value.ToStr()
    return FormatJson(value)
end function

sub clearStressBuildTaskState()
    if not m.clearTransientState then return
    if m.stressTask = invalid then return
    m.stressTask["request"] = invalid
    m.stressTask["response"] = invalid
    m.stressTask.control = "stop"
    m.stressTask = invalid
end sub

sub clearCompactionTaskState()
    if not m.clearTransientState then return
    if m.compactionTask = invalid then return
    m.compactionTask["request"] = invalid
    m.compactionTask["response"] = invalid
    m.compactionTask.control = "stop"
    m.compactionTask = invalid
end sub

function makeDbPath(fileName as string) as string
    return m.storageRoot + fileName
end function

sub requestMemorySnapshot(tag as string)
    if m.memoryTask = invalid then return
    m.memoryTask["snapshotRequest"] = {
        "tag": tag
    }
end sub
