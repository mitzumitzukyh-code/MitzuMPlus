-- ═══════════════════════════════════════════════════════════════════════════
-- Cliente de WoW simulado para cargar addons COMPLETOS en los bancos.
--
-- No intenta ser WoW: da lo justo para que los ficheros de un addon se
-- ejecuten en orden, registren eventos y respondan a un escenario (entrar a
-- una mazmorra, arrancar la llave, cambiar de pull). Todo lo que ofrece esta
-- escrito aqui a la vista; nada se inventa en silencio.
--
-- Uso:  local WoW = dofile("tests/harness/wow_mock.lua")
--       WoW.fire("ADDON_LOADED", "MitzuMPlus") ...
-- ═══════════════════════════════════════════════════════════════════════════

local WoW = {}
_G.__WOW = WoW

WoW.now = 1000
WoW.epoch = 1788000000
WoW.printed = {}
WoW.frames = {}
WoW.timers = {}
WoW.addonsLoaded = {}      -- [nombre] = true  (IsAddOnLoaded)
WoW.tocMeta = {}           -- [nombre] = { Version = ... }

WoW.state = {
    inInstance = false, instanceType = "none", instanceMapID = nil,
    instanceName = "", challengeActive = false, challengeMapID = nil,
    keyLevel = nil, elapsed = 0, uiMapID = nil, inCombat = false,
}

-- ── Lua/WoW utilidades globales ───────────────────────────────────────────

function strsplit(sep, str, pieces)
    str = tostring(str or "")
    local out, pattern = {}, "([^" .. sep:gsub("%p", "%%%0") .. "]*)"
    local i = 0
    for part in (str .. sep):gmatch(pattern .. sep:gsub("%p", "%%%0")) do
        i = i + 1
        out[i] = part
    end
    return table.unpack(out)
end
function strtrim(s) return (tostring(s or ""):match("^%s*(.-)%s*$")) end
function strjoin(sep, ...) return table.concat({ ... }, sep) end
function strlower(s) return string.lower(s) end
function strupper(s) return string.upper(s) end
strfind, strsub, strlen, strrep, strbyte, strchar, strmatch, gsub, format =
    string.find, string.sub, string.len, string.rep, string.byte, string.char,
    string.match, string.gsub, string.format
tinsert, tremove, tconcat, sort = table.insert, table.remove, table.concat, table.sort
floor, ceil, abs, max, min, mod = math.floor, math.ceil, math.abs, math.max, math.min, math.fmod
unpack = unpack or table.unpack
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
table.wipe = wipe
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
function CopyTable(t, seen)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = CopyTable(v) end
    return out
end
function Mixin(obj, ...)
    for i = 1, select("#", ...) do
        for k, v in pairs((select(i, ...))) do obj[k] = v end
    end
    return obj
end
function CreateFromMixins(...) return Mixin({}, ...) end
function securecall(fn, ...) return fn(...) end
function securecallfunction(fn, ...) return fn(...) end
function geterrorhandler() return function(msg) error(msg, 0) end end
function seterrorhandler() end
function issecretvalue() return false end
function debugstack() return "" end
function debugprofilestop() return WoW.now * 1000 end

