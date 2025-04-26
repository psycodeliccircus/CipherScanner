-- scanner.lua
local currentRes   = GetCurrentResourceName()
local exp          = exports[currentRes]
local readDir, isDir   = exp.readDir, exp.isDir
local getFileMTime = exp.getFileMTime
local LoadFile     = LoadResourceFile
local SaveFile     = SaveResourceFile
local numRes       = GetNumResources
local getResByIdx  = GetResourceByFindIndex
local getResState  = GetResourceState
local getResPath   = GetResourcePath
local gameTimer    = GetGameTimer
local osDate       = os.date
local jsonEncode   = json and json.encode

-- ensure global scanner exists
scanner = scanner or {
  enabled = true,
  results = utils.results,
  stats   = utils.stats
}

function scanner.reload()
  utils.reloadConfig()
  utils.reloadCache()
  scanner.results, scanner.stats = {}, {}
  utils.results = scanner.results
  utils.stats   = scanner.stats
end

function scanner.scanResource(res)
  local t0    = gameTimer()
  local base  = getResPath(res)
  local stack, found, scanned = {""}, {}, {}
  local cnt   = 0
  utils.log('info', "scanning %s", res)

  while #stack > 0 do
    local rel = table.remove(stack)
    local dir = base .. (rel=="" and "" or "/"..rel)
    local ok, items = pcall(readDir, dir)
    if ok and items then
      for _, f in ipairs(items) do
        utils.yield()
        local path = (rel=="" and f or rel.."/"..f)
        scanned[#scanned+1] = path
        if utils.shouldSkipFile(path) then goto cont end
        local full = base.."/"..path

        if isDir(full) then
          if not (utils.config.skipDirs or {})[f:lower()] then
            stack[#stack+1] = path
          end
        elseif utils.fileExt(f)
           and (not utils.config.incremental
                or getFileMTime(full) > (utils.cache[res] or {})[path])
        then
          cnt = cnt + 1
          local ok2, content = pcall(LoadFile, res, path)
          if ok2 and content then
            for _, sig in ipairs(utils.config.signatures or {}) do
              local m = sig:match('^/.+/$')
                and content:match(sig:sub(2,-2))
                or content:find(sig,1,true)
              if m then
                found[#found+1] = path
                break
              end
            end
          end
          utils.cache[res] = utils.cache[res] or {}
          utils.cache[res][path] = getFileMTime(full)
        end
        ::cont::
      end
    end
  end

  local dt = gameTimer() - t0
  scanner.stats[res]   = { files = cnt, matches = #found, time = dt }
  scanner.results[res] = found
  utils.log('info', "%s → %d arquivos, %d hits em %dms", res, cnt, #found, dt)

  if utils.config.showScanned then
    utils.log('info', "Arquivos lidos em %s:", res)
    for _, p in ipairs(scanned) do
      utils.log('info', "  - %s", p)
    end
  end
end

function scanner.generateReport()
  local md = {
    "# CipherScanner Report\n\n",
    "Generated at: " .. osDate("!%Y-%m-%d %H:%M:%S UTC") .. "\n\n",
    "| Resource | Files | Matches | Time (ms) |\n",
    "|----------|-------|---------|-----------|\n"
  }
  for r,s in pairs(scanner.stats) do
    md[#md+1] = string.format("| %s | %d | %d | %d |\n", r, s.files, s.matches, s.time)
  end
  SaveFile(currentRes, "report.md", table.concat(md), -1)
  utils.log('info', "report.md gerado")
end

function scanner.diff(res)
  local hist = utils.loadHistory()
  if #hist < 2 then return {}, {} end
  local prev = hist[#hist-1].results[res] or {}
  local curr = hist[#hist].results[res]   or {}
  local sp, sc = {}, {}
  for _,p in ipairs(prev) do sp[p] = true end
  for _,c in ipairs(curr) do sc[c] = true end
  local add, rem = {}, {}
  for _,c in ipairs(curr) do if not sp[c] then table.insert(add,c) end end
  for _,p in ipairs(prev) do if not sc[p] then table.insert(rem,p) end end
  return add, rem
end

function scanner.sendWebhook()
  utils.reloadConfig()

  local w = utils.config.webhook
  if not (w and w.enabled and w.url and w.url ~= "") then
    print("[cipher][WARN] Webhook disabled or URL missing")
    return
  end
  if not next(scanner.stats) then
    print("[cipher][INFO] No stats to send via webhook")
    return
  end

  -- total hits and non-zero list
  local totalHits, list = 0, {}
  for res,s in pairs(scanner.stats) do
    totalHits = totalHits + s.matches
    if s.matches > 0 then
      table.insert(list, string.format("**%s**: %d hits", res, s.matches))
    end
  end

  local embed = {
    title  = "**CipherScanner Report**",
    color  = 3447003,
    footer = { text = "Generated at " .. osDate("%Y-%m-%d %H:%M:%S") }
  }

  if totalHits == 0 then
    local countRes = 0
    for _ in pairs(scanner.stats) do countRes = countRes + 1 end
    embed.description = string.format(
      "✅ Nenhuma correspondência em %d recursos varridos.", countRes
    )
  else
    embed.description = table.concat(list, "\n")
  end

  local payload = {
    username = "CipherScanner",
    embeds   = { embed }
  }

  local body = jsonEncode(payload)

  PerformHttpRequest(
    w.url,
    function(code, responseBody)
      
      if responseBody then
        
      end
    end,
    "POST",
    body,
    { ["Content-Type"] = "application/json" }
  )
end

function scanner.scanAll(target)
  scanner.reload()
  utils.log('info', "Starting %s scan", target or "full")
  local list = {}

  if target then
    if not (utils.config.skipResources or {})[target] then
      list = { target }
    end
  else
    for i=0, numRes()-1 do
      utils.yield()
      local nm = getResByIdx(i)
      if nm and getResState(nm)=='started'
         and nm~=currentRes
         and not (utils.config.skipResources or {})[nm]
      then
        table.insert(list, nm)
      end
    end
  end

  local total, done = #list, 0
  for _, res in ipairs(list) do
    CreateThread(function()
      scanner.scanResource(res)
      done = done + 1
      TriggerClientEvent('cipher:resourceScanned', -1, res, scanner.stats[res])
      if done == total then
        utils.persistCache()
        utils.persistResults()
        scanner.generateReport()
        scanner.sendWebhook()
        utils.recordHistory(scanner.results)
        TriggerClientEvent('cipher:scanComplete', -1, scanner.stats)
      end
    end)
  end
end
