sub init()
    m.top.backgroundURI = ""
    print "[SliceDB] MainScene init"

    m.reg = StoreRegistry()
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
end sub

sub onBootTimerFire(event as object)
    print "[SliceDB] stress test start"
    startBaseBuild()
end sub

sub startBaseBuild()
    request = {
        "operation": "base"
        "path": "tmp:/stress-base.rsdb"
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
        "path": "tmp:/stress-update-1k.rsdb"
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
        "path": "tmp:/stress-add-100.rsdb"
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
        "path": "tmp:/stress-interval-update-" + m.intervalCycleIndex.ToStr() + ".rsdb"
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

    print "[SliceDB][metric] build.operation=" + res["operation"] + " count=" + res["count"].ToStr() + " bytes=" + res["totalPayloadBytes"].ToStr() + " ms=" + res["elapsedMs"].ToStr()

    if m.currentPhase = "base"
        StoreRegistry_addGeneration(m.reg, "base", res["path"])
        print "[SliceDB][metric] mergedCount=" + m.reg["mergedOrder"].Count().ToStr()
        startFirstUpdateBuild()
        return
    end if

    if m.currentPhase = "update-1k"
        StoreRegistry_addGeneration(m.reg, "u1", res["path"])
        startAddBuild()
        return
    end if

    if m.currentPhase = "add-100"
        StoreRegistry_addGeneration(m.reg, "add100", res["path"])
        ' First compaction run is intentionally aborted.
        startCompaction("post-add", true)
        return
    end if

    if m.currentPhase = "interval-update"
        genId = "u-int-" + m.intervalCycleIndex.ToStr()
        StoreRegistry_addGeneration(m.reg, genId, res["path"])
        startCompaction("interval", false)
        return
    end if
end sub

sub startCompaction(stage as string, shouldAbort as boolean)
    snapshot = StoreRegistry_beginCompactionSnapshot(m.reg)
    request = StoreRegistry_buildCompactionRequest(m.reg, snapshot, "tmp:/stress-cmp-" + stage + "-" + snapshot["version"].ToStr(), 500)

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
        print "[SliceDB][metric] compaction.abortSignal=true"
    end if
end sub

sub onCompactionResponse(event as object)
    result = event.GetData()
    if result = invalid then return

    totalMs = m.compactionStart.TotalMilliseconds()
    print "[SliceDB][metric] compaction.ms=" + totalMs.ToStr() + " aborted=" + result["aborted"].ToStr() + " chunks=" + result["chunkGenerationIds"].Count().ToStr()

    if result["aborted"]
        committedAbort = StoreRegistry_commitChunkedCompaction(m.reg, result, [])
        if committedAbort <> false then stop
        print "[SliceDB][metric] compaction.abortCommitRejected=true"

        if m.compactionStage = "post-add"
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
        print "[SliceDB][metric] compaction.commitMs=" + beforeMs.TotalMilliseconds().ToStr() + " mergedCount=" + m.reg["mergedOrder"].Count().ToStr()

        if m.compactionStage = "post-add-retry"
            startIntervalWaves()
            return
        end if

        if m.compactionStage = "interval"
            m.intervalCycleIndex = m.intervalCycleIndex + 1
            if m.intervalCycleIndex >= m.intervalCycles
                print "[SliceDB] stress-test PASS"
                return
            end if

            scheduleNextInterval()
            return
        end if
    end if
end sub

sub startIntervalWaves()
    print "[SliceDB] interval waves start"
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
    startIntervalUpdateBuild()
end sub
