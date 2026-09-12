-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · AdaptiveRoute · NameplateHooks v1.0
--
-- Marca visualmente en las placas de nombre los mobs que el solver ha decidido
-- saltar: alpha 0.35, barra gris neutro y prefijo "[SKIP]".
--
-- TAINT — la restricción que manda sobre todo lo demás
-- Los nameplates de Blizzard son frames gestionados por código protegido. Las
-- reglas que sigue este módulo:
--   · No se llama a NINGUNA función protegida (nada de SetPoint sobre el frame
--     de Blizzard, nada de mostrar/ocultar el nameplate, nada de tocar
--     UnitFrame ni sus atributos seguros).
--   · Solo se escriben propiedades puramente visuales de regiones que ya
--     existen: SetAlpha, SetStatusBarColor, SetText sobre la FontString.
--   · Todo el trabajo cuelga de NAME_PLATE_UNIT_ADDED / REMOVED, que son
--     eventos normales, nunca de un OnUpdate que corra dentro de código seguro.
--   · Nada se ejecuta durante InCombatLockdown que pudiera requerir permisos:
--     los cambios de color y texto no lo requieren, y no se hace nada más.
--
-- THREAT PLATES — detección, no suposición
-- No hay forma de verificar la API interna de ThreatPlates desde fuera del
-- juego, y adivinar nombres de función ya salió mal dos veces en este addon
-- (ver el episodio de los secret values). Así que se PRUEBAN varias vías
-- conocidas en orden, se registra cuál funcionó y, si no hay ninguna, se cae
-- al nameplate nativo de Blizzard, que siempre está.
-- `/emp skipstatus` dice qué vía se está usando de verdad.
-- ═══════════════════════════════════════════════════════════════════════════

local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

MitzuMPlus.AdaptiveRoute = MitzuMPlus.AdaptiveRoute or {}
local AR = MitzuMPlus.AdaptiveRoute

local NameplateHooks = {}
AR.NameplateHooks = NameplateHooks

local SKIP_ALPHA  = 0.35
local SKIP_COLOR  = { r = 0.45, g = 0.45, b = 0.45 }
local SKIP_PREFIX = "|cffffcc00[SKIP]|r "

local _issecretvalue = rawget(_G, "issecretvalue")

NameplateHooks._integration = "sin resolver"
NameplateHooks._tracked     = {}   -- [unitToken] = { plate, originalName }

-- ─────────────────────────────────────────────────────────────────────────
-- DETECCIÓN DE THREAT PLATES
-- ─────────────────────────────────────────────────────────────────────────

local function findThreatPlates()
    for _, name in ipairs({ "ThreatPlates", "TidyPlatesThreat", "TidyPlates_ThreatPlates" }) do
        local t = rawget(_G, name)
        if type(t) == "table" then return t, name end
    end
    return nil
end

-- ═════════════════════════════════════════════════════════════════════════
-- BUG NP-1 (v6.8.2) — el token de unidad NO se llama namePlateUnitToken aquí.
--
-- Volcado real del cliente del usuario (TidyPlatesThreat, WoW 12.1):
--   placas=5  conTokenDeUnidad=0
--   campos: ... TPFrame:table UnitFrame:table driverFrame:table
--           unitFrameTemplate:string unitToken:string
--
-- Las placas que devuelve GetNamePlates() exponen `unitToken`, no
-- `namePlateUnitToken`. Mi bucle leía el nombre estándar de Blizzard, salía
-- nil en las 5 placas y por eso la integración nunca se resolvía: no es que
-- ThreatPlates fuera irreconocible, es que ni llegaba a mirarlo.
--
-- También aparece `TPFrame`, que es el frame propio de ThreatPlates y el que
-- de verdad hay que pintar cuando está activo.
-- ═════════════════════════════════════════════════════════════════════════
local function unitTokenOf(np)
    if type(np) ~= "table" then return nil end
    local t = np.namePlateUnitToken or np.unitToken
    if type(t) == "string" then return t end
    if type(np.GetUnit) == "function" then
        local ok, u = pcall(np.GetUnit, np)
        if ok and type(u) == "string" then return u end
    end
    return nil
