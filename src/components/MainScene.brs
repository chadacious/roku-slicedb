sub init()
    m.top.backgroundURI = ""
    print "[SliceDB] MainScene init"
    m.selfTestTimer = CreateObject("roSGNode", "Timer")
    m.selfTestTimer.duration = 0.05
    m.selfTestTimer.repeat = false
    m.selfTestTimer.observeFieldScoped("fire", "onSelfTestTimerFire")
    m.top.appendChild(m.selfTestTimer)
    m.selfTestTimer.control = "start"
end sub

sub onSelfTestTimerFire(event as object)
    print "[SliceDB] self-test timer fired"
    runSliceDbSelfTest()
end sub

sub runSliceDbSelfTest()
    paths = buildGenerationSelfTestFiles()
    m.paths = paths

    m.reg = StoreRegistry()
    StoreRegistry_addGeneration(m.reg, "base", paths.basePath)
    StoreRegistry_addGeneration(m.reg, "gen1", paths.gen1Path)

    itemA = StoreRegistry_getById(m.reg, "a")
    itemB = StoreRegistry_getById(m.reg, "b")
    itemC = StoreRegistry_getById(m.reg, "c")
    item0 = StoreRegistry_getByMergedIndex(m.reg, 0)
    item1 = StoreRegistry_getByMergedIndex(m.reg, 1)
    item2 = StoreRegistry_getByMergedIndex(m.reg, 2)

    if itemA.value <> 101 then stop
    if itemB.value <> 999 then stop
    if itemC.value <> 303 then stop
    if item0.id <> "a" then stop
    if item1.id <> "b" then stop
    if item2.id <> "c" then stop

    ' Removing gen1 exposes base value for b and removes c entirely.
    StoreRegistry_removeGeneration(m.reg, "gen1")
    itemAfterRemoveA = StoreRegistry_getById(m.reg, "a")
    itemAfterRemoveB = StoreRegistry_getById(m.reg, "b")
    if itemAfterRemoveA.value <> 101 then stop
    if itemAfterRemoveB.value <> 202 then stop
    if m.reg["resolverById"]["c"] <> invalid then stop

    ' Re-add gen1 so we can compact the merged state.
    StoreRegistry_addGeneration(m.reg, "gen1", m.paths.gen1Path)

    ' Run compaction in task, then continue in callback.
    snapshot = StoreRegistry_beginCompactionSnapshot(m.reg)
    request = StoreRegistry_buildCompactionRequest(m.reg, snapshot, "tmp:/store-cmp", 2)
    m.compactionPhase = "compact"
    startCompactionTask(request, false)
end sub

sub onCompactionResponse(event as object)
    result = event.GetData()
    if result = invalid then return

    if m.compactionPhase = "compact"
        committed = StoreRegistry_commitChunkedCompaction(m.reg, result, ["base", "gen1"])
        if committed <> true then stop

        itemAfterCompactA = StoreRegistry_getById(m.reg, "a")
        itemAfterCompactB = StoreRegistry_getById(m.reg, "b")
        itemAfterCompactC = StoreRegistry_getById(m.reg, "c")
        if itemAfterCompactA.value <> 101 then stop
        if itemAfterCompactB.value <> 999 then stop
        if itemAfterCompactC.value <> 303 then stop

        ' Abort path: request abort before compaction and ensure commit is rejected.
        abortSnapshot = StoreRegistry_beginCompactionSnapshot(m.reg)
        abortRequest = StoreRegistry_buildCompactionRequest(m.reg, abortSnapshot, "tmp:/store-cmp-abort", 2)
        m.compactionPhase = "abort"
        startCompactionTask(abortRequest, true)
        return
    end if

    if m.compactionPhase = "abort"
        abortCommit = StoreRegistry_commitChunkedCompaction(m.reg, result, [])
        if abortCommit <> false then stop
        print "[SliceDB] self-test PASS"
        return
    end if
end sub

sub startCompactionTask(request as object, abortBeforeRun as boolean)
    task = CreateObject("roSGNode", "CompactionTask")
    m.compactionTask = task
    task.observeFieldScoped("response", "onCompactionResponse")
    task["request"] = request
    if abortBeforeRun then task["abortCompaction"] = true
    task.control = "RUN"
end sub
