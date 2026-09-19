-- ===========================================================================
-- MitzuMPlus - QA/Localization  (1.1.0-dev.10)
--
-- Observabilidad del idioma. NO elige idioma ni traduce nada: AceLocale-3.0 ya
-- lo hizo al cargar (ver Bootstrap.lua). Aqui solo se mira el resultado para
-- poder responder, desde el Bug Report, "en que idioma esta viendo esto el
-- jugador y le falta alguna cadena".
--
-- No hay ajuste de idioma, ni SavedVariable, ni /reload: el idioma del addon es
-- el del cliente y punto.
--
--   clientLocale    GetLocale() del cliente (enUS, enGB, esMX, deDE...)
--   activeLocale    el fichero de Locales que quedo registrado (enUS o esES/esMX)
--   fallbackLocale  siempre enUS: es el locale por defecto de AceLocale
--   englishDefault  true si el ingles se registro como locale por defecto
--   missingKeys     claves pedidas en esta sesion que no existian
--
-- AceLocale devuelve la propia clave cuando falta una entrada y la deja escrita
-- en la tabla. Eso es exactamente lo que se cuenta: no se rellena nada con "?"
-- ni con "UNKNOWN", y las pruebas exigen cero antes de publicar.
-- ===========================================================================

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local Loc = {}
MitzuMPlus.Localization = Loc

Loc.FALLBACK = "enUS"
-- Los clientes en los que el addon tiene texto propio. Cualquier otro recibe
-- ingles por el locale por defecto de AceLocale, sin configurar nada.
Loc.TRANSLATED = { enUS = true, enGB = true, esES = true, esMX = true }

local function client()
    local fn = rawget(_G, "GetLocale")
    local ok, value = pcall(function() return fn and fn() end)
    return (ok and type(value) == "string" and value) or "UNKNOWN"
end

function Loc:ClientLocale() return client() end

-- Que fichero de Locales quedo registrado. Lo escribe el propio fichero
-- (LOCALE_ID), asi que no hay que adivinarlo desde fuera.
function Loc:ActiveLocale()
    local L = MitzuMPlus.L
    local id = L and rawget(L, "LOCALE_ID")
    return type(id) == "string" and id or Loc.FALLBACK
end

function Loc:IsEnglishDefault()
    local L = MitzuMPlus.L
    -- enUS se registra con isDefault=true, asi que sus claves existen SIEMPRE,
    -- incluso en un cliente aleman sin traduccion propia.
    return L ~= nil and rawget(L, "LOCALE_ID") ~= nil
end

-- Foto de las claves que los ficheros de Locales publicaron. Este modulo carga
-- justo despues de ellos y antes de cualquier UI, asi que lo que aparezca en la
-- tabla DESPUES es, por fuerza, una clave que alguien pidio y no existia
-- (AceLocale la escribe con su propio nombre como valor).
--
-- No se compara value == key: "DPS" o "HPS" se traducen a si mismos y son
-- traducciones legitimas, no ausencias.
Loc._declared = {}
do
    local L = MitzuMPlus.L
    if type(L) == "table" then
        for key in pairs(L) do Loc._declared[key] = true end
    end
end

function Loc:MissingKeys()
    local L = MitzuMPlus.L
    if type(L) ~= "table" then return nil, nil end
    local missing, first = 0, nil
    for key in pairs(L) do
        if not self._declared[key] then
            missing = missing + 1
            if not first then first = tostring(key) end
        end
    end
    return missing, first
end

function Loc:DeclaredKeyCount()
    local n = 0
    for _ in pairs(self._declared) do n = n + 1 end
    return n
end

function Loc:KeyCount()
    local L = MitzuMPlus.L
    if type(L) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(L) do n = n + 1 end
    return n
end

-- Idiomas cuyas cadenas llevan acentos o enes: la fuente tiene que cubrirlos.
-- Es la UNICA pregunta sobre idioma que este modulo responde a la interfaz, y
-- se contesta con el locale ya elegido, sin volver a llamar a GetLocale().
Loc.EXTENDED_LATIN = { esES = true, esMX = true }

function Loc:NeedsExtendedLatin()
    return Loc.EXTENDED_LATIN[self:ActiveLocale()] == true
end

function Loc:DiagnosticFields()
    local missing, first = self:MissingKeys()
    local clientLocale = client()
    local warnings = "none"
    if missing == nil then
        warnings = "LOCALE_TABLE_UNAVAILABLE"
    elseif missing > 0 then
        warnings = "MISSING_KEY:" .. tostring(first)
    elseif not Loc.TRANSLATED[clientLocale] then
        -- No es un fallo: es la ruta esperada para un cliente sin traduccion.
        warnings = "ENGLISH_FALLBACK"
    end
    return {
        { "clientLocale", clientLocale },
        { "activeLocale", self:ActiveLocale() },
        { "fallbackLocale", Loc.FALLBACK },
        { "englishDefault", self:IsEnglishDefault() },
        { "translatedClient", Loc.TRANSLATED[clientLocale] == true },
        { "loadedKeys", self:KeyCount() },
        { "missingKeys", missing },
        { "localizationWarnings", warnings },
    }
end

function Loc:StatusLines()
    local out = {}
    for _, kv in ipairs(self:DiagnosticFields()) do out[#out + 1] = kv[1] .. "=" .. tostring(kv[2]) end
    return out
end

return Loc