end

-- Localiza la placa visual de una unidad. Se prueba ThreatPlates primero
-- porque, cuando está activo, el nameplate de Blizzard queda oculto y pintarlo
-- no se vería.
local function plateForUnit(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil, "sin API" end
    local ok, np = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or not np then return nil, "sin placa" end
    -- Leido del codigo de ThreatPlates 13.1.1: el frame propio cuelga del
    -- nameplate de Blizzard como .TPFrame, y sus regiones viven en .visual
    -- (Nameplate.lua:974). Confirmado ademas en el volcado del cliente.
    if type(np.TPFrame) == "table" then return np.TPFrame, "threatplates" end
    if type(np.UnitFrame) == "table" then return np.UnitFrame, "blizzard" end
    return np, "blizzard-raw"
end

-- Busca dentro de la placa la barra de vida y la FontString del nombre, sea
-- cual sea la estructura. Se recorre solo un nivel: no es un camino caliente
-- (una vez por NAME_PLATE_UNIT_ADDED) y evita depender de nombres de campo.
-- ═════════════════════════════════════════════════════════════════════════
-- BUG NP-2 (v6.9.0) — los campos no se llamaban como yo probaba.
--
-- Leido en TidyPlates_ThreatPlates 13.1.1:
--   Elements/Healthbar.lua:52   local healthbar = visual.Healthbar
--   Elements/Name.lua:49        tp_frame.visual.NameText = name_text
--
-- Yo buscaba healthbar/HealthBar/healthBar y name/Name. Ninguno existe: son
-- `Healthbar` (H mayuscula, b minuscula) y `NameText`. Por eso plateParts
-- devolvia nil aunque la placa fuera perfectamente reconocible.
-- ═════════════════════════════════════════════════════════════════════════
local function plateParts(plate)
    if type(plate) ~= "table" then return nil, nil end
    local v = plate.visual
    if type(v) == "table" then
        -- ThreatPlates. Nombres verificados contra su codigo fuente.
        return v.Healthbar, v.NameText, v.textframe
    end
    -- Nameplate nativo de Blizzard.
    local bar = plate.healthBar or plate.HealthBar
    local nameFS = plate.name
    if bar and type(bar.SetStatusBarColor) ~= "function" then bar = nil end
    if nameFS and type(nameFS.SetText) ~= "function" then nameFS = nil end
    return bar, nameFS, plate
end

-- Vuelca los campos de una tabla, para diagnóstico cuando algo no se reconoce.
local function dumpFields(t, limit)
    if type(t) ~= "table" then return "(no es tabla)" end
    local keys = {}
    pcall(function()
        for k, v in pairs(t) do
            if type(k) == "string" then keys[#keys + 1] = k .. ":" .. type(v) end
        end
    end)
    table.sort(keys)
    local shown = {}
    for i = 1, math.min(limit or 20, #keys) do shown[i] = keys[i] end
    return table.concat(shown, " ") .. (#keys > (limit or 20) and (" ...+" .. (#keys - (limit or 20))) or "")
end

-- ─────────────────────────────────────────────────────────────────────────
-- APLICAR / QUITAR
-- ─────────────────────────────────────────────────────────────────────────

local function npcIDFromUnit(unit)
    if not UnitGUID then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or type(guid) ~= "string" then return nil end
    if _issecretvalue and _issecretvalue(guid) then return nil end
    local unitType, _, _, _, _, id = strsplit("-", guid)
    if unitType ~= "Creature" and unitType ~= "Vehicle" then return nil end
    return tonumber(id)
end

-- ═════════════════════════════════════════════════════════════════════════
-- BUG NP-3 (v6.9.0) — no se puede pintar SOBRE ThreatPlates. Hay que pintar
-- AL LADO.
--
-- Leido en su codigo: ThreatPlates reescribe el nombre en cada actualizacion
--   Elements/Name.lua:57   tp_frame.visual.NameText:SetText(unit.name)
--   Elements/Name.lua:93   tp_frame.visual.NameText:SetText(unit_name)
-- y recolorea barra y alpha por amenaza/objetivo continuamente.
--
-- Es decir: mi SetText con el prefijo [SKIP], mi SetStatusBarColor y mi
-- SetAlpha duraban hasta la siguiente actualizacion de ThreatPlates. Habrian
-- parpadeado, o directamente no se habrian visto nunca.
--
-- SOLUCION: no tocar NADA suyo. Se crean dos regiones PROPIAS colgadas de su
-- frame — una etiqueta y un velo gris sobre la barra — y se muestran u ocultan.
-- Nadie mas las toca, asi que no hay carrera. Ademas ya no hace falta guardar
-- ni restaurar el estado original, que era la parte fragil del diseño anterior.
--
-- La fuente se asigna SIEMPRE antes del primer SetText: una FontString sin
-- fuente lanza "Font not set" (el propio ThreatPlates lo documenta en
-- Elements/Name.lua:45).
-- ═════════════════════════════════════════════════════════════════════════

local LABEL_FONT = "Fonts\\FRIZQT__.TTF"

local function ensureOverlay(plate, bar, anchorFrame)
    local ov = plate.__mitzuSkip
    if ov and ov.label then return ov end

    ov = {}
    local host = anchorFrame or plate

    local label = host:CreateFontString(nil, "OVERLAY")
    label:SetFont(LABEL_FONT, 11, "OUTLINE")   -- ANTES de cualquier SetText
    label:SetText("[SKIP]")
    label:SetTextColor(1, 0.8, 0, 1)
    label:SetPoint("BOTTOM", host, "TOP", 0, 2)
    label:Hide()
    ov.label = label

    if bar then
        local veil = bar:CreateTexture(nil, "OVERLAY")
        veil:SetAllPoints(bar)
        veil:SetColorTexture(0.1, 0.1, 0.1, 0.55)
        veil:Hide()
        ov.veil = veil
    end

    plate.__mitzuSkip = ov
    return ov
end

function NameplateHooks:_Apply(unit, skip)
    local plate, how = plateForUnit(unit)
    if not plate then return end
    self._integration = how

    local bar, _, anchorFrame = plateParts(plate)
    local ok, ov = pcall(ensureOverlay, plate, bar, anchorFrame)
    if not ok or not ov then return end

    if skip then
        ov.label:Show()
        if ov.veil then ov.veil:Show() end
        self._tracked[unit] = plate
    else
        ov.label:Hide()
        if ov.veil then ov.veil:Hide() end
        self._tracked[unit] = nil
    end
end

function NameplateHooks:_Evaluate(unit)
    local pm = AR.ProfileManager
    local st = pm and pm:Settings()
    if st and st.nameplateSkips == false then
        self:_Apply(unit, false)
        return
    end
    local ET = AR.EventTracker
    if not ET then return end
    local npcID = npcIDFromUnit(unit)
    if not npcID then return end
    self:_Apply(unit, ET:IsSkipped(npcID))
end

-- Repasa todas las placas visibles. Se llama cuando cambia ActiveSkips, no en
-- bucle: un mob que estaba marcado puede dejar de estarlo tras un recálculo.
function NameplateHooks:RefreshAll()
    if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then return end
    for _, np in ipairs(plates) do
        local unit = unitTokenOf(np)
        if unit then
            local okEval = pcall(function() NameplateHooks:_Evaluate(unit) end)
            if not okEval then return end
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────
-- EVENTOS
-- ─────────────────────────────────────────────────────────────────────────

local frame = CreateFrame("Frame")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" and unit then
        pcall(function() NameplateHooks:_Evaluate(unit) end)
    elseif event == "NAME_PLATE_UNIT_REMOVED" and unit then
        -- Ahora que la capa es NUESTRA hay que apagarla al soltar la placa: el
        -- frame se recicla para otra unidad y, si no, el proximo mob apareceria
        -- ya marcado como SKIP sin serlo.
        pcall(function() NameplateHooks:_Apply(unit, false) end)
        NameplateHooks._tracked[unit] = nil
    elseif event == "PLAYER_ENTERING_WORLD" then
        NameplateHooks._tracked = {}
    end
end)

-- ThreatPlates puede cargarse después que nosotros. Al detectarlo se repasan
-- las placas para que la integración pase de "blizzard" a la suya.
local tpWatcher = CreateFrame("Frame")
tpWatcher:RegisterEvent("ADDON_LOADED")
tpWatcher:SetScript("OnEvent", function(_, _, name)
    if type(name) == "string" and name:find("ThreatPlates") then
        NameplateHooks._tracked = {}
        if C_Timer and C_Timer.After then
            C_Timer.After(1, function() NameplateHooks:RefreshAll() end)
        end
    end
end)

-- Resuelve la vía de integración SIN necesidad de que haya SKIPs activos.
-- Antes solo se rellenaba dentro de _Apply, así que el diagnóstico decía
-- "sin resolver" justo cuando más falta hace saberlo: antes de entrar a la
-- llave. Ahora se sondea una placa visible cualquiera y se informa.
function NameplateHooks:ProbeIntegration()
    self._probeDump = nil
    if not C_NamePlate or not C_NamePlate.GetNamePlates then
        return "sin API de nameplates"
    end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" or #plates == 0 then
        return nil, "no hay ninguna placa visible ahora mismo"
    end

    local withToken = 0
    for _, np in ipairs(plates) do
        local unit = unitTokenOf(np)
        if unit then
            withToken = withToken + 1
            local plate, how = plateForUnit(unit)
            if plate then
                local bar, nameFS = plateParts(plate)
                self._integration = how
                self._probeParts = string.format("barra=%s nombre=%s",
                    bar and "si" or "NO", nameFS and "si" or "NO")
                return how
            end
        end
    end

    -- Si se llega aqui, la deteccion fallo. En vez de repetir "sin estructura
    -- reconocible" —que no dice NADA sobre por que— se vuelca lo que hay de
    -- verdad en la primera placa. Adivinar la forma de la tabla ya salio mal
    -- dos veces en este addon; esto la pregunta.
    local dump = { string.format("placas=%d conTokenDeUnidad=%d", #plates, withToken) }
    local np = plates[1]
    if type(np) == "table" then
        dump[#dump + 1] = "placa: " .. dumpFields(np, 24)
        -- Un nivel mas adentro: TPFrame es el frame de ThreatPlates y .visual
        -- suele guardar la barra y el nombre. Sin esto el diagnostico se queda
        -- en la superficie justo donde deja de ser util.
        if type(np.TPFrame) == "table" then
            dump[#dump + 1] = "TPFrame: " .. dumpFields(np.TPFrame, 24)
            local v = np.TPFrame.visual or np.TPFrame.Visual
            if type(v) == "table" then
                dump[#dump + 1] = "TPFrame.visual: " .. dumpFields(v, 20)
            end
        end
    end
    self._probeDump = dump
    return nil, "placas visibles pero sin estructura reconocible"
end

function NameplateHooks:StatusLines()
    local out = {}
    local tp, tpName = findThreatPlates()
    out[#out + 1] = string.format("|cFFd9b33e[Nameplates]|r ThreatPlates: %s",
        tp and ("|cFF21de66" .. tpName .. "|r") or "|cFFff9922no detectado|r")

    if self._integration == "sin resolver" then
        local how, why = self:ProbeIntegration()
        if not how then
            out[#out + 1] = "Vía de integración: |cFFff9922sin resolver|r — " .. tostring(why)
            if self._probeDump then
                for _, l in ipairs(self._probeDump) do out[#out + 1] = "  " .. l end
            else
                out[#out + 1] = "  Apunta a un mob (que se vea su placa) y repite el comando."
            end
        end
    end
    out[#out + 1] = "Vía de integración en uso: " .. tostring(self._integration)
    if self._probeParts then
        out[#out + 1] = "  Partes localizadas en la placa: " .. self._probeParts
    end
    local n = 0
    for _ in pairs(self._tracked) do n = n + 1 end
    out[#out + 1] = string.format("Placas marcadas ahora mismo: %d", n)
    return out
end

return NameplateHooks
