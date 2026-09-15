MitzuForeverAtlas = MitzuForeverAtlas or {}
MitzuForeverAtlas.Probe = MitzuForeverAtlas.Probe or {}

local function available(value)
    return value ~= nil and "AVAILABLE" or "UNAVAILABLE"
end

function MitzuForeverAtlas.Probe:Collect()
    local version, build, buildDate, interfaceVersion = GetBuildInfo()
    local result = {
        version = version,
        build = build,
        buildDate = buildDate,
        interfaceVersion = interfaceVersion,
        wowProjectID = WOW_PROJECT_ID,
        apis = {
            C_Map = available(C_Map),
            C_Spell = available(C_Spell),
            C_UnitAuras = available(C_UnitAuras),
            C_ChatInfo = available(C_ChatInfo),
            UnitGUID = available(UnitGUID),
            UnitThreatSituation = available(UnitThreatSituation),
            CombatLogGetCurrentEventInfo = available(CombatLogGetCurrentEventInfo),
            C_NamePlate = available(C_NamePlate),
        },
    }
    return result
end

function MitzuForeverAtlas.Probe:Print()
    local result = self:Collect()
    print("|cff55ccffMitzuForeverAtlas Probe|r")
    print("version=" .. tostring(result.version) .. " build=" .. tostring(result.build) .. " interface=" .. tostring(result.interfaceVersion) .. " project=" .. tostring(result.wowProjectID))
    for name, state in pairs(result.apis) do
        print(name .. "=" .. state)
    end
end
