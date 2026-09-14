-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - Database
-- Estructura de base de datos y filtrado
--
-- FIX BUG-T4: GetFilteredRuns - cálculo de semana usaba alineamiento con
--   época Unix (bloques de 7 días arbitrarios), ignorando el reset real de WoW
--   (miércoles a las 07:00 hora del servidor). Reemplazado por GetWeeklyReset().
-- FIX BUG-T5: GetAllRuns - corregida indentación inconsistente (tab+espacios).
-- FIX BUG-T6: GetStats - el loop de DPS promedio ahora hace break al llegar a
--   20 runs en lugar de seguir iterando todo el historial innecesariamente.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

-- NOTA: MitzuMPlusDB_Defaults está definido en MitzuMPlus_main.lua
-- para evitar conflictos y tener una sola fuente de verdad.

-- ─────────────────────────────────────────────────────────────────────────────
-- Stubs de season: SeasonSync.lua fue eliminado (pro player edition).
-- Estas funciones evitan crashes en Stats.lua, Core.lua y cualquier otro caller.
function MitzuMPlus:HasActiveSeason() return false end
function MitzuMPlus:GetActiveSeason() return nil end
function MitzuMPlus:IsDungeonInActiveSeason(_mapID) return true end

-- SeasonSync ya no forma parte de esta edición, pero Blizzard sigue exponiendo
-- la temporada M+ actual. Este descriptor ligero permite etiquetar runs nuevas
-- sin mantener una lista manual ni adivinar la temporada de runs antiguas.
function MitzuMPlus:GetRuntimeSeasonDescriptor()
    if not (C_MythicPlus and C_MythicPlus.GetCurrentSeason) then return nil end
    local okSeason, seasonID = pcall(C_MythicPlus.GetCurrentSeason)
    seasonID = okSeason and tonumber(seasonID) or nil
    if not seasonID or seasonID <= 0 then return nil end

    local expansionLevel
    if C_Expansion and C_Expansion.GetCurrentExpansionLevel then
        local ok, value = pcall(C_Expansion.GetCurrentExpansionLevel)
        if ok then expansionLevel = tonumber(value) end
    elseif GetExpansionLevel then
        local ok, value = pcall(GetExpansionLevel)
        if ok then expansionLevel = tonumber(value) end
    end
    expansionLevel = expansionLevel or 0
    local names = self.Constants and self.Constants.EXPANSION_NAMES or {}
    local expansionName = names[expansionLevel] or ("Expansión " .. expansionLevel)
    return {
        seasonKey = string.format("exp%d_s%d", expansionLevel, seasonID),
        seasonName = string.format("%s - Temporada %d", expansionName, seasonID),
        seasonNumber = seasonID,
        expansionLevel = expansionLevel,
    }
end

-- UTILIDAD: Timestamp del último reset semanal de WoW
-- FIX BUG-4: Los valores de reset se leen desde Constants para tener una
-- única fuente de verdad. Ya no se duplican aquí como variables locales.
-- Constants.WEEK_RESET_WDAY = 3 (Miércoles, date("%w"): 0=Dom…6=Sáb)
-- Constants.WEEK_RESET_HOUR = 9 (09:00 hora de servidor)
-- ─────────────────────────────────────────────────────────────────────────────
local function GetWeeklyReset()
    local C = MitzuMPlus.Constants or {}
    local RESET_WEEKDAY = C.WEEK_RESET_WDAY or 3
    local RESET_HOUR    = C.WEEK_RESET_HOUR or 9

    if not time then return 0, 0 end
    local now         = time()
    local secInDay    = 86400
    local secInWeek   = 7 * secInDay

    -- Hora actual del servidor (WoW date() devuelve hora local de servidor)
    local curHour   = tonumber(date("%H")) or 0
    local curMin    = tonumber(date("%M")) or 0
    local curSec    = tonumber(date("%S")) or 0
    local curWday   = tonumber(date("%w")) or 0  -- 0=Domingo

    -- Segundos transcurridos desde medianoche del servidor
    local secSinceMidnight = curHour * 3600 + curMin * 60 + curSec

    -- Timestamp de la medianoche de hoy (server time)
    local todayMidnight = now - secSinceMidnight

    -- Días completos hacia atrás hasta el RESET_WEEKDAY
    local daysBack = (curWday - RESET_WEEKDAY + 7) % 7

    -- Si hoy ES el día de reset pero aún no ha llegado la hora, retroceder 7 días
    if daysBack == 0 and curHour < RESET_HOUR then
        daysBack = 7
    end

    local thisWeekStart = todayMidnight - daysBack * secInDay + RESET_HOUR * 3600
    local lastWeekStart = thisWeekStart - secInWeek
    local lastWeekEnd   = thisWeekStart

    return thisWeekStart, lastWeekStart, lastWeekEnd
