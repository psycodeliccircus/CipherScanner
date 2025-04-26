-- server.lua
local currentRes = GetCurrentResourceName()
local jsonDecode = json and json.decode

-- JSON helper mínimo
local function loadJSON(name)
    local raw = LoadResourceFile(currentRes, name)
    if not raw then return {} end
    local ok, data = pcall(jsonDecode, raw)
    return ok and type(data)=='table' and data or {}
end

-- Update checker
local function checkUpdate()
    local cfg = loadJSON('config.json').update
    if not cfg or not cfg.enabled then return end

    local gh = cfg.github
    local url = ("https://api.github.com/repos/%s/%s/releases/latest")
                :format(gh.owner, gh.repo)
    local headers = {
        ["User-Agent"] = "CipherScanner",
        ["Accept"]     = "application/vnd.github.v3+json"
    }
    if gh.token and #gh.token>0 then
        headers["Authorization"] = "token "..gh.token
    end

    PerformHttpRequest(url, function(code, body)
        if code==403 then
            print("[cipher][WARN] 403 do GitHub – possivelmente rate-limit.")
            return
        end
        if code==200 and body then
            local ok, data = pcall(jsonDecode, body)
            if ok and data.tag_name and data.tag_name~=loadJSON('config.json').version then
                local info = {
                    version     = data.tag_name,
                    downloadUrl = (data.assets and data.assets[1] and data.assets[1].browser_download_url)
                                  or data.html_url,
                    changelog   = data.body or ""
                }
                print(("[cipher][INFO] Nova versão %s disponível → %s")
                      :format(info.version, info.downloadUrl))
                TriggerClientEvent('cipher:updateAvailable', -1, info)
            end
        end
    end, 'GET', '', headers)
end

-- carregar módulo de scan (já define scanAll, reloadConfig, etc)
-- **NÃO** use dofile: FiveM já instancia `scanAll.lua` antes
-- e disponibiliza globalmente scanAll(), reloadConfig(), etc.

-- comandos
RegisterCommand('cipherscan', function(src, args)
    local cmd = args[1] and args[1]:lower()
    if cmd=='start' then
        scanAll(args[2])
    elseif cmd=='update' then
        print("[cipher][INFO] Checando update...")
        checkUpdate()
    else
        print("Uso: /cipherscan [start [res]|update]")
    end
end, true)

-- loop de scheduler
CreateThread(function()
    Citizen.Wait(100)
    -- primeira checagem e scan
    checkUpdate()
    scanAll()
    -- ciclo periódico de update
    local cfg = loadJSON('config.json').update
    if cfg and cfg.enabled then
        while true do
            Citizen.Wait(cfg.checkInterval or 86400000)
            checkUpdate()
        end
    end
end)
