-- MitzuMPlus RuntimeVersion v5.3
-- Detecta el parche/build real del cliente en runtime; nunca depende de una versión hardcodeada.
local MitzuMPlus = _G.MitzuMPlus
if not MitzuMPlus then return end

local RuntimeVersion = {}
MitzuMPlus.RuntimeVersion = RuntimeVersion

local function safeSeason()
    if C_Seasons and C_Seasons.GetActiveSeason then
        local ok, season = pcall(C_Seasons.GetActiveSeason)
        if ok then return season end
    end
    return nil
end

function RuntimeVersion:Refresh()
    local version, build, buildDate, interfaceVersion, localizedVersion, buildInfo = GetBuildInfo()
    self.info = {
        patch = tostring(version or "unknown"),
        build = tostring(build or "unknown"),
        buildDate = tostring(buildDate or "unknown"),
        interface = tonumber(interfaceVersion) or 0,
        localizedVersion = localizedVersion,
        buildInfo = buildInfo,
        season = safeSeason(),
        projectID = WOW_PROJECT_ID,
        detectedAt = (time and time()) or 0,
    }
    MitzuMPlus.ClientVersion = self.info
    return self.info
end

function RuntimeVersion:Get()
    return self.info or self:Refresh()
end

function RuntimeVersion:IsPatchAtLeast(major, minor, patch)
    local info = self:Get()
    local a,b,c = tostring(info.patch or "0.0.0"):match("^(%d+)%.(%d+)%.(%d+)")
    a,b,c = tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
    major,minor,patch = tonumber(major) or 0, tonumber(minor) or 0, tonumber(patch) or 0
    if a ~= major then return a > major end
    if b ~= minor then return b > minor end
    return c >= patch
end

function RuntimeVersion:GetDisplayString()
    local i = self:Get()
    local s = string.format("WoW %s · build %s · Interface %d", i.patch, i.build, i.interface)
    if i.season then s = s .. " · Season " .. tostring(i.season) end
    return s
end

RuntimeVersion:Refresh()
