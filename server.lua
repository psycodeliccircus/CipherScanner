-- server.lua (v9)
local currentRes   = GetCurrentResourceName()
local exp          = exports[currentRes]
local readDir, isDir  = exp.readDir, exp.isDir
local getFileMTime = exp.getFileMTime
local loadFile     = LoadResourceFile
local saveFile     = SaveResourceFile
local numRes       = GetNumResources
local getResByIdx  = GetResourceByFindIndex
local getResState  = GetResourceState
local getResPath   = GetResourcePath
local gameTimer    = GetGameTimer
local jsonEncode   = json and json.encode
local jsonDecode   = json and json.decode
local os_date      = os.date

-- estados globais
local config, cache, resultsLog, stats = {}, {}, {}, {}
local opCount = 0

-- níveis de log
local levels = { error=1, warn=2, info=3, debug=4 }
local function log(level, fmt, ...)
    if levels[level] <= levels[config.logLevel or 'info'] then
        local ts = os_date("!%Y-%m-%d %H:%M:%S UTC")
        print(("[cipher][%s][%s][%s] %s")
            :format(currentRes, level:upper(), ts, fmt:format(...)))
    end
end

-- throttle para o game loop
local function yieldIfNeeded()
    opCount = opCount + 1
    if opCount >= (config.maxOpsPerFrame or 30) then
        opCount = 0
        Citizen.Wait(0)
    end
end

-- utilitários JSON
local function loadJSON(name)
    local raw = loadFile(currentRes, name)
    if not raw then return {} end
    local ok, data = pcall(jsonDecode, raw)
    if not ok then log('warn','falha ao decodificar %s', name) end
    return type(data)=='table' and data or {}
end
local function saveJSON(name, tbl)
    local ok, err = pcall(function()
        saveFile(currentRes, name, jsonEncode(tbl), -1)
    end)
    if not ok then log('error','erro ao salvar %s: %s', name, err) end
end

-- recarrega config e cache
local function reloadConfig() config = loadJSON('config.json') end
local function reloadCache()  cache  = loadJSON('cipher_cache.json') end

-- persiste cache e results
local function persistCache()   saveJSON('cipher_cache.json', cache) end
local function persistResults() saveJSON('cipher_results.json', resultsLog) end

-- decide se deve scan incremental
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

-- decide skip de arquivo
local function shouldSkipFile(rel)
    if config.skipFiles then
        for _, pat in ipairs(config.skipFiles) do
            if rel:find(pat,1,true) then return true end
        end
    end
    return false
end

local function fileExt(name)
    return name:match("%.([^.]+)$")
end

-- grava report.md em Markdown
local function generateReport()
    local md = {
        "# CipherScanner Report\n",
        "Generated at: "..os_date("!%Y-%m-%d %H:%M:%S UTC").."\n\n",
        "| Resource | Files | Matches | Time (ms) |\n",
        "|----------|-------|---------|-----------|\n"
    }
    for res, s in pairs(stats) do
        md[#md+1] = string.format("| %s | %d | %d | %d |\n",
            res, s.files, s.matches, s.time)
    end
    local content = table.concat(md)
    saveFile(currentRes, "report.md", content, -1)
    log('info',"report.md gerado")
end

-- envia webhook Discord
local function sendWebhook()
    if config.webhook and config.webhook.enabled and config.webhook.url ~= "" then
        local embed = { title="CipherScanner v9", fields={} }
        for res, s in pairs(stats) do
            embed.fields[#embed.fields+1] = {
                name  = res,
                value = string.format("%d matches em %d arquivos", s.matches, s.files),
                inline = false
            }
        end
        local payload = jsonEncode({ embeds = { embed } })
        PerformHttpRequest(
            config.webhook.url,
            function(code) log('info',"webhook HTTP status %d", code) end,
            "POST",
            payload,
            { ["Content-Type"]="application/json" }
        )
    end
end

