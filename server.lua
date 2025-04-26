-- server.lua
local jsonDecode = json and json.decode

-- Update checker
local function checkUpdate()
  local cfg = utils.config.update
  if not (cfg and cfg.enabled) then return end
  local gh = cfg.github
  local url = ("https://api.github.com/repos/%s/%s/releases/latest")
              :format(gh.owner, gh.repo)
  local headers = {
    ["User-Agent"] = "CipherScanner",
    ["Accept"]     = "application/vnd.github.v3+json"
  }
  if gh.token and #gh.token > 0 then
    headers["Authorization"] = "token " .. gh.token
  end

  PerformHttpRequest(url, function(code, body)
    if code == 403 then
      utils.log('warn', "403 do GitHub – rate-limit provável")
    elseif code ~= 200 then
      utils.log('warn', "HTTP %d ao checar update", code)
    else
      local ok, data = pcall(jsonDecode, body)
      if ok and data.tag_name and data.tag_name ~= utils.config.version then
        local info = {
          version    = data.tag_name,
          downloadUrl= (data.assets and data.assets[1] and data.assets[1].browser_download_url)
                       or data.html_url,
          changelog  = data.body or ""
        }
        utils.log('info', "nova versão %s disponível → %s", info.version, info.downloadUrl)
        TriggerClientEvent('cipher:updateAvailable', -1, info)
      else
        utils.log('info', "já na versão %s", utils.config.version)
      end
    end
  end, 'GET', '', headers)
end

-- Commands
RegisterCommand('cipherscan', function(_, args)
  local cmd = args[1] and args[1]:lower()
  if cmd == 'start' then
    scanner.scanAll(args[2])
  elseif cmd == 'update' then
    utils.log('info', "checando update...")
    checkUpdate()
  elseif cmd == 'pause' then
    scanner.enabled = false; utils.log('info', "scan pausado")
  elseif cmd == 'resume' then
    scanner.enabled = true; utils.log('info', "scan retomado")
  else
    utils.log('info', "Uso: /cipherscan [start|update|pause|resume]")
  end
end, true)

-- Scheduler
CreateThread(function()
  Citizen.Wait(100)
  utils.reloadConfig()
  utils.reloadCache()
  if utils.config.update.enabled then
    checkUpdate()
    Citizen.SetTimeout(utils.config.update.checkInterval or 86400000, function()
      CreateThread(checkUpdate)
    end)
  end
  if utils.config.autoInterval and scanner.enabled then
    CreateThread(function()
      while scanner.enabled do
        scanner.scanAll()
        Citizen.Wait(utils.config.autoInterval)
      end
    end)
  end
end)
