-- utils.lua
local currentRes = GetCurrentResourceName()
local LoadFile   = LoadResourceFile
local SaveFile   = SaveResourceFile
local jsonDecode = json and json.decode
local jsonEncode = json and json.encode
local osDate     = os.date
local CitizenWait= Citizen.Wait

utils = utils or {
  config  = {},
  cache   = {},
  results = {},
  stats   = {}
}
utils.historyFile = 'cipher_history.json'

-- Logging
local levels = { error=1, warn=2, info=3, debug=4 }
function utils.log(level, fmt, ...)
  local lvl = utils.config.logLevel or 'info'
  if levels[level] <= (levels[lvl] or 3) then
    local ts = osDate("!%Y-%m-%d %H:%M:%S UTC")
    print(("[cipher][%s][%s][%s] %s")
      :format(currentRes, level:upper(), ts, fmt:format(...)))
  end
end

-- Throttle
local opCount = 0
function utils.yield()
  opCount = opCount + 1
  if opCount >= (utils.config.maxOpsPerFrame or 30) then
    opCount = 0
    CitizenWait(0)
  end
end

-- JSON helpers
function utils.loadJSON(name)
  local raw = LoadFile(currentRes, name)
  if not raw then return {} end
  local ok,data = pcall(jsonDecode, raw)
  if not ok then utils.log('warn', "falha ao decodificar %s", name) end
  return type(data)=='table' and data or {}
end
function utils.saveJSON(name, tbl)
  local ok,err = pcall(function()
    SaveFile(currentRes, name, jsonEncode(tbl), -1)
  end)
  if not ok then utils.log('error', "falha ao salvar %s: %s", name, err) end
end

-- Config & cache persistence
function utils.reloadConfig()   utils.config  = utils.loadJSON('config.json') end
function utils.reloadCache()    utils.cache   = utils.loadJSON('cipher_cache.json') end
function utils.persistCache()   utils.saveJSON('cipher_cache.json',  utils.cache) end
function utils.persistResults() utils.saveJSON('cipher_results.json', utils.results) end

-- History
function utils.loadHistory()     return utils.loadJSON(utils.historyFile) end
function utils.saveHistory(h)    utils.saveJSON(utils.historyFile, h) end
function utils.recordHistory(r)
  local hist = utils.loadHistory()
  table.insert(hist, { ts=os.time(), results=r })
  while #hist > (utils.config.historyLimit or 5) do table.remove(hist,1) end
  utils.saveHistory(hist)
end
function utils.clearHistory(res)
  local new = {}
  for _,e in ipairs(utils.loadHistory()) do
    if not res or not e.results[res] then table.insert(new,e) end
  end
  utils.saveHistory(new)
end

-- Filters
function utils.fileExt(name) return name:match("%.([^.]+)$") end
function utils.shouldSkipFile(rel)
  for _,pat in ipairs(utils.config.skipFiles or {}) do
    if rel:find(pat,1,true) then return true end
  end
  return false
end
