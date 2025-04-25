-- server.lua (v8)
local currentRes    = GetCurrentResourceName()
local exp           = exports[currentRes]
local readDir, isDir= exp.readDir, exp.isDir
local getFileMTime  = exp.getFileMTime
local loadFile      = LoadResourceFile
local saveFile      = SaveResourceFile
local numRes        = GetNumResources
local getResByIdx   = GetResourceByFindIndex
local getResState   = GetResourceState
local getResPath    = GetResourcePath
local gameTimer     = GetGameTimer
local jsonEncode    = json and json.encode
local jsonDecode    = json and json.decode

-- estados globais
local config     = {}
local cache      = {}   -- cache de mtimes
local resultsLog = {}   -- resultados do último scan
local stats      = {}   -- stats por recurso
local opCount    = 0

-- níveis de log
local levels = { error=1, warn=2, info=3, debug=4 }
local function log(level, fmt, ...)
    if levels[level] <= levels[config.logLevel or 'info'] then
        print(("[cipher][%s][%s] %s")
            :format(currentRes, level:upper(), fmt:format(...)))
    end
end

-- throttle para não travar
local function yieldIfNeeded()
    opCount = opCount + 1
    if opCount >= (config.maxOpsPerFrame or 30) then
        opCount = 0
        Citizen.Wait(0)
    end
end

local function getExt(name)
    return name:match("%.([^.]+)$")
end

local function loadJSON(name)
    local raw = loadFile(currentRes, name)
    if not raw then return {} end
    local ok, data = pcall(jsonDecode, raw)
    if not ok then log('warn', 'falha ao decodificar %s', name) end
    return type(data)=='table' and data or {}
end

local function saveJSON(name, tbl)
    local ok, err = pcall(function()
        saveFile(currentRes, name, jsonEncode(tbl), -1)
    end)
    if not ok then log('error','erro ao salvar %s: %s', name, err) end
end

local function reloadConfig() config = loadJSON('config.json') end
local function reloadCache () cache  = loadJSON('cipher_cache.json') end
local function persistCache() saveJSON('cipher_cache.json', cache) end
local function persistResults() saveJSON('cipher_results.json', resultsLog) end

local function needsScan(res, path)
    if not config.incremental then return true end
    local full = getResPath(res) .. '/' .. path
    local mtime = getFileMTime(full)
    local prev  = cache[res] and cache[res][path]
    return not prev or mtime > prev
end

local function updateCache(res, path)
    cache[res] = cache[res] or {}
    cache[res][path] = getFileMTime(getResPath(res)..'/'..path)
end

local function shouldSkipFile(relPath)
    if config.skipFiles then
        for _, pat in ipairs(config.skipFiles) do
            if relPath:find(pat,1,true) then return true end
        end
    end
    return false
end

