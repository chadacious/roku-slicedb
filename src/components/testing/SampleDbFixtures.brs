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

    buildStoreFile(basePath, [
        {
            "id": "a"
            "value": 101
        }
        {
            "id": "b"
            "value": 202
        }
    ])

    buildStoreFile(gen1Path, [
        {
            "id": "b"
            "value": 999
        }
        {
            "id": "c"
            "value": 303
        }
    ])

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
