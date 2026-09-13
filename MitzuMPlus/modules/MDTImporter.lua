-- MitzuMPlus MDTImporter v5.3
-- Importa rutas Mythic Dungeon Tools actuales (!~MDT2~) usando las APIs nativas
-- de Blizzard: Base64 -> Deflate -> CBOR. Legacy se delega a MDT/LibDeflate si existe.
local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local Importer = {}
MitzuMPlus.MDTImporter = Importer
local PREFIX = "!~MDT2~"

local function trim(s)
    return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function decodeNative(text)
    if not C_EncodingUtil or not Enum or not Enum.CompressionMethod then
        return nil, "ENCODING_API_UNAVAILABLE"
    end
    local payload = text:sub(#PREFIX + 1)
    local ok1, decoded = pcall(C_EncodingUtil.DecodeBase64, payload)
    if not ok1 or not decoded then return nil, "MDT_BASE64_ERROR" end
    local ok2, decompressed = pcall(C_EncodingUtil.DecompressString, decoded, Enum.CompressionMethod.Deflate)
    if not ok2 or not decompressed then return nil, "MDT_DEFLATE_ERROR" end
    local ok3, preset = pcall(C_EncodingUtil.DeserializeCBOR, decompressed)
    if not ok3 or type(preset) ~= "table" then return nil, "MDT_CBOR_ERROR" end
    return preset
end

local function decodeLegacy(text)
    -- Preferir la implementación del propio MDT si está cargado: mantiene compatibilidad
    -- sin copiar librerías ni depender de detalles privados del formato antiguo.
    local MDT = rawget(_G, "MDT")
    if type(MDT) == "table" and type(MDT.StringToTable) == "function" then
        local ok, result = pcall(MDT.StringToTable, MDT, text, true)
        if ok and type(result) == "table" then return result end
    end

    if text:sub(1,1) == "!" and LibStub then
        local deflate = LibStub("LibDeflate", true)
        local serializer = LibStub("AceSerializer-3.0", true)
        if deflate and serializer then
            local encoded = text:sub(2)
            local decoded = deflate:DecodeForPrint(encoded)
            local decompressed = decoded and deflate:DecompressDeflate(decoded)
            if decompressed then
                local ok, result = serializer:Deserialize(decompressed)
                if ok and type(result) == "table" then return result end
            end
        end
    end
    return nil, "MDT_LEGACY_UNSUPPORTED"
end

function Importer:Decode(text)
    text = trim(text)
    if text == "" then return nil, "EMPTY" end
    if text:sub(1, #PREFIX) == PREFIX then
        return decodeNative(text)
    end
    return decodeLegacy(text)
end

local function getValue(preset)
    if type(preset) ~= "table" then return nil end
    if type(preset.value) == "table" then return preset.value end
    -- Algunos mensajes internos de MDT pueden ser solo la tabla value.
    if type(preset.pulls) == "table" then return preset end
    return nil
end

-- Solo CUENTA. Vale para los dos formatos de MDT (lista de indices o mapa
-- marcado) porque el numero de elementos es el mismo en ambos. Si algun dia
-- hace falta saber CUALES son, no se toca esto: se usa
-- DataStructure.SelectedClones, que lee el valor y no la clave (BUG CLONE-1).
local function countSelectedClones(clones)
    if type(clones) ~= "table" then return 0 end
    local n = 0
    for _, selected in pairs(clones) do
        if selected then n = n + 1 end
    end
    return n
end

-- Conserva CUALES clones fueron seleccionados. Soporta la lista actual de MDT
-- y el mapa marcado de presets legacy.
local function selectedClones(clones)
    local out, seen = {}, {}
    if type(clones) ~= "table" then return out end
    for key, value in pairs(clones) do
        local cloneIdx
        if type(value) == "number" then
            cloneIdx = value
        elseif value == true then
            cloneIdx = tonumber(key)
        end
        if cloneIdx and not seen[cloneIdx] then
            seen[cloneIdx] = true
            out[#out + 1] = cloneIdx
        end
    end
    table.sort(out)
    return out
end

local function enemyIdentity(enemy)
    if type(enemy) ~= "table" then return nil, nil end
    return tonumber(enemy.id or enemy[1]), tonumber(enemy.count or enemy[2])
end

local function getMDTMeta(dungeonIdx)
    local MDT = rawget(_G, "MDT")
    local mi = type(MDT) == "table" and type(MDT.mapInfo) == "table"
               and MDT.mapInfo[dungeonIdx] or nil
    local totals = type(MDT) == "table" and type(MDT.dungeonTotalCount) == "table"
                   and MDT.dungeonTotalCount[dungeonIdx] or nil
    local liveEnemies = type(MDT) == "table" and type(MDT.dungeonEnemies) == "table"
                        and MDT.dungeonEnemies[dungeonIdx] or nil
    local static = MitzuMPlus.MDTEnemyData and MitzuMPlus.MDTEnemyData[dungeonIdx] or nil
    local enemies = liveEnemies or (static and static.e)
    if type(enemies) ~= "table" then return nil end
    return {
        challengeModeID = mi and tonumber(mi.mapID) or nil,
        dungeonName = (mi and mi.englishName)
                      or (type(MDT) == "table" and type(MDT.dungeonList) == "table"
                          and MDT.dungeonList[dungeonIdx]) or nil,
        totalForces = (totals and tonumber(totals.normal))
                      or (static and tonumber(static.total)) or nil,
        enemies = enemies,
    }
end

local function forcePctForPull(pull, meta)
    if type(pull) ~= "table" or not meta or type(meta.enemies) ~= "table" or not meta.totalForces or meta.totalForces <= 0 then
        return nil
    end
    local force = 0
    for enemyIdx, clones in pairs(pull) do
        local enemy = meta.enemies[enemyIdx]
        local _, perMob = enemyIdentity(enemy)
        if perMob and perMob > 0 then
            force = force + (perMob * countSelectedClones(clones))
        end
    end
    if force <= 0 then return 0 end
    return (force / meta.totalForces) * 100
end

function Importer:ExtractRoute(preset)
    local value = getValue(preset)
    if not value or type(value.pulls) ~= "table" or #value.pulls == 0 then
        return nil, "MDT_NO_PULLS"
    end
    local dungeonIdx = tonumber(value.currentDungeonIdx)
    local meta = dungeonIdx and getMDTMeta(dungeonIdx) or nil
    local planned, numeric = {}, {}
    local weighted = meta and meta.enemies and meta.totalForces and true or false

    for i, pull in ipairs(value.pulls) do
        local pct = weighted and forcePctForPull(pull, meta) or nil
        local enemies = {}
        if type(pull) == "table" then
            for enemyIdx, clones in pairs(pull) do
                local ei = tonumber(enemyIdx)
                local selected = ei and selectedClones(clones) or {}
                if ei and #selected > 0 then
                    local npcID, forceCount = enemyIdentity(meta and meta.enemies[ei])
                    enemies[#enemies + 1] = {
                        enemyIdx = ei, npcID = npcID, forceCount = forceCount,
                        clones = selected,
                    }
                end
            end
            table.sort(enemies, function(a, b) return a.enemyIdx < b.enemyIdx end)
        end
        planned[i] = {
            pct = pct,
            enemyGroups = type(pull)=="table" and (function() local n=0; for _ in pairs(pull) do n=n+1 end; return n end)() or 0,
            enemies = enemies,
        }
        numeric[i] = pct or 0
    end

    -- Sin la base de datos de MDT seguimos sabiendo el número/orden de pulls.
    -- Se usa una distribución neutra solo como cold-start; AUTO learning la corrige.
    if not weighted then
        local even = 100 / math.max(1, #planned)
        for i=1,#planned do numeric[i] = even; planned[i].estimated = true end
    end

    local rt = MitzuMPlus.RuntimeVersion and MitzuMPlus.RuntimeVersion:Get() or nil
    return {
        pulls = numeric,
        plannedPulls = planned,
        name = tostring(preset.text or "Ruta MDT"),
        source = "MDT",
        sourceFormat = (preset.__mitzuNative and "MDT2") or "MDT",
        mdtDungeonIdx = dungeonIdx,
        challengeModeID = meta and meta.challengeModeID or nil,
        dungeonName = meta and meta.dungeonName or nil,
        forcePrecision = weighted and "exact-mdt-data" or "structure-auto-learn",
        patch = rt and rt.patch or nil,
        interface = rt and rt.interface or nil,
        updated = (time and time()) or 0,
    }
end

function Importer:Import(text, run)
    local native = trim(text):sub(1,#PREFIX) == PREFIX
    local preset, err = self:Decode(text)
    if not preset then return false, err end
    if native then preset.__mitzuNative = true end
    local route, extractErr = self:ExtractRoute(preset)
    if not route then return false, extractErr end
    if not MitzuMPlus.RouteAdvisor or not MitzuMPlus.RouteAdvisor.SaveImportedMDTRoute then
        return false, "ROUTE_ADVISOR_UNAVAILABLE"
    end
    local ok, info = MitzuMPlus.RouteAdvisor:SaveImportedMDTRoute(route, run)
    if not ok then return false, info end
    return true, info, route
end

function Importer:ShowDialog()
    if self.frame then self.frame:Show(); self.editBox:SetText(""); self.editBox:SetFocus(); return end
    local f = CreateFrame("Frame", "MitzuMPlusMDTImportFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    f:SetSize(620, 290); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:EnableMouse(true); f:SetMovable(true)
    f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize=24, insets={left=8,right=8,top=8,bottom=8}})
    end
    local title=f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge"); title:SetPoint("TOP",0,-18); title:SetText("MitzuMPlus · Importar ruta MDT")
    local help=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); help:SetPoint("TOPLEFT",24,-48); help:SetPoint("TOPRIGHT",-24,-48); help:SetJustifyH("LEFT")
    help:SetText("Pega una cadena exportada de Mythic Dungeon Tools. MDT2 actual funciona sin MDT instalado; con MDT instalado también se calculan los % exactos por pull.")
    local scroll=CreateFrame("ScrollFrame",nil,f,"InputScrollFrameTemplate"); scroll:SetPoint("TOPLEFT",24,-82); scroll:SetPoint("BOTTOMRIGHT",-34,58)
    local eb=scroll.EditBox; eb:SetMultiLine(true); eb:SetAutoFocus(true); eb:SetFontObject(ChatFontNormal); eb:SetWidth(540); eb:SetTextInsets(4,4,4,4)
    self.editBox=eb
    local import=CreateFrame("Button",nil,f,"UIPanelButtonTemplate"); import:SetSize(130,24); import:SetPoint("BOTTOMRIGHT",-28,22); import:SetText("Importar")
    import:SetScript("OnClick",function()
        local ok, info, route = Importer:Import(eb:GetText(), _G.MitzuMPlusCurrentRun)
        if ok then
            MitzuMPlus:Print(string.format("|cFF21de66MDT importado:|r %d pulls · %s", tonumber(info) or 0, route.forcePrecision == "exact-mdt-data" and "% exacto" or "AUTO learning"))
            f:Hide()
        else
            MitzuMPlus:Print("|cFFee5555No se pudo importar MDT:|r "..tostring(info))
        end
    end)
    local cancel=CreateFrame("Button",nil,f,"UIPanelButtonTemplate"); cancel:SetSize(100,24); cancel:SetPoint("RIGHT",import,"LEFT",-8,0); cancel:SetText("Cancelar"); cancel:SetScript("OnClick",function() f:Hide() end)
    f:SetScript("OnShow",function() eb:SetFocus() end)
    f:Hide(); self.frame=f; f:Show()
end