local function scanResource(resName)
    local t0        = gameTimer()
    local base      = getResPath(resName)
    local stack     = { '' }
    local found     = {}
    local fileCount = 0
    opCount = 0

    while #stack > 0 do
        local rel = table.remove(stack)
        local dir = base .. (rel=='' and '' or '/'..rel)
        local ok, items = pcall(readDir, dir)
        if ok and items then
            for _, item in ipairs(items) do
                yieldIfNeeded()
                local relPath = (rel=='' and item or rel..'/'..item)
                if shouldSkipFile(relPath) then goto continue end

                local full = base..'/'..relPath
                if isDir(full) then
                    if not (config.skipDirs or {})[item:lower()] then
                        stack[#stack+1] = relPath
                    end
                elseif getExt(item)==(config.luaExt or 'lua') then
                    if needsScan(resName, relPath) then
                        fileCount = fileCount + 1
                        local ok2, content = pcall(loadFile, resName, relPath)
                        if ok2 and content then
                            for _, sig in ipairs(config.signatures or {}) do
                                local match
                                if sig:match('^/.+/$') then
                                    match = content:match(sig:sub(2,-2))
                                else
                                    match = content:find(sig,1,true)
                                end
                                if match then
                                    found[#found+1] = relPath
                                    log('debug','match [%s] em %s', sig, relPath)
                                    break
                                end
                            end
                        end
                        updateCache(resName, relPath)
                    end
                end
                ::continue::
            end
        end
    end

    stats[resName]    = { files=fileCount, matches=#found, time=gameTimer()-t0 }
    resultsLog[resName] = found
    log('info','%s → %d arquivos, %d hits em %dms',
        resName, fileCount, #found, stats[resName].time)
end

local function scanAll(target)
    reloadConfig(); reloadCache()
    resultsLog, stats = {}, {}
    log('info','iniciando %s scan (incremental=%s)',
        target or 'full', tostring(config.incremental))

    if target then
        scanResource(target)
    else
        for i=0, numRes()-1 do
            yieldIfNeeded()
            local name = getResByIdx(i)
            if name
            and getResState(name)=='started'
            and name~=currentRes
            and not (config.skipDirs or {})[name] then
                scanResource(name)
            end
        end
    end

    persistCache(); persistResults()

    local totF, totM, totT = 0,0,0
    for _, s in pairs(stats) do
        totF, totM, totT = totF+s.files, totM+s.matches, totT+s.time
    end
    log('info','concluído: %d arquivos, %d matches em %dms',
        totF, totM, totT)
end

-- comando /cipherscan
RegisterCommand('cipherscan', function(src,args)
    local cmd = args[1] and args[1]:lower()
    if cmd == 'start' then
        scanAll(args[2])
    elseif cmd == 'reload' then
        reloadConfig(); log('info','config recarregada')
    elseif cmd == 'clear' then
        resultsLog, cache = {}, {}; persistCache(); persistResults()
        log('info','logs e cache limpos')
    elseif cmd == 'export' then
        persistResults(); log('info','results exportados')
    elseif cmd == 'stats' then
        for r,s in pairs(stats) do
            log('info','%s → %d/%d em %dms',
                r, s.matches, s.files, s.time)
        end
    elseif cmd == 'addsig' and args[2] then
        config.signatures = config.signatures or {}
        table.insert(config.signatures, args[2])
        saveJSON('config.json',config)
        log('info','assinatura adicionada: %s', args[2])
    elseif cmd == 'remsig' and args[2] then
        for i,v in ipairs(config.signatures or {}) do
            if v==args[2] then table.remove(config.signatures,i); break end
        end
        saveJSON('config.json',config)
        log('info','assinatura removida: %s', args[2])
    elseif cmd == 'listsig' then
        log('info','signatures: %s',
            table.concat(config.signatures or {},', '))
    elseif cmd == 'verbose' then
        config.verbose = not config.verbose
        saveJSON('config.json',config)
        log('info','verbose=%s',tostring(config.verbose))
    else
        log('info','Uso: /cipherscan [start [res]|reload|clear|export|stats|addsig|remsig|listsig|verbose]')
    end
end, true)

-- eventos
AddEventHandler('onResourceStart', function(res)
    if res~=currentRes and config.autoOnStart then
        log('info','recurso %s iniciado → scan incremental', res)
        scanResource(res); persistCache(); persistResults()
    end
end)

RegisterNetEvent('cipher:requestResults')
AddEventHandler('cipher:requestResults', function()
    for r,paths in pairs(resultsLog) do
        TriggerClientEvent('cipher:report', source, r, paths)
    end
end)

RegisterNetEvent('cipher:getStats')
AddEventHandler('cipher:getStats', function()
    TriggerClientEvent('cipher:stats', source, stats)
end)

-- auto-interval
CreateThread(function()
    Citizen.Wait(100)
    if config.autoInterval and config.autoInterval > 0 then
        while true do
            Citizen.Wait(config.autoInterval)
            scanAll()
        end
    end
end)

-- scan inicial
CreateThread(function()
    Citizen.Wait(100)
    scanAll()
end)