function GetTime() return WoW.now end
function time() return WoW.epoch + math.floor(WoW.now - 1000) end
function date(fmt, t) return os.date(fmt or "%Y-%m-%d %H:%M:%S", t or time()) end
function GetServerTime() return time() end
-- El locale del cliente es un dato del escenario: S.boot({ locale = "enUS" }).
WoW.locale = WoW.locale or "esES"
function GetLocale() return WoW.locale end
-- Nombres de clase localizados por Blizzard (el addon nunca los traduce).
LOCALIZED_CLASS_NAMES_MALE = setmetatable({}, { __index = function(_, token)
    if type(token) ~= "string" then return nil end
    if WoW.locale == "esES" or WoW.locale == "esMX" then return "clase:" .. token end
    return token:sub(1, 1) .. token:sub(2):lower()
end })
LOCALIZED_CLASS_NAMES_FEMALE = LOCALIZED_CLASS_NAMES_MALE
function GetGameTime() return 12, 30, 0 end
function GetFramerate() return 60 end
function UIFrameFadeIn(f) if f and f.Show then f:Show() end end
function UIFrameFadeOut(f) end
function UIFrameFlash() end
function PanelTemplates_SetTab() end
function EasyMenu() end
function ToggleDropDownMenu() end
function CloseDropDownMenus() end
function UIDropDownMenu_Initialize() end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton() end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetText() end
function SecondsToTime(s) return tostring(s) end
function FormatLargeNumber(n) return tostring(n) end
function GetClassColor() return 1, 1, 1, "ffffffff" end
function GetMouseFocus() return nil end
function GetMouseFoci() return {} end
function IsModifierKeyDown() return false end
function GetNetStats() return 0, 0, 20, 20 end
function GetBuildInfo() return "12.1.0", "99999", "Sep 1 2026", 120100 end
function IsLoggedIn() return true end
function InCombatLockdown() return WoW.state.inCombat end
function GetRealmName() return "Eldre'Thalas" end
function GetNormalizedRealmName() return "EldreThalas" end
function UnitName(u) if u == "player" then return "Mitzuky", nil end return nil end
function UnitFullName(u) if u == "player" then return "Mitzuky", "EldreThalas" end end
function UnitClass(u) if u == "player" then return "Druida", "DRUID", 11 end end
function UnitGUID(u) if u == "player" then return "Player-1-0001" end return nil end
function UnitExists(u) return u == "player" end
function UnitIsUnit(a, b) return a == b end
function UnitLevel() return 90 end
function UnitRace(u) if u == "player" then return "Tauren", "Tauren", 6 end end
function UnitFactionGroup(u) if u == "player" then return "Horde", "Horda" end end
function UnitSex() return 2 end
function UnitHealth() return 1 end
function UnitHealthMax() return 1 end
function UnitPower() return 0 end
function UnitPowerMax() return 0 end
function UnitPowerType() return 0 end
function UnitCastingInfo() return nil end
function UnitChannelInfo() return nil end
function UnitThreatSituation() return nil end
function UnitCanAttack() return false end
function UnitIsFriend() return true end
function UnitIsEnemy() return false end
function UnitClassification() return "normal" end
function UnitCreatureType() return nil end
function GetCurrentRegion() return 3 end
function GetCurrentRegionName() return "EU" end
function UnitGroupRolesAssigned() return "HEALER" end
function UnitInParty() return false end
function UnitInRaid() return false end
function UnitIsPlayer(u) return u == "player" end
function UnitIsDeadOrGhost() return false end
function UnitAffectingCombat() return WoW.state.inCombat end
function IsInGroup() return false end
function IsInRaid() return false end
function GetNumGroupMembers() return 0 end
function GetSpecialization() return 4 end
function GetSpecializationInfo() return 105, "Restauracion", "", 0, "HEALER" end
function GetSpecializationInfoByID(id) return id, "Restauracion", "", 0, "HEALER" end
function GetInspectSpecialization() return 0 end
function NotifyInspect() end
function ClearInspectPlayer() end
function CanInspect() return false end
function GetAverageItemLevel() return 700, 700 end
function PlaySound() end
function PlaySoundFile() end
function IsInInstance() return WoW.state.inInstance, WoW.state.instanceType end
function GetInstanceInfo()
    local s = WoW.state
    return s.instanceName, s.instanceType, 8, "Mitica+", 5, 0, false,
           s.instanceMapID, 5
end
function GetCVar() return "0" end
function SetCVar() end
function GetScreenWidth() return 1920 end
function GetScreenHeight() return 1080 end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function IsAltKeyDown() return false end
function GetCursorPosition() return 0, 0 end
function hooksecurefunc(a, b, c)
    if type(a) == "table" then
        local orig = a[b]
        a[b] = function(...) local r = { orig(...) } c(...) return table.unpack(r) end
    elseif type(a) == "string" then
        local orig = _G[a]
        _G[a] = function(...) local r = { orig(...) } b(...) return table.unpack(r) end
    end
end

PlayerUtil = { GetCurrentSpecID = function() return 105 end }

