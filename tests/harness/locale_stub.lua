-- ═══════════════════════════════════════════════════════════════════════════
-- Tabla de traducciones REAL para los bancos que cargan un módulo suelto (sin
-- el TOC completo, así que sin AceLocale ni Bootstrap).
--
--   _G.MitzuMPlus = { L = dofile("tests/harness/locale_stub.lua")("enUS") }
--
-- No inventa textos: ejecuta Locales/enUS.lua o Locales/esES.lua con un LibStub
-- falso y devuelve lo que el fichero de verdad escribe. Así un banco que lee
-- L["TRACKER_PACE"] comprueba la traducción publicada, no una copia.
--
-- Igual que AceLocale, una clave que no existe se devuelve tal cual y se anota
-- en `missing`, para que un banco pueda exigir cero claves ausentes.
-- ═══════════════════════════════════════════════════════════════════════════

local FILES = {
    enUS = "MitzuMPlus/Locales/enUS.lua",
    enGB = "MitzuMPlus/Locales/enUS.lua",   -- AceLocale mapea enGB a enUS
    esES = "MitzuMPlus/Locales/esES.lua",
    esMX = "MitzuMPlus/Locales/esES.lua",
}

return function(locale)
    locale = locale or "enUS"
    local L = {}
    local missing = {}

    local savedLibStub, savedGetLocale = _G.LibStub, _G.GetLocale
    _G.GetLocale = function() return locale end
    _G.LibStub = function()
        return {
            NewLocale = function(_, _, want)
                -- El mismo contrato de AceLocale: solo devuelve tabla para el
                -- locale del cliente (enUS es además el locale por defecto).
                if want == locale or want == "enUS" then return L end
                return nil
            end,
        }
    end

    -- Inglés primero (es el locale por defecto: siempre se registra), luego la
    -- traducción, que sobrescribe lo que tenga. Mismo orden que el TOC.
    dofile(FILES.enUS)
    local translated = FILES[locale]
    if translated and translated ~= FILES.enUS then dofile(translated) end

    _G.LibStub, _G.GetLocale = savedLibStub, savedGetLocale

    local keys = {}
    for key in pairs(L) do keys[#keys + 1] = key end

    return setmetatable({}, {
        __index = function(_, key)
            local value = rawget(L, key)
            if value ~= nil then return value end
            missing[#missing + 1] = tostring(key)
            return key
        end,
        __newindex = function(_, key, value) rawset(L, key, value) end,
        __pairs = function() return pairs(L) end,
        __metatable = { locale = locale, keys = keys, missing = missing, raw = L },
    })
end