end

-- ─────────────────────────────────────────────────────────────────────────────
-- GUARDAR RUN
-- ─────────────────────────────────────────────────────────────────────────────

function MitzuMPlus:SaveRun(runData)
    if not self.db then return nil end

    -- FIX BUG-5: sanitizar y validar ANTES de guardar para evitar que lleguen
    -- valores nil/malformados a la DB y crasheen la UI al mostrarlos.
    if type(self.SanitizeRunData) == "function" then
        runData = self:SanitizeRunData(runData)
    end
    if not runData then
        if self.Print then
            self:Print("|cFFFF4444[MitzuMPlus] SaveRun: datos inválidos, run descartada.|r")
        end
        return nil
    end
    if type(self.ValidateRunData) == "function" then
        local ok, reason = self:ValidateRunData(runData)
        if not ok then
            if self.Print then
                self:Print(string.format(
                    "|cFFFF4444[MitzuMPlus] SaveRun: validación fallida (%s), run descartada.|r",
                    tostring(reason)))
            end
            return nil
        end
    end

    local g = self.db.global
    local runID = g.nextRunID or 1
    g.nextRunID = runID + 1

    -- En este punto runData es siempre una tabla válida (SanitizeRunData + ValidateRunData
    -- lo garantizan arriba). El check type ~= "table" que había aquí era código muerto.
    runData.runID = runID
    g.runs[runID] = runData

    if self.db.char then
        self.db.char.lastRunID   = runID
    end

    if self.SendMessage then
        self:SendMessage("MITZUMPLUS_RUN_SAVED", runID, runData)
    end

    return runID
end

-- ─────────────────────────────────────────────────────────────────────────────
-- OBTENER RUN POR ID
-- ─────────────────────────────────────────────────────────────────────────────

function MitzuMPlus:GetRun(runID)
    if not self.db then return nil end
    return self.db.global.runs[runID]
end

-- ─────────────────────────────────────────────────────────────────────────────
-- OBTENER TODAS LAS RUNS (ordenadas de más reciente a más antigua)
-- FIX: corregida indentación en return out
-- ─────────────────────────────────────────────────────────────────────────────