C_AddOns = {
    GetAddOnMetadata = function(name, key)
        local m = WoW.tocMeta[name]
        return m and m[key] or nil
    end,
    IsAddOnLoaded = function(name) return WoW.addonsLoaded[name] == true end,
    GetNumAddOns = function() return 0 end,
    GetAddOnInfo = function(name) return name, name, "", false, "MISSING" end,
    LoadAddOn = function() return false, "MISSING" end,
    DoesAddOnExist = function(name) return WoW.tocMeta[name] ~= nil end,
}
function GetAddOnMetadata(name, key) return C_AddOns.GetAddOnMetadata(name, key) end
function IsAddOnLoaded(name) return C_AddOns.IsAddOnLoaded(name) end

C_ChallengeMode = {
    IsChallengeModeActive = function() return WoW.state.challengeActive end,
    GetActiveChallengeMapID = function()
        return WoW.state.challengeActive and WoW.state.challengeMapID or nil
    end,
    GetActiveKeystoneInfo = function()
        if not WoW.state.challengeActive then return 0, {}, false end
        return WoW.state.keyLevel, {}, false
    end,
    -- Ruby Life Pools con el mismo nombre que da GetInstanceInfo: asi
    -- DungeonRegistry la reconoce ANTES de la piedra (PRE_KEY), como en vivo.
    GetMapUIInfo = function(id)
        if tonumber(id) == 399 then return "Estanques de Vida Rubi", 399, 1800, nil end
        return "Mazmorra " .. tostring(id), id, 1800, nil
    end,
    GetCompletionInfo = function() return nil end,
    GetDeathCount = function() return 0, 0 end,
    GetMapTable = function() return { 399 } end,
    GetAffixInfo = function() return "Afijo", "", 0 end,
    GetStartTime = function() return nil end,
}
C_MythicPlus = {
    GetOwnedKeystoneChallengeMapID = function() return nil end,
    GetOwnedKeystoneLevel = function() return nil end,
    GetCurrentAffixes = function() return {} end,
    GetRunHistory = function() return {} end,
    GetSeasonBestForMap = function() return nil end,
    RequestMapInfo = function() end,
    RequestCurrentAffixes = function() end,
    GetCurrentSeason = function() return 18 end,
}
C_ChallengeModeInfo = C_ChallengeMode

-- Cronometro de la Challenge que mantiene el servidor (lo leen ChallengeClock y
-- RunSession). `timerReady=false` imita el hueco de unos segundos que hay tras
-- un /reload antes de que GetWorldElapsedTimers vuelva a devolver el timer.
LE_WORLD_ELAPSED_TIMER_TYPE_CHALLENGE_MODE = 1
function GetWorldElapsedTimers()
    local s = WoW.state
    if s.challengeActive and s.challengeStartedAt and s.timerReady ~= false then return 1 end
end
function GetWorldElapsedTime(id)
    local s = WoW.state
    if id ~= 1 or not (s.challengeActive and s.challengeStartedAt) or s.timerReady == false then
        return nil
    end
    return nil, math.floor(WoW.now - s.challengeStartedAt), LE_WORLD_ELAPSED_TIMER_TYPE_CHALLENGE_MODE
