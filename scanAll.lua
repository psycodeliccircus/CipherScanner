-- scanAll.lua
local currentRes   = GetCurrentResourceName()
local exp          = exports[currentRes]
local readDir, isDir   = exp.readDir, exp.isDir
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

-- estado compartilhado
config, cache, resultsLog, stats = {}, {}, {}, {}

-- logging genérico
local levels = { error=1, warn=2, info=3, debug=4 }
local function log(level, fmt, ...)
    if levels[level] <= levels[config.logLevel or 'info'] then
        local ts = os_date("!%Y-%m-%d %H:%M:%S UTC")
        print(("[cipher][%s][%s][%s] %s")
            :format(currentRes, level:upper(), ts, fmt:format(...)))
    end
end

-- throttle automático
local opCount = 0
local function yieldIfNeeded()
    opCount = opCount + 1
    if opCount >= (config.maxOpsPerFrame or 30) then
        opCount = 0
        Citizen.Wait(0)
    end
end

-- helpers JSON
local function loadJSON(name)
    local raw = LoadResourceFile(currentRes, name)
    if not raw then return {} end
    local ok, data = pcall(jsonDecode, raw)
    if not ok then log('warn','falha ao decodificar %s', name) end
    return type(data)=='table' and data or {}
end
local function saveJSON(name, tbl)
    local ok, err = pcall(function()
        SaveResourceFile(currentRes, name, jsonEncode(tbl), -1)
    end)
    if not ok then log('error','falha ao salvar %s: %s', name, err) end
end

-- recarrega / persiste
function reloadConfig()    config = loadJSON('config.json') end
function reloadCache()     cache  = loadJSON('cipher_cache.json') end
local function persistCache()   saveJSON('cipher_cache.json', cache) end
local function persistResults() saveJSON('cipher_results.json', resultsLog) end

-- geração de relatório
function generateReport()
    local md = {
        "# CipherScanner Report\n\n",
        "Generated at: "..os_date("!%Y-%m-%d %H:%M:%S UTC").."\n\n",
        "| Resource | Files | Matches | Time (ms) |\n",
        "|----------|-------|---------|-----------|\n"
    }
    for res, s in pairs(stats) do
        md[#md+1] = string.format("| %s | %d | %d | %d |\n",
            res, s.files, s.matches, s.time)
    end
    SaveResourceFile(currentRes, "report.md", table.concat(md), -1)
    log('info',"report.md gerado")
end

-- webhook
function sendWebhook()
    if config.webhook and config.webhook.enabled and config.webhook.url ~= "" then
        local embed = { title="CipherScanner", fields={} }
        for res, s in pairs(stats) do
            embed.fields[#embed.fields+1] = {
                name  = res,
                value = string.format("%d matches em %d arquivos", s.matches, s.files),
                inline = false
            }
        end
        PerformHttpRequest(
            config.webhook.url,
            function(code) log('info',"webhook status %d", code) end,
            "POST",
            jsonEncode({ embeds={embed} }),
            { ["Content-Type"]="application/json" }
        )
    end
end

-- filtragens
local function fileExt(name) return name:match("%.([^.]+)$") end
local function shouldSkipFile(rel)
    if config.skipFiles then
        for _, pat in ipairs(config.skipFiles) do
            if rel:find(pat,1,true) then return true end
        end
    end
    return false
end

-- incremental?
local function needsScan(res, path)
    if not config.incremental then return true end
    local full = getResPath(res).."/"..path
    local mtime = getFileMTime(full)
    local prev  = cache[res] and cache[res][path]
    return not prev or mtime > prev
end
local function updateCache(res, path)
    cache[res] = cache[res] or {}
    cache[res][path] = getFileMTime(getResPath(res).."/"..path)
end

-- escaneia um recurso
function scanResource(resName)
    local t0      = gameTimer()
    local base    = getResPath(resName)
    local stack   = { "" }
    local found   = {}
    local scanned = {}
    local cnt     = 0
    opCount       = 0

    while #stack > 0 do
        local rel = table.remove(stack)
        local dir = base..(rel=="" and "" or "/"..rel)
        local ok, items = pcall(readDir, dir)
        if ok and items then
            for _, item in ipairs(items) do
                yieldIfNeeded()
                local relPath = (rel=="" and item or rel.."/"..item)
                scanned[#scanned+1] = relPath
                if shouldSkipFile(relPath) then goto cont end
                local full = base.."/"..relPath

                if isDir(full) then
                    if not (config.skipDirs or {})[item:lower()] then
                        stack[#stack+1] = relPath
                    end
                elseif fileExt(item) and needsScan(resName, relPath) then
                    cnt = cnt + 1
                    local ok2, content = pcall(loadFile, resName, relPath)
                    if ok2 and content then
                        for _, sig in ipairs(config.signatures or {}) do
                            local match = sig:match("^/.+/$")
                                and content:match(sig:sub(2,-2))
                                or content:find(sig,1,true)
                            if match then
                                found[#found+1] = relPath
                                if config.verbose then
                                    log('debug',"[%s]→ %s", sig, relPath)
                                end
                                break
                            end
                        end
                    end
                    updateCache(resName, relPath)
                end
                ::cont::
            end
        end
    end

    stats[resName]      = { files=cnt, matches=#found, time=gameTimer()-t0 }
    resultsLog[resName] = found
    log('info','%s → %d arquivos, %d hits em %dms',
        resName, cnt, #found, stats[resName].time)

    if config.showScanned then
        log('info','Arquivos lidos em %s:', resName)
        for _, p in ipairs(scanned) do
            log('info','  - %s', p)
        end
    end
end

-- escaneia tudo (ou alvo)
function scanAll(target)
    reloadConfig(); reloadCache()
    resultsLog, stats = {}, {}
    log('info','Iniciando %s scan (incremental=%s)',
        target or "full", tostring(config.incremental))

    local toScan = {}
    if target then
        toScan = { target }
    else
        for i=0, numRes()-1 do
            yieldIfNeeded()
            local name = getResByIdx(i)
            if name and getResState(name)=="started"
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