-- scan de um único recurso
local function scanResource(resName)
    local t0     = gameTimer()
    local base   = getResPath(resName)
    local stack  = { '' }
    local found  = {}
    local cnt    = 0
    opCount      = 0

    while #stack > 0 do
        local rel = table.remove(stack)
        local dir = base .. (rel=='' and '' or '/'..rel)
        local ok, items = pcall(readDir, dir)
        if ok and items then
            for _, item in ipairs(items) do
                yieldIfNeeded()
                local relPath = (rel=='' and item or rel..'/'..item)
                if shouldSkipFile(relPath) then goto cont end
                local full = base..'/'..relPath
                if isDir(full) then
                    if not (config.skipDirs or {})[item:lower()] then
                        stack[#stack+1] = relPath
                    end
                else
                    local ext = fileExt(item)
                    if ext and vim.tbl_contains(config.fileExts or {ext}, ext)
                    and needsScan(resName, relPath) then
                        cnt = cnt + 1
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
                                    if config.verbose then
                                        log('debug','[%s] → %s', sig, relPath)
                                    end
                                    break
                                end
                            end
                        end
                        updateCache(resName, relPath)
                    end
                end
                ::cont::
            end
        end
    end

    stats[resName]     = { files=cnt, matches=#found, time=gameTimer()-t0 }
    resultsLog[resName] = found
    log('info','%s → %d arquivos, %d hits em %dms',
        resName, cnt, #found, stats[resName].time)
end

-- scan completo (paralelo) ou de um recurso-alvo
local function scanAll(target)
    reloadConfig(); reloadCache()
    resultsLog, stats = {}, {}
    log('info','iniciando %s scan (incremental=%s)',
        target and ("scan em "..target) or "full", tostring(config.incremental))

    local toScan = {}
    if target then
        toScan = { target }
    else
        for i=0, numRes()-1 do
            yieldIfNeeded()
            local name = getResByIdx(i)
            if name
            and getResState(name)=='started'
            and name~=currentRes
            and not (config.skipDirs or {})[name] then
                toScan[#toScan+1] = name
            end
        end
    end

    local total, done = #toScan, 0
    for _, res in ipairs(toScan) do
        CreateThread(function()
            scanResource(res)
            done = done + 1
            TriggerClientEvent('cipher:resourceScanned', -1, res, stats[res])
            if done == total then
                persistCache(); persistResults()
                generateReport(); sendWebhook()
                TriggerClientEvent('cipher:scanComplete', -1, stats)
            end
        end)
    end
end

-- comandos /cipherscan
RegisterCommand('cipherscan', function(src,args)
    local cmd = args[1] and args[1]:lower()
    if cmd=='start' then         scanAll(args[2])
    elseif cmd=='reload' then     reloadConfig(); log('info','config recarregada')
    elseif cmd=='clear' then      resultsLog, cache = {}, {}; persistCache(); persistResults(); log('info','logs limpos')
    elseif cmd=='export' then     persistResults(); generateReport(); log('info','export completo')
    elseif cmd=='stats' then
        for r,s in pairs(stats) do
            log('info','%s → %d/%d em %dms', r, s.matches, s.files, s.time)
        end
    else
        log('info','Uso: /cipherscan [start [res]|reload|clear|export|stats]')
    end
end, true)

-- auto scan on start
AddEventHandler('onResourceStart', function(res)
    if res~=currentRes and config.autoOnStart then
        log('info','recurso %s iniciou → scan incremental', res)
        scanAll(res)
    end
end)

-- eventos para clientes
RegisterNetEvent('cipher:requestResults')
AddEventHandler('cipher:requestResults', function()
    TriggerClientEvent('cipher:report', source, resultsLog)
end)
RegisterNetEvent('cipher:getStats')
AddEventHandler('cipher:getStats', function()
    TriggerClientEvent('cipher:stats', source, stats)
end)

-- auto-interval e scan inicial
CreateThread(function()
    Citizen.Wait(100)
    if config.autoInterval and config.autoInterval > 0 then
        while true do
            Citizen.Wait(config.autoInterval)
            scanAll()
        end
    end
    scanAll()
end)