end
C_PlayerInfo = { GetPlayerMythicPlusRatingSummary = function() return { currentSeasonScore = 0 } end }
C_Map = {
    GetBestMapForUnit = function() return WoW.state.uiMapID end,
    GetMapInfo = function(id) return id and { mapID = id, name = "Mapa " .. id } or nil end,
}
C_Scenario = { GetInfo = function() return nil end, GetStepInfo = function() return nil end }
C_ScenarioInfo = {
    GetCriteriaInfo = function() return nil end,
    GetScenarioStepInfo = function() return nil end,
    GetUnitCriteriaProgressValues = function() return nil end,
}
C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() return nil end }
C_Secrets = {}
C_DamageMeter = nil
C_Texture = { GetAtlasInfo = function() return nil end }
C_Spell = { GetSpellInfo = function() return nil end, GetSpellName = function() return nil end }
C_Item = { GetItemInfo = function() return nil end }
C_CVar = { GetCVar = function() return "0" end, SetCVar = function() end }
C_Container = { GetContainerNumSlots = function() return 0 end }
C_UnitAuras = {}
C_Timer = {
    After = function(secs, fn)
        WoW.timers[#WoW.timers + 1] = { at = WoW.now + (secs or 0), fn = fn }
    end,
    NewTimer = function(secs, fn)
        local h = { cancelled = false }
        function h:Cancel() self.cancelled = true end
        function h:IsCancelled() return self.cancelled end
        WoW.timers[#WoW.timers + 1] = { at = WoW.now + (secs or 0), fn = function()
            if not h.cancelled then fn(h) end
        end }
        return h
    end,
    NewTicker = function(secs, fn, iterations)
        local h = { cancelled = false, secs = secs, fn = fn }
        function h:Cancel() self.cancelled = true end
        function h:IsCancelled() return self.cancelled end
        WoW.timers[#WoW.timers + 1] = { at = WoW.now + (secs or 0), ticker = h }
        return h
    end,
}

-- Avanza el reloj y dispara los temporizadores vencidos EN ORDEN, parando el
-- reloj en cada vencimiento. Un ticker de 1 s dentro de advance(5) dispara
-- cinco veces, como en el cliente.
function WoW.advance(secs)
    local target = WoW.now + (secs or 0)
    for _ = 1, 10000 do
        local earliest
        for _, t in ipairs(WoW.timers) do
            if t.at <= target and (not earliest or t.at < earliest) then earliest = t.at end
        end
        if not earliest then break end
        if earliest > WoW.now then WoW.now = earliest end
        local listos, resto = {}, {}
        for _, t in ipairs(WoW.timers) do
            if t.at <= WoW.now then listos[#listos + 1] = t else resto[#resto + 1] = t end
        end
        WoW.timers = resto
        for _, t in ipairs(listos) do
            if t.ticker then
                if not t.ticker.cancelled then
                    local ok, err = pcall(t.ticker.fn, t.ticker)
                    if not ok then WoW.errors[#WoW.errors + 1] = "ticker: " .. tostring(err) end
                    local paso = math.max(0.001, tonumber(t.ticker.secs) or 1)
                    WoW.timers[#WoW.timers + 1] = { at = t.at + paso, ticker = t.ticker }
                end
            else
                local ok, err = pcall(t.fn)
                if not ok then WoW.errors[#WoW.errors + 1] = "timer: " .. tostring(err) end
            end
        end
    end
    WoW.now = target
end
WoW.errors = {}

-- ── Marcos ─────────────────────────────────────────────────────────────────

local frameMeta = {}
local function nuevoRegion(kind)
    local r = { __kind = kind or "Region", __shown = true, __points = {}, __scripts = {},
                __events = {}, __w = 0, __h = 0, __text = "" }
    return setmetatable(r, frameMeta)
end

local metodos = {}
function metodos:RegisterEvent(e) self.__events[e] = true end
function metodos:UnregisterEvent(e) self.__events[e] = nil end
function metodos:RegisterAllEvents() self.__all = true end
function metodos:UnregisterAllEvents() self.__events = {} self.__all = false end
function metodos:IsEventRegistered(e) return self.__events[e] == true end
function metodos:RegisterUnitEvent(e) self.__events[e] = true end
function metodos:SetScript(s, fn) self.__scripts[s] = fn end
function metodos:GetScript(s) return self.__scripts[s] end
function metodos:HookScript(s, fn)
    local orig = self.__scripts[s]
    self.__scripts[s] = function(...) if orig then orig(...) end fn(...) end
end
function metodos:HasScript() return true end
function metodos:Show() self.__shown = true end
function metodos:Hide() self.__shown = false end
function metodos:SetShown(v) self.__shown = v and true or false end
function metodos:IsShown() return self.__shown end
function metodos:IsVisible() return self.__shown end
function metodos:SetWidth(w) self.__w = w end
function metodos:SetHeight(h) self.__h = h end
function metodos:SetSize(w, h) self.__w, self.__h = w, h end
function metodos:GetWidth() return self.__w end
function metodos:GetHeight() return self.__h end
function metodos:GetSize() return self.__w, self.__h end
function metodos:SetText(t) self.__text = t end
function metodos:GetText() return self.__text end
-- Tamano real de los objetos de fuente de Blizzard (px de altura). Sin esto el
-- mock mide igual una fuente Large que una Small y ninguna prueba de jerarquia
-- tipografica significaria nada.
WoW.FONT_HEIGHT = {
    GameFontNormalSmall = 10, GameFontHighlightSmall = 10, GameFontDisableSmall = 10,
    GameFontNormal      = 12, GameFontHighlight      = 12, GameFontDisable      = 12,
    GameFontHighlightMedium = 12, GameFontNormalMed1 = 12, GameFontNormalMed2 = 14,
    GameFontNormalLarge = 16, GameFontHighlightLarge = 16, GameFontDisableLarge = 16,
    GameFontNormalHuge  = 20, GameFontHighlightHuge  = 20,
}
WoW.FONT_DEFAULT_HEIGHT = 12

function metodos:SetFontObject(template) self.__font = template end
function metodos:GetFontObject() return self.__font end
function metodos:GetStringHeight()
    return WoW.FONT_HEIGHT[self.__font or ""] or WoW.FONT_DEFAULT_HEIGHT
end

-- Medio pixel de ancho por pixel de alto: 6 px por glifo en la fuente de 12,
-- que es lo que este mock media antes para todo. No por byte: "·" o "ñ"
-- ocupan un glifo.
function metodos:GetStringWidth()
    local glyphs = tostring(self.__text or ""):gsub("[\128-\191]", "")
    return #glyphs * (self:GetStringHeight() / 2)
end
function metodos:GetParent() return self.__parent end
function metodos:SetParent(p) self.__parent = p end
function metodos:GetName() return self.__name end
function metodos:GetObjectType() return self.__kind end
function metodos:IsObjectType(t) return self.__kind == t end
function metodos:GetFrameLevel() return 1 end
function metodos:GetEffectiveScale() return 1 end
function metodos:GetScale() return 1 end
function metodos:GetLeft() return 0 end
function metodos:GetRight() return self.__w end
function metodos:GetTop() return self.__h end
function metodos:GetBottom() return 0 end
function metodos:GetCenter() return self.__w / 2, self.__h / 2 end
function metodos:GetNumPoints() return #self.__points end
function metodos:SetPoint(...) self.__points[#self.__points + 1] = { ... } end
function metodos:ClearAllPoints() self.__points = {} end
function metodos:GetPoint(i) local p = self.__points[i or 1]; if p then return table.unpack(p) end end
function metodos:CreateFontString(_, _, template)
    local r = nuevoRegion("FontString"); r.__parent = self; r.__font = template; return r
end
function metodos:CreateTexture() local r = nuevoRegion("Texture"); r.__parent = self; return r end
function metodos:CreateMaskTexture() local r = nuevoRegion("MaskTexture"); r.__parent = self; return r end
function metodos:CreateAnimationGroup() local r = nuevoRegion("AnimationGroup"); r.__parent = self; return r end
function metodos:CreateAnimation() local r = nuevoRegion("Animation"); r.__parent = self; return r end
function metodos:GetChildren() return end
function metodos:GetRegions() return end
function metodos:GetFontString() return self.__fs end
function metodos:GetNormalTexture() return nuevoRegion("Texture") end
function metodos:GetHighlightTexture() return nuevoRegion("Texture") end
function metodos:GetPushedTexture() return nuevoRegion("Texture") end
function metodos:GetStatusBarTexture() return nuevoRegion("Texture") end
function metodos:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function metodos:SetFont() return true end
function metodos:GetValue() return self.__value or 0 end
function metodos:SetValue(v) self.__value = v end
function metodos:GetMinMaxValues() return 0, 100 end
function metodos:GetChecked() return self.__checked end
function metodos:SetChecked(v) self.__checked = v end
function metodos:GetNumLines() return 1 end
function metodos:IsMouseOver() return false end
function metodos:GetVerticalScroll() return 0 end
function metodos:GetVerticalScrollRange() return 0 end
function metodos:GetAttribute() return nil end
function metodos:GetBackdrop() return nil end
function metodos:GetID() return 0 end
function metodos:IsEnabled() return true end
function metodos:IsProtected() return false end
function metodos:IsPlaying() return false end

frameMeta.__index = function(t, k)
    local m = metodos[k]
    if m then return m end
    -- Cualquier otro metodo de interfaz (SetBackdrop, SetTextColor, SetAlpha...)
    -- no hace nada: solo se prueba logica, no pintura.
    if type(k) == "string" and k:match("^%u") then
        return function() end
    end
    return nil
end

function CreateFrame(kind, name, parent, template)
    local f = nuevoRegion(kind or "Frame")
    f.__name, f.__parent, f.__template = name, parent, template
    if kind == "Button" or (template and tostring(template):find("Button")) then
        f.__fs = nuevoRegion("FontString")
    end
    WoW.frames[#WoW.frames + 1] = f
    if name then _G[name] = f end
    return f
end

UIParent = nuevoRegion("Frame")
UIParent.__w, UIParent.__h = 1920, 1080
WorldFrame = nuevoRegion("Frame")
Minimap = nuevoRegion("Frame")
GameTooltip = nuevoRegion("GameTooltip")
DEFAULT_CHAT_FRAME = nuevoRegion("ScrollingMessageFrame")
DEFAULT_CHAT_FRAME.AddMessage = function(_, msg) WoW.printed[#WoW.printed + 1] = tostring(msg) end
ChatFrame1 = DEFAULT_CHAT_FRAME
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    WoW.printed[#WoW.printed + 1] = table.concat(parts, " ")
end
for name in pairs(WoW.FONT_HEIGHT) do
    local f = nuevoRegion("Font")
    f.__font = name
    _G[name] = f
end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
BackdropTemplateMixin = {}
SlashCmdList = {}
hash_SlashCmdList = {}
StaticPopupDialogs = {}
function StaticPopup_Show() end
function StaticPopup_Hide() end
UISpecialFrames = {}
RAID_CLASS_COLORS = setmetatable({}, { __index = function()
    return { r = 1, g = 1, b = 1, colorStr = "ffffffff" }
end })
CLASS_ICON_TCOORDS = setmetatable({}, { __index = function() return { 0, 1, 0, 1 } end })
Enum = setmetatable({}, { __index = function(t, k)
    local v = setmetatable({}, { __index = function() return 0 end })
    rawset(t, k, v)
    return v
end })
-- Valores reales (Blizzard_APIDocumentationGenerated, 12.1.0 y 12.1.5): el
-- tracker de Blizzard filtra el cronometro de la llave con este Enum.
Enum.WorldElapsedTimerTypes = { None = 0, ChallengeMode = 1, ProvingGround = 2 }
Settings = nil
SOUNDKIT = setmetatable({}, { __index = function() return 0 end })

-- ── Eventos ────────────────────────────────────────────────────────────────

-- Dispara un evento del cliente a todos los marcos que lo escuchan.
function WoW.fire(event, ...)
    for _, f in ipairs(WoW.frames) do
        if (f.__events[event] or f.__all) and f.__scripts.OnEvent then
            local ok, err = pcall(f.__scripts.OnEvent, f, event, ...)
            if not ok then WoW.errors[#WoW.errors + 1] = event .. ": " .. tostring(err) end
        end
    end
end

-- Registra los metadatos de un .toc para GetAddOnMetadata.
function WoW.registerToc(name, meta)
    WoW.tocMeta[name] = meta
end

-- Dispara el arranque de un addon como WoW: ADDON_LOADED y, si se pide,
-- PLAYER_LOGIN y PLAYER_ENTERING_WORLD.
function WoW.startAddon(name)
    WoW.addonsLoaded[name] = true
    WoW.fire("ADDON_LOADED", name)
end

function WoW.login()
    WoW.fire("PLAYER_LOGIN")
    WoW.fire("PLAYER_ENTERING_WORLD", true, false)
    WoW.advance(0)
end

return WoW
