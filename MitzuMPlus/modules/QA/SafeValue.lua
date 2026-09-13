-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · QA/SafeValue  —  convertir cualquier valor en texto copiable
--
-- Visto en vivo: "Chat Copy paste: Some lines contained a Blizzard secret
-- value and could not be copied." En Midnight 12.1 un valor SECRETO (vida de
-- enemigos, tropas por unidad, algunos spellID...) contamina todo lo que se
-- construye con él: concatenarlo produce otro valor secreto, y en código de
-- addon incluso puede lanzar un error.
--
-- Todo lo que acaba en un informe de QA pasa por aquí. Reglas:
--   · Se pregunta ANTES de tocar: issecretvalue(v). Nunca se concatena a ciegas.
--   · Cada conversión va en pcall. Un valor que no se deja convertir se reporta
--     como UNAVAILABLE, no rompe el informe que intenta diagnosticar un error.
--   · El resultado también se comprueba: un texto que siga siendo secreto sale
--     como SECRET.
--   · Datos personales innecesarios salen como REDACTED: rutas locales,
--     BattleTags, GUIDs de jugador.
--   · "|" es el carácter de escape de la caja de texto de WoW: se sustituye por
--     "/" para que lo copiado sea exactamente lo que se ve.
-- ═══════════════════════════════════════════════════════════════════════════

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local Safe = {}
MitzuMPlus.QASafe = Safe

Safe.SECRET      = "SECRET"
Safe.UNAVAILABLE = "UNAVAILABLE"
Safe.REDACTED    = "REDACTED"
Safe.MAX_LEN     = 240

-- ¿Es un valor secreto de Blizzard? Si la API no existe (clientes sin secretos,
-- bancos de pruebas) nada lo es. Si la propia pregunta falla, se trata como
-- secreto: ante la duda, no se toca.
function Safe.IsSecret(v)
    local fn = rawget(_G, "issecretvalue")
    if type(fn) ~= "function" then return false end
    local ok, res = pcall(fn, v)
    if not ok then return true end
    return res == true
end

local function redactar(s)
    -- Rutas locales (C:\..., D:/...). Un error de Lua trae la ruta del fichero;
    -- se conserva lo que hay a partir de AddOns, que es lo útil y no es privado.
    -- La ruta de WoW lleva espacios ("World of Warcraft"): se admiten hasta
    -- llegar a AddOns. Una ruta sin AddOns se redacta hasta el siguiente ":"
    -- (el que separa la ruta del número de línea en un error de Lua).
    s = s:gsub("%a:[\\/][^\n\"']-[\\/][Aa]dd[Oo]ns[\\/]", "AddOns/")
    s = s:gsub("%a:[\\/][^\n\"':]+", Safe.REDACTED)
    -- Carpeta de cuenta de WTF.
    s = s:gsub("WTF[\\/]Account[\\/][^\\/%s]+", "WTF/Account/" .. Safe.REDACTED)
    -- BattleTag: Nombre#1234
    s = s:gsub("[%a][%w]+#%d%d%d%d+", Safe.REDACTED)
    -- GUIDs de jugador y de Battle.net.
    s = s:gsub("Player%-%d+%-%x+", Safe.REDACTED)
    s = s:gsub("BNet%-%d+%-%x+", Safe.REDACTED)
    return s
end

-- Texto seguro de un valor escalar. `max` opcional acota la longitud.
function Safe.Text(v, max)
    if v == nil then return "nil" end
    if Safe.IsSecret(v) then return Safe.SECRET end

    local t = type(v)
    local s
    if t == "boolean" then
        s = v and "true" or "false"
    elseif t == "number" then
        local ok, r = pcall(function()
            if v ~= v then return "NaN" end
            if v == math.huge then return "inf" end
            if v == -math.huge then return "-inf" end
            if v == math.floor(v) and math.abs(v) < 1e15 then
                return string.format("%d", v)
            end
            return string.format("%.3f", v):gsub("0+$", ""):gsub("%.$", "")
        end)
        if not ok or type(r) ~= "string" then return Safe.UNAVAILABLE end
        s = r
    elseif t == "string" then
        s = v
    elseif t == "table" or t == "function" or t == "userdata" or t == "thread" then
        -- Nunca se imprime la dirección de memoria: no ayuda y cambia en cada
        -- sesión, lo que ensucia comparar dos informes.
        return "<" .. t .. ">"
    else
        return Safe.UNAVAILABLE
    end

    local ok, limpio = pcall(function()
        local r = redactar(s)
        r = r:gsub("|", "/"):gsub("[%c]", " ")
        return r
    end)
    if not ok or type(limpio) ~= "string" then return Safe.UNAVAILABLE end
    if Safe.IsSecret(limpio) then return Safe.SECRET end

    max = max or Safe.MAX_LEN
    if #limpio > max then limpio = limpio:sub(1, max) .. "..." end
    return limpio
end

-- Número utilizable, o nil. Un número secreto NO es utilizable.
function Safe.Number(v)
    if v == nil or Safe.IsSecret(v) then return nil end
    local ok, n = pcall(tonumber, v)
    if not ok or type(n) ~= "number" or n ~= n then return nil end
    return n
end

-- Llama a fn protegida. Devuelve ok y hasta cuatro resultados; si falla, false
-- y el motivo ya saneado.
function Safe.Call(fn, ...)
    if type(fn) ~= "function" then return false, Safe.UNAVAILABLE end
    local r = { pcall(fn, ...) }
    if not r[1] then return false, Safe.Text(r[2], 160) end
    return true, r[2], r[3], r[4], r[5]
end

-- Método de un módulo, protegido. nil si el módulo o el método no existen.
function Safe.Method(obj, name, ...)
    if type(obj) ~= "table" then return false, "MODULE_NIL" end
    local fn = obj[name]
    if type(fn) ~= "function" then return false, "METHOD_NIL" end
    return Safe.Call(fn, obj, ...)
end

-- "clave=valor" con el valor saneado.
function Safe.KV(key, value, max)
    return tostring(key) .. "=" .. Safe.Text(value, max)
end

return Safe