function MitzuMPlus:GetAllRuns()
    if not self.db then return {} end

    local out = {}
    for runID, run in pairs(self.db.global.runs or {}) do
        if type(run) == "table" then
            run.runID = runID
            out[#out + 1] = run
        end
    end

    table.sort(out, function(a, b)
        local at = tonumber(a.startTime) or 0
        local bt = tonumber(b.startTime) or 0
        return at > bt
    end)

    return out
end

-- ─────────────────────────────────────────────────────────────────────────────
-- MAZMORRAS ÚNICAS (para filtros)
-- ─────────────────────────────────────────────────────────────────────────────

function MitzuMPlus:GetUniqueDungeons()
    if type(self.HasActiveSeason) == "function" and self:HasActiveSeason() then
        local season = type(self.GetActiveSeason) == "function" and self:GetActiveSeason()
        if season and season.dungeons and #season.dungeons > 0 then
            local list = {}
            for _, d in ipairs(season.dungeons) do
                if d.name and d.name ~= "" then
                    list[#list + 1] = d.name
                end
            end
            table.sort(list)
            return list
        end
    end

    local seen, list = {}, {}
    for _, run in ipairs(self:GetAllRuns()) do
        local dn = run.dungeonName
        if dn and dn ~= "" and not seen[dn] then
            seen[dn] = true
            list[#list + 1] = dn
        end
    end
    table.sort(list)
    return list
end

-- ─────────────────────────────────────────────────────────────────────────────
-- OBTENER RUNS FILTRADAS Y PAGINADAS
-- FIX BUG-T4: cálculo de semana corregido para usar reset real de WoW.
-- ─────────────────────────────────────────────────────────────────────────────

function MitzuMPlus:GetFilteredRuns(filters)
    filters = filters or {}

    local page = tonumber(filters.page) or 1
    local pageSize = tonumber(filters.pageSize)
                     or (self.db and self.db.profile and self.db.profile.settings
                         and self.db.profile.settings.pageSize)
                     or 20
    if page < 1     then page = 1     end
    if pageSize < 1 then pageSize = 20 end

    local all = self:GetAllRuns()

    -- Calcular ventanas de semana una sola vez (evita llamar GetWeeklyReset por run)
    local thisWeekStart, lastWeekStart, lastWeekEnd
    local weekFilter = filters.week
    if weekFilter and weekFilter ~= "" then
        thisWeekStart, lastWeekStart, lastWeekEnd = GetWeeklyReset()
    end

    local result         = {}
    local totalInTime    = 0
    local totalOutOfTime = 0
    local search = (filters.search or ""):lower()

    for _, run in ipairs(all) do
        local ok = true

        -- Filtro por nombre de mazmorra (string exacta)
        if ok and filters.dungeon and filters.dungeon ~= "" then
            if run.dungeonName ~= filters.dungeon then
                ok = false
            end
        end

        -- Filtro por ID de mazmorra
        if ok and filters.dungeonID and run.dungeonID ~= filters.dungeonID then
            ok = false
        end

        -- FIX BUG-FILTER-1: Filtro por nivel de llave (nunca se aplicaba).
        -- filters.keyLevel puede ser un número exacto, o una tabla {min, max}.
        if ok and filters.keyLevel then
            local kl = tonumber(run.keyLevel) or 0
            if type(filters.keyLevel) == "table" then
                local kmin = tonumber(filters.keyLevel.min) or 0
                local kmax = tonumber(filters.keyLevel.max) or math.huge
                if kl < kmin or kl > kmax then ok = false end
            else
                if kl ~= tonumber(filters.keyLevel) then ok = false end
            end
        end

        -- Filtro de resultado
        if ok and filters.inTimeOnly  and not run.inTime then ok = false end
        if ok and filters.outTimeOnly and run.inTime     then ok = false end

        -- Filtro por rol
        if ok and filters.role and filters.role ~= "" then
            if run.playerRole ~= filters.role then ok = false end
        end

        -- Búsqueda libre (nombre de mazmorra)
        if ok and search ~= "" then
            local dn = (run.dungeonName or ""):lower()
            if not dn:find(search, 1, true) then ok = false end
        end

        -- Filtro por semana (usa timestamps calculados correctamente)
        if ok and weekFilter and weekFilter ~= "" and thisWeekStart then
            local st = tonumber(run.startTime) or 0
            if weekFilter == "thisweek" then
                if st < thisWeekStart then ok = false end
            elseif weekFilter == "lastweek" then
                if st < lastWeekStart or st >= lastWeekEnd then ok = false end
            end
        end

        if ok then
            result[#result + 1] = run
            if run.inTime then
                totalInTime = totalInTime + 1
            else
                totalOutOfTime = totalOutOfTime + 1
            end
        end
    end

    -- Ordenación
    local sortBy  = filters.sortBy  or "date"
    local sortDir = filters.sortDir or "desc"

    local function GetDps(r)
        local ct = tonumber(r.completionTime) or 0
        local dt = r.stats and tonumber(r.stats.damageTotal) or 0
        return (ct > 0) and (dt / ct) or 0
    end

    table.sort(result, function(a, b)
        local va, vb
        if     sortBy == "date"    then va, vb = tonumber(a.startTime)  or 0, tonumber(b.startTime)  or 0
        elseif sortBy == "dungeon" then va, vb = tostring(a.dungeonName or ""), tostring(b.dungeonName or "")
        elseif sortBy == "level"   then va, vb = tonumber(a.keyLevel)   or 0, tonumber(b.keyLevel)   or 0
        elseif sortBy == "result"  then va, vb = a.inTime and 1 or 0,         b.inTime and 1 or 0
        elseif sortBy == "time"    then va, vb = tonumber(a.completionTime) or 0, tonumber(b.completionTime) or 0
        elseif sortBy == "dps"     then va, vb = GetDps(a), GetDps(b)
        elseif sortBy == "deaths"  then
            va = a.stats and tonumber(a.stats.deaths)  or 0
            vb = b.stats and tonumber(b.stats.deaths)  or 0
        elseif sortBy == "kicks"   then
            local as = a.stats or {}
            local bs = b.stats or {}
            va = tonumber(as.kicksGroup) or tonumber(as.kicks) or 0
            vb = tonumber(bs.kicksGroup) or tonumber(bs.kicks) or 0
        else
            va, vb = tonumber(a.startTime) or 0, tonumber(b.startTime) or 0
        end
        if sortDir == "asc" then
            return va < vb
        else
            return va > vb
        end
    end)

    -- Paginación
    local total      = #result
    local startIndex = (page - 1) * pageSize + 1
    local endIndex   = math.min(page * pageSize, total)

    local pageRuns = {}
    for i = startIndex, endIndex do
        pageRuns[#pageRuns + 1] = result[i]
    end

    local totalPages = (pageSize > 0) and math.max(1, math.ceil(total / pageSize)) or 1

    return {
        runs           = pageRuns,
        total          = total,
        totalInTime    = totalInTime,
        totalOutOfTime = totalOutOfTime,
        page           = page,
        pageSize       = pageSize,
        totalPages     = totalPages,
    }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- ELIMINAR RUN
-- ─────────────────────────────────────────────────────────────────────────────

function MitzuMPlus:DeleteRun(runID, deferPBRebuild)
    if not self.db then return end
    runID=tonumber(runID)
    for key,run in pairs(self.db.global.runs or {}) do
        if type(run)=="table" and tonumber(run.runID)==runID then
            self.db.global.runs[key]=nil
            -- personalBests es una caché derivada del historial. Una run
            -- eliminada no puede seguir influyendo en récords futuros.
            if not deferPBRebuild and self.PersonalBest and self.PersonalBest.RebuildFromHistory then
                self.PersonalBest:RebuildFromHistory()
            end
            return true
        end
    end
    return false
end

-- ─────────────────────────────────────────────────────────────────────────────
-- ESTADÍSTICAS GLOBALES
-- FIX BUG-T6: el loop para DPS promedio ahora hace break temprano al alcanzar
--   20 runs, en lugar de iterar todo el historial innecesariamente.
-- ─────────────────────────────────────────────────────────────────────────────

function MitzuMPlus:GetStats()
    local runs     = self:GetAllRuns()
    local total    = #runs
    local bestTime = nil
    local bestKey  = nil
    local inTime   = 0

    -- BUG-L8 FIX: Loop 1 — bestTime, bestKey e inTime (recorre todas las runs sin break)
    for _, run in ipairs(runs) do
        if run.inTime then inTime = inTime + 1 end

        if run.inTime and run.completionTime and run.completionTime > 0 then
            if not bestTime or run.completionTime < (bestTime.completionTime or math.huge) then
                bestTime = run
            end
        end

        if run.keyLevel then
            if not bestKey or (tonumber(run.keyLevel) or 0) > (tonumber(bestKey.keyLevel) or 0) then
                bestKey = run
            end
        end
    end

    -- BUG-L8 FIX: Loop 2 — DPS promedio (limitado a 20 runs más recientes, con break seguro)
    local dpsSum   = 0
    local dpsCount = 0
    for _, run in ipairs(runs) do
        if run.stats and run.stats.damageTotal
           and run.completionTime and run.completionTime > 0 then
            dpsSum   = dpsSum   + (run.stats.damageTotal / run.completionTime)
            dpsCount = dpsCount + 1
            if dpsCount == 20 then break end
        end
    end

    return {
        totalRuns     = total,
        bestTime      = bestTime,
        bestKey       = bestKey,
        inTimeCount   = inTime,
        outOfTimeCount = total - inTime,
        avgDPS20      = (dpsCount > 0) and (dpsSum / dpsCount) or 0,
    }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- PROMEDIOS POR MAZMORRA Y NIVEL DE LLAVE
-- ─────────────────────────────────────────────────────────────────────────────

function MitzuMPlus:GetAverages(dungeonID, keyLevel, margin)
    margin = margin or 1
    local runs = self:GetAllRuns()
    local sum  = { dps=0, deaths=0, kicks=0, dispels=0, time=0 }
    local n    = 0

    for _, run in ipairs(runs) do
        if run.dungeonID == dungeonID
           and run.keyLevel and keyLevel
           and math.abs((run.keyLevel or 0) - keyLevel) <= margin then

            local ct  = tonumber(run.completionTime) or 0
            local dt  = run.stats and tonumber(run.stats.damageTotal) or 0
            local dps = (ct > 0) and (dt / ct) or 0

            sum.dps     = sum.dps     + dps
            sum.deaths  = sum.deaths  + (run.stats and (run.stats.deaths  or 0) or 0)
            local s = run.stats or {}
            sum.kicks   = sum.kicks   + (tonumber(s.kicksGroup) or tonumber(s.kicks) or 0)
            sum.dispels = sum.dispels + (tonumber(s.dispelsGroup) or tonumber(s.dispels) or 0)
            sum.time    = sum.time    + ct
            n = n + 1
        end
    end

    if n == 0 then
        return { count=0, dps=0, deaths=0, kicks=0, dispels=0, time=0 }
    end

    return {
        count   = n,
        dps     = sum.dps     / n,
        deaths  = sum.deaths  / n,
        kicks   = sum.kicks   / n,
        dispels = sum.dispels / n,
        time    = sum.time    / n,
    }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- MEJOR RUN PERSONAL (en tiempo, menor completionTime)
-- ─────────────────────────────────────────────────────────────────────────────

function MitzuMPlus:GetPersonalBest()
    local runs = self:GetAllRuns()
    local best = nil
    for _, run in ipairs(runs) do
        if run.inTime and run.completionTime and run.completionTime > 0 then
            if not best or run.completionTime < (best.completionTime or math.huge) then
                best = run
            end
        end
    end
    return best
end
