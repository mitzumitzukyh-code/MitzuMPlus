-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - Core (v4.0.0)
-- Sistema central de eventos y tracking
--
-- v4.0.0 REWRITE:
--           El tracking ahora usa C_DamageMeter API como fuente primaria,
--           con fallback a CLEU para clientes pre-12.0 (TWW).
--   ROLE-1  GetCurrentSpecIndex/GetCurrentRole completamente reescritos.
--           Midnight usa PlayerUtil.GetCurrentSpecID() → specID directo.
--           GetSpecializationInfoByID(specID) obtiene nombre + rol.
--   API-FIX GetAverageItemLevel → C_PaperDollInfo.GetAverageItemLevels()
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus_Historial"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

_G.MitzuMPlusCurrentRun = nil

-- ─────────────────────────────────────────────────────────────────────────────
-- DETECCIÓN DE VERSIÓN: ¿Estamos en Midnight (12.0+)?
-- ─────────────────────────────────────────────────────────────────────────────

local IS_MIDNIGHT = false
do
    local _, _, _, interfaceVersion = GetBuildInfo()
    IS_MIDNIGHT = (tonumber(interfaceVersion) or 0) >= 120000
end

MitzuMPlus.IS_MIDNIGHT = IS_MIDNIGHT

-- FIX BUG-SECRET-GLOBAL: issecretvalue() API (Midnight 12.0+) used across all
-- handlers to detect opaque Secret Values that crash on table-key or comparison.
local _issecretvalue = rawget(_G, "issecretvalue")

-- ─────────────────────────────────────────────────────────────────────────────
-- UTILIDADES INTERNAS
-- ─────────────────────────────────────────────────────────────────────────────

local function Now()
    return time and time() or 0
end

local function BuildFullPlayerName(name, realm)
    name = tostring(name or "")
    realm = tostring(realm or "")
    if name == "" then return "" end
    if realm == "" then
        realm = (GetRealmName and GetRealmName()) or ""
    end
    if realm ~= "" and not string.find(name, "%-", 1, true) then
        return name .. "-" .. realm
    end
    return name
end

local function ExtractRatingNumber(value)
    if type(value) == "number" then
        return math.max(0, math.floor(value + 0.5))
    end
    if type(value) ~= "table" then return 0 end

    local candidates = {
        value.currentSeasonScore,
        value.score,
        value.mythicPlusScore,
        value.mythic_rating,
        value.mythicRating,
    }
    for _, v in ipairs(candidates) do
        local n = tonumber(v)
        if n and n > 0 then
            return math.floor(n + 0.5)
        end
    end

    if type(value.mythicKeystoneProfile) == "table" then
        local profile = value.mythicKeystoneProfile
        local n = tonumber(profile.currentScore) or tonumber(profile.score)
        if n and n > 0 then
            return math.floor(n + 0.5)
        end
    end

    return 0
end

local function GetUnitMythicRating(unit, unitName, unitRealm)
    -- Fuente 1: API Blizzard (funciona seguro para player, y en algunos
    -- clientes también para party/raid units).
    if C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary and unit and unit ~= "" then
        local ok, summary = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit)
        if ok then
            local score = ExtractRatingNumber(summary)
            if score > 0 then return score end
        end
    end

    -- Fuente 2 (opcional): API del addon RaiderIO si está cargado.
    local fullName = BuildFullPlayerName(unitName, unitRealm)
    if fullName == "" then return 0 end

    local rio = rawget(_G, "RaiderIO")
    if type(rio) == "table" then

        local probes = {
            function()
                if type(rio.GetScore) == "function" then
                    return rio:GetScore(fullName)
                end
            end,
            function()
                if type(rio.GetScore) == "function" then
                    return rio.GetScore(fullName)
                end
            end,
            function()
                if type(rio.GetPlayerScore) == "function" then
                    return rio:GetPlayerScore(fullName)
                end
            end,
            function()
                if type(rio.GetPlayerScore) == "function" then
                    return rio.GetPlayerScore(fullName)
                end
            end,
            function()
                if type(rio.GetProfile) == "function" then
                    return rio:GetProfile(fullName)
                end
            end,
            function()
                if type(rio.GetProfile) == "function" then
                    return rio.GetProfile(fullName)
                end
            end,
        }

        for _, probe in ipairs(probes) do
            local ok, result = pcall(probe)
            if ok then
                local score = ExtractRatingNumber(result)
                if score > 0 then return score end
            end
        end
    end

    return 0
end

-- FIX ROLE-1: Obtener el specID actual del jugador.
-- En Midnight, PlayerUtil.GetCurrentSpecID() es la API canónica.
-- En TWW (11.x), GetSpecialization() devuelve un ÍNDICE (1-4), no un specID.
-- Necesitamos manejar ambos casos.
local function GetPlayerSpecID()
    -- Ruta 1: PlayerUtil (funciona en TWW 11.0.2+ y Midnight)
    if PlayerUtil and PlayerUtil.GetCurrentSpecID then
        local specID = PlayerUtil.GetCurrentSpecID()
        if specID and specID > 0 then
            return specID
        end
    end

    -- Ruta 2: GetSpecialization() devuelve ÍNDICE, convertir a specID
    if GetSpecialization then
        local specIndex = GetSpecialization()
        if specIndex and specIndex > 0 then
            if GetSpecializationInfo then
                local specID = GetSpecializationInfo(specIndex)
                if specID and specID > 0 then
                    return specID
                end
            end
        end
    end

    return nil
end

-- FIX ROLE-2: Obtener el rol y nombre de spec a partir del specID.
-- GetSpecializationInfoByID(specID) funciona en todas las versiones modernas.
local function GetPlayerRoleAndSpec()
    local specID = GetPlayerSpecID()
    if not specID then
        return "DAMAGER", "Unknown", nil
    end

    -- GetSpecializationInfoByID acepta un specID (no un índice)
    if GetSpecializationInfoByID then
        local id, name, description, icon, role = GetSpecializationInfoByID(specID)
        if role and role ~= "" then
            return role, name or "Unknown", specID
        end
    end

    -- Fallback: UnitGroupRolesAssigned
    if UnitGroupRolesAssigned then
        local role = UnitGroupRolesAssigned("player")
        if role and role ~= "NONE" and role ~= "" then
            return role, "Unknown", specID
        end
    end

    return "DAMAGER", "Unknown", specID
end

-- Exportar para uso en otros módulos
MitzuMPlus.GetPlayerSpecID = GetPlayerSpecID
MitzuMPlus.GetPlayerRoleAndSpec = GetPlayerRoleAndSpec

-- ─────────────────────────────────────────────────────────────────────────────
-- REGISTRO DE EVENTOS PRINCIPALES
-- ─────────────────────────────────────────────────────────────────────────────

function MitzuMPlus:RegisterCoreEvents()
    if self._eventsRegistered then
        if self.Print then self:Print("Eventos ya registrados.") end
        return
    end

    local function DoRegister()
        if MitzuMPlus._eventsRegistered then return true end
        if InCombatLockdown and InCombatLockdown() then return false end

        if not MitzuMPlus._eventFrame then
            MitzuMPlus._eventFrame = CreateFrame("Frame")
        end

        if not MitzuMPlus._eventHandlers then
            MitzuMPlus._eventHandlers = {
                -- CHALLENGE_MODE_START ya NO arranca la run. Se dispara al
                -- ENTRAR a la mazmorra (BUG CTX-1) y, cuando la llave si
                -- arrancaba, competia con MITZU_KEY_STARTED: los dos caminos
                -- llamaban a OnChallengeStart y salia "Ya hay una run activa.
                -- Ignorando inicio duplicado." El guard tapaba el sintoma.
                -- Ahora hay UN solo suscriptor autorizado, al final de este
                -- fichero: DungeonContext -> MITZU_KEY_STARTED.
                CHALLENGE_MODE_COMPLETED = "OnChallengeCompleted",
                CHALLENGE_MODE_RESET     = "OnChallengeReset",
                PLAYER_ENTERING_WORLD    = "OnPlayerEnteringWorld",
                ENCOUNTER_END            = "OnBossKill",
                SCENARIO_CRITERIA_UPDATE = "OnScenarioCriteriaUpdate",
                CRITERIA_UPDATE          = "OnScenarioCriteriaUpdate",
                GROUP_ROSTER_UPDATE      = "OnGroupRosterUpdate",
            }
        end

        MitzuMPlus._eventFrame:SetScript("OnEvent", function(_, event, ...)
            local method = MitzuMPlus._eventHandlers and MitzuMPlus._eventHandlers[event]
            if method and MitzuMPlus[method] then
                MitzuMPlus[method](MitzuMPlus, event, ...)
            end
        end)

        for ev in pairs(MitzuMPlus._eventHandlers) do
            if InCombatLockdown and InCombatLockdown() then
                if MitzuMPlus.Print then
                    MitzuMPlus:Print("No se pueden registrar eventos en combate. Reintentando al salir.")
                end
                return false
            end
            local ok, err = pcall(function()
                MitzuMPlus._eventFrame:RegisterEvent(ev)
            end)
            if not ok then
                -- v5.4.2: antes un solo evento invalido abortaba el registro
                -- COMPLETO y el addon se quedaba sin tracking. Ahora se avisa y
                -- se continua con el resto.
                if MitzuMPlus.Print then
                    MitzuMPlus:Print("|cFFFF9922Evento no registrado:|r " .. tostring(ev) .. " (" .. tostring(err) .. ")")
                end
            end
        end

        MitzuMPlus._trackingActive = false

        MitzuMPlus._eventsRegistered = true
        return true
    end

    if DoRegister() then
        MitzuMPlus:_SetupCombatFrameDeferred()
        return
    end

    if self._eventRegisterTicker and self._eventRegisterTicker.Cancel then
        self._eventRegisterTicker:Cancel()
        self._eventRegisterTicker = nil
    end
    if C_Timer and C_Timer.NewTicker then
        self._eventRegisterTicker = C_Timer.NewTicker(1, function(t)
            if DoRegister() then
                t:Cancel()
                MitzuMPlus._eventRegisterTicker = nil
                MitzuMPlus:_SetupCombatFrameDeferred()
            end
        end)
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- BUG FIX (ADDON_ACTION_FORBIDDEN en /reload con ChatCopyPaste):
--
-- La v1 del fix (creaba _combatFrame dentro de DoRegister) seguía fallando
-- porque `OnInitialize` corre dentro de AceAddon:InitializeAddon (LibStub),
-- que es COMPARTIDO con otros addons (ChatCopyPaste, HandyNotes...). Si
-- cualquiera de esos está taintado en el momento del reload, nuestro
-- RegisterEvent hereda la contaminación y Blizzard lo bloquea.
--
-- Solución v2: diferir la creación del frame + RegisterEvent con
-- C_Timer.After(0, ...). Esto lo ejecuta UN frame después, ya fuera de la
-- cadena de llamadas iniciada por AceAddon:InitializeAddon. Tanto el
-- call-stack como cualquier taint que venga de la lib compartida quedan
-- limpios al procesar el OnUpdate timer.
-- ═══════════════════════════════════════════════════════════════════════════
function MitzuMPlus:_SetupCombatFrameDeferred()
    if MitzuMPlus._combatFrame then return end
    if not (C_Timer and C_Timer.After) then
        -- Fallback improbable: ejecutar directamente.
        MitzuMPlus:_DoSetupCombatFrame()
        return
    end
    C_Timer.After(0, function()
        MitzuMPlus:_DoSetupCombatFrame()
    end)
end

function MitzuMPlus:_DoSetupCombatFrame()
    if MitzuMPlus._combatFrame then return end
    -- Midnight 12.x: never register CLEU or infer combat from UNIT_* events.
    -- Blizzard's supported source is C_DamageMeter; values may be secret in combat.
    MitzuMPlus._combatFrame = CreateFrame("Frame")
    MitzuMPlus._combatFrame:SetScript("OnEvent", function(_, event, ...)
        if not MitzuMPlus._trackingActive then return end
        if event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" and MitzuMPlus.OnDamageMeterUpdate then
            pcall(MitzuMPlus.OnDamageMeterUpdate, MitzuMPlus, event, ...)
        end
    end)
    if _G.C_DamageMeter then
        pcall(function() MitzuMPlus._combatFrame:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED") end)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- ESTRUCTURA DE RUN VACÍA
-- ─────────────────────────────────────────────────────────────────────────────

function MitzuMPlus:NewRunData()
    return {
        dungeonID      = 0,
        dungeonName    = "",
        keyLevel       = 0,
        affixes        = {},
        startTime      = 0,
        endTime        = 0,
        completionTime = 0,
        timeLimit      = 0,
        inTime         = false,
        playerName     = "",
        playerRealm    = "",
        playerClass    = "",
        playerSpec     = "",
        playerSpecID   = 0,
        playerRole     = "",
        playerIlvl     = 0,
        playerMythicRating = 0,  -- Puntaje M+ del jugador al iniciar la run (API Blizzard)
        group          = {},
        equippedItems  = {},
        stats = {
            -- Blizzard-supported Midnight metrics only.
            damageTotal    = 0,
            healingTotal   = 0,
            absorbTotal    = 0,
            damageTaken    = 0,
            avoidableDmg   = 0,
            -- deaths     = muertes DEL GRUPO (C_ChallengeMode.GetDeathCount)
            -- deathsSelf = muertes DEL JUGADOR (Enum.DamageMeterType.Deaths)
            -- v5.4.2 (BUG A6): antes se fusionaban con math.max en el mismo
            -- campo, asi que una de las dos cifras siempre era mentira.
            deaths         = 0,
            deathsSelf     = 0,
            kicks          = 0,
            dispels        = 0,
            dpsOfficial    = 0,
            hpsOfficial    = 0,
            dtpsOfficial   = 0,
        },
        timeline    = {},
        loot        = {},
        notes       = "",
        tags        = {},
        isFavorite  = false,
        seasonKey   = nil,
        seasonName  = nil,
        -- v4.0.0: fuente de datos usada para esta run
        dataSource  = (IS_MIDNIGHT and _G.C_DamageMeter and (_G.C_DamageMeter.GetCombatSessionFromType or _G.C_DamageMeter.GetCombatSessionFromID))
            and "C_DamageMeter" or (IS_MIDNIGHT and "STRUCTURAL_ONLY" or "CLEU"),
    }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- CHALLENGE MODE — INICIO
-- ─────────────────────────────────────────────────────────────────────────────

function MitzuMPlus:OnPlayerEnteringWorld()
    if self.LoadActiveSeason then
        self:LoadActiveSeason()
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(3.0, function()
            if MitzuMPlus.BackgroundSeasonScan then
                MitzuMPlus:BackgroundSeasonScan()
            end
        end)
        -- Resume overlay after /reload if M+ is active
        C_Timer.After(1.5, function()
            if MitzuMPlus.ResumeOverlayIfActive then
                MitzuMPlus:ResumeOverlayIfActive()
            end
        end)
        -- Detectar auto-abandono: run activa pero ya no estamos en M+
        C_Timer.After(0.5, function()
            local run = _G.MitzuMPlusCurrentRun
            if not run then return end
            local mapID = C_ChallengeMode
                and C_ChallengeMode.GetActiveChallengeMapID
                and C_ChallengeMode.GetActiveChallengeMapID()
            if mapID and mapID ~= 0 then return end  -- seguimos en M+
            -- Registrar al propio jugador como quien se fue
            run.abandoners = run.abandoners or {}
            local playerName = run.playerName or ""
            if playerName == "" then return end
            for _, ab in ipairs(run.abandoners) do
                if ab.name == playerName then return end  -- ya registrado
            end
            local elapsed = math.max(0, Now() - (run.startTime or 0))
            run.abandoners[#run.abandoners + 1] = {
                name   = playerName,
                class  = run.playerClass or "",
                role   = run.playerRole  or "",
                leftAt = elapsed,
                isSelf = true,
            }
        end)
    end
end

-- ───────────────────────────────────────────────────────────────────────────
-- ABANDONO DE GRUPO DURANTE RUN ACTIVA
-- ───────────────────────────────────────────────────────────────────────────
function MitzuMPlus:OnGroupRosterUpdate()
    local run = _G.MitzuMPlusCurrentRun
    if not run then return end
    -- Ignorar los primeros 15 s: el grupo se puede estar formando aún
    if not run.startTime or (Now() - run.startTime) < 15 then return end

    -- Conjunto de nombres en el grupo ACTUAL
    local current = {}
    local selfName = run.playerName or ""
    if selfName ~= "" then current[selfName] = true end
    local groupSize = GetNumGroupMembers and GetNumGroupMembers() or 0
    for i = 1, math.min(groupSize, 4) do
        local unit = "party" .. i
        if UnitExists(unit) then
            local name = UnitName(unit)
            if name and name ~= "" then current[name] = true end
        end
    end

    run.abandoners = run.abandoners or {}

    for _, member in ipairs(run.group or {}) do
        local name = member.name or ""
        if name ~= "" and name ~= selfName and not current[name] then
            -- Miembro original ya no está en el grupo
            local already = false
            for _, ab in ipairs(run.abandoners) do
                if ab.name == name then already = true; break end
            end
            if not already then
                local elapsed = math.max(0, Now() - run.startTime)
                run.abandoners[#run.abandoners + 1] = {
                    name   = name,
                    class  = member.class or "",
                    role   = member.role  or "",
                    leftAt = elapsed,
                    isSelf = false,
                }
                run.timeline[#run.timeline + 1] = {
                    timestamp = Now(),
                    type      = "abandon",
                    note      = name .. " salió del grupo",
                }
                if self.Print then
                    self:Print(string.format(
                        "|cFFFF6B6B[Abandono]|r %s salió a los %d:%02d.",
                        name, math.floor(elapsed / 60), elapsed % 60
                    ))
                end
            end
        end
    end
end

function MitzuMPlus:OnChallengeStart()
    -- ─────────────────────────────────────────────────────────────────────
    -- BUG CTX-1 (v7.11.0) — este handler colgaba de CHALLENGE_MODE_START, y
    -- ese evento NO significa que la llave haya empezado: se dispara al
    -- ENTRAR a la mazmorra en modo piedra. Resultado visto en vivo:
    -- "M+ Iniciada: Estanques de Vida Rubi +4" antes de insertar la piedra, y
    -- una run entera creada en el historial sin llave.
    --
    -- La autoridad es IsChallengeModeActive(). Si todavia no lo esta, no se
    -- arranca nada: DungeonContext vuelve a llamar aqui por MITZU_KEY_STARTED
    -- cuando la llave arranca de verdad (ver el final de este fichero).
    -- ─────────────────────────────────────────────────────────────────────
    local activa = C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
                   and C_ChallengeMode.IsChallengeModeActive()
    if not activa then
        self._pendingChallengeStart = true
        return
    end
    self._pendingChallengeStart = nil

    -- FIX DEDUP-2: Si ya tenemos una run activa para este dungeon, no crear otra
    if _G.MitzuMPlusCurrentRun then
        if self.Print then
            self:Print("|cFFFF9922Ya hay una run activa. Ignorando inicio duplicado.|r")
        end
        return
    end

    -- FIX BUG-DEDUP-3: Limpiar la clave anti-duplicado de la run anterior para no
    -- bloquear runs legítimas del mismo dungeon al mismo nivel en la misma sesión.
    self._lastCompletedRunKey = nil

    local run = self:NewRunData()

    local mapID = C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID and
                  C_ChallengeMode.GetActiveChallengeMapID()
    if not mapID or mapID == 0 then
        if self.Print then
            self:Print("|cFFFF4444Error:|r No se pudo obtener el mapa activo.")
        end
        return
    end
    run.dungeonID = mapID

    if self.HasActiveSeason and self:HasActiveSeason() then
        if not self:IsDungeonInActiveSeason(mapID) then
            if self.Print then
                self:Print(string.format(
                    "|cFFFF9922Advertencia:|r La mazmorra (ID %d) no es parte de la temporada activa.", mapID))
            end
        end
        local season = self:GetActiveSeason()
        if season then
            run.seasonKey = season.seasonKey
            run.seasonName = season.seasonName
        end
    elseif self.GetRuntimeSeasonDescriptor then
        local season = self:GetRuntimeSeasonDescriptor()
        if season then
            run.seasonKey = season.seasonKey
            run.seasonName = season.seasonName
        end
    end

    if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
        local level, affixes = C_ChallengeMode.GetActiveKeystoneInfo()
        run.keyLevel = level or 0
        if type(affixes) == "table" then run.affixes = affixes end
    end

    if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and run.dungeonID ~= 0 then
        local name, _, timeLimit = C_ChallengeMode.GetMapUIInfo(run.dungeonID)
        run.dungeonName = name or ""
        run.timeLimit   = timeLimit or 0
    end

    local name, realm = UnitName("player")
    run.playerName  = name  or ""
    run.playerRealm = realm or ""

    local _, class = UnitClass("player")
    run.playerClass = class or ""

    -- FIX ROLE-1 + ROLE-2: Detección correcta de rol y spec
    local role, specName, specID = GetPlayerRoleAndSpec()
    run.playerRole   = role or "DAMAGER"
    run.playerSpec   = specName or ""
    run.playerSpecID = specID or 0

    -- FIX RACE-1: Si spec APIs retornaron nil (loading screen), reintentar en 2s
    if not specID or specID == 0 then
        if C_Timer and C_Timer.After then
            C_Timer.After(2.0, function()
                local curRun = _G.MitzuMPlusCurrentRun
                if curRun and (not curRun.playerSpecID or curRun.playerSpecID == 0) then
                    local r2, s2, id2 = GetPlayerRoleAndSpec()
                    if id2 and id2 > 0 then
                        curRun.playerRole   = r2 or curRun.playerRole
                        curRun.playerSpec   = s2 or curRun.playerSpec
                        curRun.playerSpecID = id2
                        MitzuMPlus._currentRunRole = curRun.playerRole
                    end
                end
            end)
        end
    end

    -- FIX API-4: Item level
    local overallAvg, equippedAvg = 0, 0
    if C_PaperDollInfo and C_PaperDollInfo.GetAverageItemLevels then
        overallAvg, equippedAvg = C_PaperDollInfo.GetAverageItemLevels()
    elseif GetAverageItemLevel then
        overallAvg, equippedAvg = GetAverageItemLevel()
    end
    run.playerIlvl = math.floor(equippedAvg or overallAvg or 0)

    -- Puntaje Mítico+ del jugador (Blizzard API)
    if C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
        local ok, summary = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, "player")
        if ok and type(summary) == "table" then
            run.playerMythicRating = tonumber(summary.currentSeasonScore) or 0
        end
    end

    local slotCount = (MitzuMPlus.Constants and MitzuMPlus.Constants.SLOT_COUNT) or 19
    for slotID = 1, slotCount do
        run.equippedItems[slotID] = GetInventoryItemLink("player", slotID)
    end

    run.startTime = Now()

    -- ── Capturar miembros del grupo ──────────────────────────────────────────
    run.group = {}
    local isRaid = IsInRaid and IsInRaid()
    local groupSize = GetNumGroupMembers and GetNumGroupMembers() or 0
    local prefix    = isRaid and "raid" or "party"
    local maxIter   = isRaid and math.min(groupSize, 40) or math.min(groupSize, 4)

    local function CaptureUnit(unit)
        if not UnitExists(unit) then return end
        local _, cls = UnitClass(unit)
        local unitRole = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or "NONE"
        if unitRole == "NONE" or unitRole == "" then unitRole = "DAMAGER" end
        local unitName, unitRealm = UnitName(unit)
        unitName  = unitName  or ""
        unitRealm = unitRealm or ""
        -- Para el propio jugador, UnitName("player") no devuelve realm; lo tomamos
        -- de GetRealmName() cuando sea necesario (mismo reino que el jugador).
        if (unitRealm == "" or unitRealm == nil) and GetRealmName then
            unitRealm = GetRealmName() or ""
        end
        local isPlayer = UnitIsUnit and UnitIsUnit(unit, "player")
        local memberSpec = isPlayer and (run.playerSpec or "") or ""
        local memberSpecID = isPlayer and (run.playerSpecID or 0) or 0
        local memberRating = GetUnitMythicRating(unit, unitName, unitRealm)
        table.insert(run.group, {
            class  = cls or "",
            role   = unitRole,
            name   = unitName,
            realm  = unitRealm,
            spec   = memberSpec,
            specID = memberSpecID,
            mythicRating = memberRating,
        })
    end
    CaptureUnit("player")
    for i = 1, maxIter do
        local unit = prefix .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            CaptureUnit(unit)
        end
    end

    -- Enriquecer spec/specID de los compañeros vía NotifyInspect (rate-limited).
    -- Se ejecuta de forma asíncrona: el resultado se escribe directamente en
    -- run.group[i].spec / specID / role conforme llegan los INSPECT_READY.
    -- Si algún miembro está fuera de rango o no es inspeccionable, se salta.
    if self.InspectQueue and self.InspectQueue.StartForRun then
        pcall(function() self.InspectQueue:StartForRun(run) end)
    end

    -- ── LootTracker: items que caen a cada miembro (CHAT_MSG_LOOT) ──────
    if self.LootTracker then
        self.LootTracker:Start()
    end

    -- BUG FIX (verify reporte: enemyForcesFinalPct=0, enemyForcesTotal=0):
    -- Antes KeystoneTracker:Start sólo se llamaba desde UI_Overlay_v2 cuando
    -- el overlay estaba habilitado. Si el usuario desactiva el overlay, el
    -- tracker nunca se activa (_active=false) y Update() retorna temprano,
    -- dejando enemy forces sin capturar. Ahora lo arrancamos aquí siempre.
    if self.KeystoneTracker and self.KeystoneTracker.Start then
        pcall(self.KeystoneTracker.Start, self.KeystoneTracker, run)
    end
    if self.RouteAdvisor and self.RouteAdvisor.Start then
        pcall(self.RouteAdvisor.Start, self.RouteAdvisor, run)
    end

    self._currentRunRole = run.playerRole

    -- ── ACTIVAR TRACKING ────────────────────────────────────────────────────
    -- BUG FIX (ADDON_ACTION_FORBIDDEN): antes hacíamos self:RegisterEvent
    -- vía AceEvent-3.0 aquí, lo que disparaba taint con HandyNotes. Ahora
    -- los eventos ya están registrados en _combatFrame (frame privado) desde
    -- el arranque; solo activamos el flag de dispatch.
    self._trackingActive = true
    -- Inicializar contador de poll periódico (C_DamageMeter)
    if IS_MIDNIGHT then
        self:RegisterMidnightCombatTracking()
    end

    -- v5.4.2 (BUG A2): la sesion Overall de C_DamageMeter es acumulada, no el
    -- segmento de la key. Guardamos aqui el valor de partida de cada fuente
    -- (estamos fuera de combate, asi que los campos son legibles) para poder
    -- restar despues y que las stats de la run sean SOLO de la run.
    if self.CaptureCombatBaseline then
        pcall(self.CaptureCombatBaseline, self, run)
    end

    _G.MitzuMPlusCurrentRun = run

    -- v5.4.2: ShowOverlay arranca el ticker externo del Coach. Ya NO hace falta
    -- acertar con el instante exacto: si IsChallengeModeActive() todavia es
    -- false (cuenta atras), el ticker sigue sondeando y el overlay aparece solo
    -- en cuanto la key arranca de verdad. Antes, ese unico intento a +0.20s
    -- podia caer en la vista de PRUEBA y quedarse ahi toda la key.
    if self.ShowOverlay then
        self:ShowOverlay()
    end
    -- Reset per-run diagnostic flags
    self._meterNoSessionLogged = nil
    self._meterFirstPollLogged = nil
    self._meterValuesLogged = nil
    self._meterNoMatchLogged = nil
    self._meterEventLogged = nil
    self._meterExplored = nil
    self._pendingMeterSources = nil
    self._lastMeterExploreTime = nil
    self._meterSingleArgLogged = nil

    -- ── DIAGNOSTIC LOG: run start context ────────────────────────────────
    if self.ErrorLogger and self.ErrorLogger.LogEvent then
        -- Enumerate C_DamageMeter keys to discover available methods
        local meterKeys = "N/A"
        if C_DamageMeter and type(C_DamageMeter) == "table" then
            local keys = {}
            for k, v in pairs(C_DamageMeter) do
                keys[#keys + 1] = tostring(k) .. "=" .. type(v)
            end
            table.sort(keys)
            meterKeys = #keys > 0 and table.concat(keys, ", ") or "(empty table)"
        end

        self.ErrorLogger:LogEvent("RUN_START", "M+ iniciada", {
            dungeon     = run.dungeonName or "?",
            keyLevel    = run.keyLevel or 0,
            role        = run.playerRole or "?",
            spec        = run.playerSpec or "?",
            isMidnight  = IS_MIDNIGHT,
            hasMeter    = (C_DamageMeter ~= nil),
            hasGetParty = (C_DamageMeter and C_DamageMeter.GetPartyData ~= nil) or false,
            hasGetSID   = (C_DamageMeter and C_DamageMeter.GetCurrentSessionID ~= nil) or false,
            dataSource  = run.dataSource or "?",
            groupSize   = #(run.group or {}),
            meterKeys   = meterKeys,
        })
    end

    if self.EventBus then
        self.EventBus:Emit("RUN_STARTED", run)
    end

    if self.Print then
        self:Print(string.format(
            "|cFF21de66M+ Iniciada:|r %s +%d | Rol: %s (%s) | Fuente: %s",
            run.dungeonName, run.keyLevel,
            run.playerRole, run.playerSpec,
            run.dataSource))
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- MIDNIGHT 12.0: TRACKING VÍA C_DamageMeter + UNIT_COMBAT
-- ─────────────────────────────────────────────────────────────────────────────
-- En Midnight, CLEU no existe para addons. Usamos:
--   1. C_DamageMeter API para obtener totales de daño/healing al final
--   2. UNIT_COMBAT para tracking en tiempo real (limitado a eventos del jugador)
--   3. UNIT_HEALTH para detectar muertes propias
--   4. SPELL_UPDATE_COOLDOWN + aura events para kicks/dispels/defensivos
-- ─────────────────────────────────────────────────────────────────────────────

function MitzuMPlus:RegisterMidnightCombatTracking()
    -- BUG FIX (ADDON_ACTION_FORBIDDEN): los eventos UNIT_COMBAT, UNIT_HEALTH,
    -- DAMAGE_METER_COMBAT_SESSION_UPDATED y UNIT_SPELLCAST_SUCCEEDED YA están
    -- registrados en _combatFrame. Aquí solo activamos el gate.
    self._trackingActive = true

    -- Polling periódico: C_DamageMeter no emite eventos en cada hit,
    -- así que polleamos cada 5 segundos para mantener los trackers actualizados.
    -- Check for REAL Midnight API (GetCombatSessionSourceFromType) or legacy (GetPartyData)
    if C_DamageMeter
        and (C_DamageMeter.GetCombatSessionSourceFromType or C_DamageMeter.GetPartyData)
        and C_Timer and C_Timer.NewTicker then
        self._meterPollTicker = C_Timer.NewTicker(5.0, function()
            local run = _G.MitzuMPlusCurrentRun
            if run then
                MitzuMPlus:PollDamageMeterData(run)
            end
        end)
    end
end

function MitzuMPlus:UnregisterMidnightCombatTracking()
    -- BUG FIX (ADDON_ACTION_FORBIDDEN): no llamamos UnregisterEvent porque
    -- nuestro _combatFrame ya gatea via _trackingActive. Solo paramos el
    -- polling periódico de C_DamageMeter.
    if self._meterPollTicker then
        self._meterPollTicker:Cancel()
        self._meterPollTicker = nil
    end
end

-- ── Interrupt Spell IDs (para detectar kicks vía UNIT_SPELLCAST_SUCCEEDED) ───
local INTERRUPT_SPELL_IDS = {
    [47528]  = true,  -- Mind Freeze (DK)
    [183752] = true,  -- Disrupt (DH)
    [106839] = true,  -- Skull Bash (Druid)
    [147362] = true,  -- Counter Shot (Hunter)
    [187707] = true,  -- Muzzle (Hunter)
    [2139]   = true,  -- Counterspell (Mage)
    [116705] = true,  -- Spear Hand Strike (Monk)
    [96231]  = true,  -- Rebuke (Paladin)
    [15487]  = true,  -- Silence (Priest)
    [1766]   = true,  -- Kick (Rogue)
    [57994]  = true,  -- Wind Shear (Shaman)
    [19647]  = true,  -- Spell Lock (Warlock)
    [6552]   = true,  -- Pummel (Warrior)
    [351338] = true,  -- Quell (Evoker)
}

-- Handler: detectar kicks cuando el jugador castea un spell de interrupt.
-- En Midnight (IS_MIDNIGHT=true) CLEU no está disponible, así que contamos
-- kicks aquí vía UNIT_SPELLCAST_SUCCEEDED. En pre-Midnight, los kicks se
-- cuentan vía SPELL_INTERRUPT (CLEU) y este handler no hace nada.
function MitzuMPlus:OnSpellcastSucceeded(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    local run = _G.MitzuMPlusCurrentRun
    if not run then return end

    -- Un secreto no se convierte ni se compara. Este handler es solo para
    -- casts del jugador, pero comparte la misma politica fail-closed.
    if type(_issecretvalue) ~= "function" then return end
    local okSecret, isSecret = pcall(_issecretvalue, spellID)
    if not okSecret or isSecret ~= false then return end
    if spellID == nil then return end
    spellID = tonumber(spellID) -- ya demostrado no secreto
    if not spellID then return end

    if IS_MIDNIGHT and INTERRUPT_SPELL_IDS[spellID] then
        run.stats.kicks      = (run.stats.kicks      or 0) + 1
        run.stats.kicksGroup = (run.stats.kicksGroup or 0) + 1
        run.timeline[#run.timeline + 1] = { timestamp = Now(), type = "kick", note = "Interrupción" }
    end
end

-- UNIT_COMBAT: solo conserva daño recibido del jugador (WOUND).
-- No se usa HEAL como proxy porque en Midnight no identifica de forma fiable
-- quién originó la sanación y podría fabricar estadísticas incorrectas.
function MitzuMPlus:OnUnitCombat(event, unitTarget, action, descriptor, damage, damageType)
    local run = _G.MitzuMPlusCurrentRun
    if not run or unitTarget ~= "player" then return end

    if _issecretvalue then
        if action ~= nil and _issecretvalue(action) then
            local ok, plain = pcall(string.format, "%s", action)
            action = (ok and plain) or nil
        end
        if damage ~= nil and _issecretvalue(damage) then
            local ok, plain = pcall(tonumber, damage)
            damage = (ok and plain) or 0
        end
    end

    damage = tonumber(damage) or 0
    if action == "WOUND" and damage > 0 then
        run.stats.damageTaken = (run.stats.damageTaken or 0) + damage
    end
end

-- Detectar muerte del jugador
-- FIX BUG-TAINT-1: En Midnight 12.0, UnitHealth() retorna un "secret number"
-- que no puede compararse con operadores estándar (==, >, <). Usar
-- UnitIsDeadOrGhost() en su lugar, que retorna un booleano limpio.
function MitzuMPlus:OnUnitHealth(event, unit)
    if unit ~= "player" then return end
    local run = _G.MitzuMPlusCurrentRun
    if not run then return end

    local isDead = UnitIsDeadOrGhost("player")
    if isDead and not self._playerDeadFlag then
        self._playerDeadFlag = true
        run.stats.deaths = (run.stats.deaths or 0) + 1
        -- BUG FIX (verify reporte: timestamps mezclados epoch/GetTime):
        -- unificamos a epoch con Now().
        run.timeline[#run.timeline + 1] = {
            timestamp = Now(), type = "death", note = "Muerte"
        }
        if self.EventBus then
            self.EventBus:Emit("PLAYER_DIED", GetTime())
        end
    elseif not isDead then
        self._playerDeadFlag = false
    end
end

-- C_DamageMeter: obtener datos oficiales del meter integrado de Blizzard
-- Real API (Midnight 12.0.5): session-based model
--   IsDamageMeterAvailable() → bool
--   GetAvailableCombatSessions() → table of session objects
--   GetCombatSessionFromType(sessionType) → session data
--   GetCombatSessionSourceFromType(sessionType) → per-player breakdown
--   GetCombatSessionFromID(sessionID) → session data
--   GetCombatSessionSourceFromID(sessionID) → per-player breakdown
--   GetSessionDurationSeconds(sessionType) → number
--   ResetAllCombatSessions() → void

function MitzuMPlus:OnDamageMeterUpdate(event, ...)
    local run = _G.MitzuMPlusCurrentRun
    if not run then return end
    if not C_DamageMeter then return end

    local _EL = self.ErrorLogger
    local function diag(msg, data)
        if _EL and _EL.LogEvent then _EL:LogEvent("METER_EVENT", msg, data) end
    end

    -- Log event firing (once per run)
    if not self._meterEventLogged then
        self._meterEventLogged = true
        local nArgs = select("#", ...)
        local argDump = ""
        if nArgs > 0 then
            local parts = {}
            for i = 1, math.min(nArgs, 5) do
                local a = select(i, ...)
                parts[#parts + 1] = tostring(a) .. "(" .. type(a) .. ")"
            end
            argDump = table.concat(parts, ", ")
        end
        diag("Event fired", { nArgs = nArgs, args = argDump ~= "" and argDump or "none" })
    end

    -- Auto-explore: dump full API response to SavedVariables
    -- Rate-limit to once per 30s (not once-per-run — first call may be too early)
    local now = GetTime()
    if not self._lastMeterExploreTime or (now - self._lastMeterExploreTime) > 30 then
        self._lastMeterExploreTime = now
        self:_ExploreDamageMeterAPI(run)
    end

    -- Poll actual data using the real API (TWO-arg model)
    self:PollDamageMeterDataV2(run)
end

-- Full API exploration — dumps to db.global.meterExploreData for diagnostic review
-- KEY INSIGHT: GetCombatSessionSourceFromType likely takes TWO args:
--   (damageMeterType, sessionType) where:
--     damageMeterType = Enum.DamageMeterType (0=DamageDone..10=EnemyDamageTaken)
--     sessionType     = Enum.DamageMeterSessionType (0=Overall, 1=Current, 2=Expired)
function MitzuMPlus:_ExploreDamageMeterAPI(run)
    local cdm = C_DamageMeter
    if not cdm then return end

    local _isSecret = rawget(_G, "issecretvalue")
    local function safe(v, depth)
        depth = depth or 0
        if v == nil then return nil end
        if _isSecret and _isSecret(v) then return "<SECRET>" end
        if type(v) == "table" then
            if depth > 3 then return "<DEEP>" end
            local t = {}
            local n = 0
            for k, val in pairs(v) do
                n = n + 1
                if n > 50 then t["_TRUNCATED"] = true; break end
                t[tostring(k)] = safe(val, depth + 1)
            end
            return t
        end
        return v
    end

    local explore = { timestamp = time(), dungeon = run.dungeonName or "?", version = 2 }

    -- 1) GetAvailableCombatSessions
    if cdm.GetAvailableCombatSessions then
        local ok, res = pcall(cdm.GetAvailableCombatSessions)
        explore.sessions = ok and safe(res) or { error = tostring(res) }
    end

    -- 2) GetSessionDurationSeconds with sessionType 0-2
    explore.durationBySessionType = {}
    if cdm.GetSessionDurationSeconds then
        for st = 0, 2 do
            local ok, res = pcall(cdm.GetSessionDurationSeconds, st)
            if ok and res ~= nil then
                explore.durationBySessionType[st] = res
            end
        end
    end

    -- 3) TWO-ARG exploration: GetCombatSessionSourceFromType(damageMeterType, sessionType)
    --    damageMeterType: 0-10, sessionType: 0-2
    explore.source2arg = {}
    local source2argCount = 0
    if cdm.GetCombatSessionSourceFromType then
        for dmgType = 0, 10 do
            for sessType = 0, 2 do
                local ok, res = pcall(cdm.GetCombatSessionSourceFromType, dmgType, sessType)
                if ok and res ~= nil then
                    local key = "t" .. dmgType .. "_s" .. sessType
                    explore.source2arg[key] = safe(res)
                    source2argCount = source2argCount + 1
                end
            end
        end
    end

    -- 4) TWO-ARG: GetCombatSessionFromType(damageMeterType, sessionType)
    explore.session2arg = {}
    local session2argCount = 0
    if cdm.GetCombatSessionFromType then
        for dmgType = 0, 10 do
            for sessType = 0, 2 do
                local ok, res = pcall(cdm.GetCombatSessionFromType, dmgType, sessType)
                if ok and res ~= nil then
                    local key = "t" .. dmgType .. "_s" .. sessType
                    explore.session2arg[key] = safe(res)
                    session2argCount = session2argCount + 1
                end
            end
        end
    end

    -- 5) SINGLE-ARG fallback: GetCombatSessionSourceFromType(type) with 0-10
    explore.source1arg = {}
    local source1argCount = 0
    if cdm.GetCombatSessionSourceFromType then
        for t = 0, 10 do
            local ok, res = pcall(cdm.GetCombatSessionSourceFromType, t)
            if ok and res ~= nil then
                explore.source1arg[t] = safe(res)
                source1argCount = source1argCount + 1
            end
        end
    end

    -- 6) SINGLE-ARG fallback: GetCombatSessionFromType(type) with 0-10
    explore.session1arg = {}
    if cdm.GetCombatSessionFromType then
        for t = 0, 10 do
            local ok, res = pcall(cdm.GetCombatSessionFromType, t)
            if ok and res ~= nil then
                explore.session1arg[t] = safe(res)
            end
        end
    end

    -- 7) ID-BASED exploration (the correct API path!)
    --    GetCombatSessionFromID(sessionID, damageMeterType) → session info
    --    GetCombatSessionSourceFromID(sessionID, damageMeterType) → per-player sources
    --    Error messages confirmed: both need (sessionID: number, type: number)
    local sessionFromIDCount = 0
    local sourceFromIDCount = 0
    if cdm.GetAvailableCombatSessions then
        local ok, sessions = pcall(cdm.GetAvailableCombatSessions)
        if ok and type(sessions) == "table" and #sessions > 0 then
            explore.sessionFromID = {}
            explore.sourceFromID = {}
            -- Key dmgTypes: 0=DamageDone, 2=HealingDone, 5=Interrupts, 6=Dispels, 7=DamageTaken
            local probeDmgTypes = { 0, 2, 5, 6, 7 }
            -- Probe first 3 sessions to limit overhead
            local maxSessions = math.min(#sessions, 3)
            for i = 1, maxSessions do
                local s = sessions[i]
                local sid = type(s) == "table" and (s.sessionID or s.id or s.sessionId) or s
                if sid and type(sid) == "number" then
                    for _, dmgType in ipairs(probeDmgTypes) do
                        local key = "sid" .. sid .. "_t" .. dmgType
                        -- GetCombatSessionFromID(sessionID, damageMeterType)
                        if cdm.GetCombatSessionFromID then
                            local ok2, r2 = pcall(cdm.GetCombatSessionFromID, sid, dmgType)
                            if ok2 and r2 ~= nil then
                                explore.sessionFromID[key] = safe(r2)
                                sessionFromIDCount = sessionFromIDCount + 1
                            end
                        end
                        -- GetCombatSessionSourceFromID(sessionID, damageMeterType)
                        if cdm.GetCombatSessionSourceFromID then
                            local ok3, r3 = pcall(cdm.GetCombatSessionSourceFromID, sid, dmgType)
                            if ok3 and r3 ~= nil then
                                explore.sourceFromID[key] = safe(r3)
                                sourceFromIDCount = sourceFromIDCount + 1
                            end
                        end
                    end
                end
            end
        end
    end

    -- 8) Scan for Enum.DamageMeter*
    if _G.Enum then
        for enumName, enumVal in pairs(_G.Enum) do
            if type(enumName) == "string" and enumName:find("DamageMeter") then
                explore["Enum_" .. enumName] = safe(enumVal)
            end
        end
    end

    -- Save to db.global for diagnostic review
    if self.db and self.db.global then
        self.db.global.meterExploreData = explore
    end

    -- Log summary
    local _EL = self.ErrorLogger
    if _EL and _EL.LogEvent then
        local durParts = {}
        for st, d in pairs(explore.durationBySessionType) do
            durParts[#durParts + 1] = "s" .. st .. "=" .. tostring(d) .. "s"
        end
        _EL:LogEvent("METER_EXPLORE", "Auto-explore during M+", {
            sessionsAvailable = type(explore.sessions) == "table" and #explore.sessions or 0,
            source2argHits = source2argCount,
            session2argHits = session2argCount,
            source1argHits = source1argCount,
            sessionFromIDHits = sessionFromIDCount,
            sourceFromIDHits = sourceFromIDCount,
            durations = #durParts > 0 and table.concat(durParts, ", ") or "none",
        })
    end
end

-- New V2 polling: ID-BASED API
-- 1. GetAvailableCombatSessions() → [{sessionID, name, durationSeconds}, ...]
-- 2. GetCombatSessionSourceFromID(sessionID, damageMeterType) → per-player sources
-- DamageMeterType: DamageDone=0, HealingDone=2, Interrupts=5, Dispels=6, DamageTaken=7
local DMT_DAMAGE_DONE    = 0
local DMT_HEALING_DONE   = 2
local DMT_INTERRUPTS     = 5
local DMT_DISPELS        = 6
local DMT_DAMAGE_TAKEN   = 7

-- Value field names the API might use per source entry
local VALUE_FIELDS = { "amount", "value", "total", "totalAmount",
    "damageDone", "damage", "damageTotal", "healingDone", "healing",
    "healTotal", "damageTaken", "interrupts", "dispels" }
-- Identity field names for matching players
local GUID_FIELDS_V2 = { "guid", "unitGUID", "GUID", "playerGUID", "unitToken" }
local NAME_FIELDS_V2 = { "name", "playerName", "unitName", "sourceName" }

function MitzuMPlus:PollDamageMeterDataV2(run)
    local cdm = C_DamageMeter
    if not cdm then return end

    local _isSecret = rawget(_G, "issecretvalue")
    local function safeNum(v)
        if v == nil then return 0 end
        if _isSecret and _isSecret(v) then return 0 end
        return tonumber(v) or 0
    end
    local function pickField(tbl, fields)
        for _, f in ipairs(fields) do
            local ok2, v = pcall(function() return tbl[f] end)
            if ok2 and v ~= nil then
                if _isSecret and _isSecret(v) then return nil end
                return v
            end
        end
        return nil
    end
    local function pickValue(tbl)
        for _, f in ipairs(VALUE_FIELDS) do
            local ok2, v = pcall(function() return tbl[f] end)
            if ok2 and v ~= nil then
                if _isSecret and _isSecret(v) then return 0 end
                return tonumber(v) or 0
            end
        end
        return 0
    end

    local playerGUID = UnitGUID("player")
    local playerName = UnitName("player")

    -- ── PRIMARY PATH: ID-based ──────────────────────────────────────────
    -- GetAvailableCombatSessions() → session list
    -- GetCombatSessionSourceFromID(sessionID, damageMeterType) → per-player data
    local sessions = nil
    if cdm.GetAvailableCombatSessions then
        local ok, res = pcall(cdm.GetAvailableCombatSessions)
        if ok and type(res) == "table" and #res > 0 then
            sessions = res
        end
    end

    -- Accumulate per-player totals across ALL sessions for each stat type
    -- Key = GUID or name, Value = {guid, name, damage, healing, taken, kicks, dispels}
    local playerTotals = {}  -- keyed by GUID or name
    local anyData = false

    local function addSourceData(sessionID, dmgType, statField)
        if not cdm.GetCombatSessionSourceFromID then return end
        local ok, sources = pcall(cdm.GetCombatSessionSourceFromID, sessionID, dmgType)
        if not ok or type(sources) ~= "table" then return end

        for _, entry in ipairs(sources) do
            if type(entry) == "table" then
                local eGUID = pickField(entry, GUID_FIELDS_V2)
                local eName = pickField(entry, NAME_FIELDS_V2)
                local eVal  = pickValue(entry)
                local key   = eGUID or eName
                if key then
                    if not playerTotals[key] then
                        playerTotals[key] = { guid = eGUID, name = eName or "?",
                            damage = 0, healing = 0, taken = 0, kicks = 0, dispels = 0 }
                    end
                    playerTotals[key][statField] = (playerTotals[key][statField] or 0) + eVal
                    if eVal > 0 then anyData = true end
                end
            end
        end
    end

    if sessions then
        for _, s in ipairs(sessions) do
            local sid = type(s) == "table" and (s.sessionID or s.id or s.sessionId) or s
            if sid and type(sid) == "number" then
                addSourceData(sid, DMT_DAMAGE_DONE,  "damage")
                addSourceData(sid, DMT_HEALING_DONE, "healing")
                addSourceData(sid, DMT_DAMAGE_TAKEN, "taken")
                addSourceData(sid, DMT_INTERRUPTS,   "kicks")
                addSourceData(sid, DMT_DISPELS,      "dispels")
            end
        end
    end

    -- ── FALLBACK: Type-based (in case SourceFromID returns nothing) ─────
    if not anyData and cdm.GetCombatSessionSourceFromType then
        for _, sessType in ipairs({1, 0, 2}) do  -- Current, Overall, Expired
            local function queryFallback(dmgType, statField)
                local ok, sources = pcall(cdm.GetCombatSessionSourceFromType, dmgType, sessType)
                if not ok or type(sources) ~= "table" then return end
                for _, entry in ipairs(sources) do
                    if type(entry) == "table" then
                        local eGUID = pickField(entry, GUID_FIELDS_V2)
                        local eName = pickField(entry, NAME_FIELDS_V2)
                        local eVal  = pickValue(entry)
                        local key   = eGUID or eName
                        if key and eVal > 0 then
                            if not playerTotals[key] then
                                playerTotals[key] = { guid = eGUID, name = eName or "?",
                                    damage = 0, healing = 0, taken = 0, kicks = 0, dispels = 0 }
                            end
                            if eVal > (playerTotals[key][statField] or 0) then
                                playerTotals[key][statField] = eVal
                            end
                            anyData = true
                        end
                    end
                end
            end
            queryFallback(DMT_DAMAGE_DONE,  "damage")
            queryFallback(DMT_HEALING_DONE, "healing")
            queryFallback(DMT_DAMAGE_TAKEN, "taken")
            queryFallback(DMT_INTERRUPTS,   "kicks")
            queryFallback(DMT_DISPELS,      "dispels")
            if anyData then break end  -- stop at first sessType that has data
        end
    end

    -- ── Extract player stats from accumulated totals ────────────────────
    local dmgVal, healVal, takenVal, kicksVal, dispelsVal = 0, 0, 0, 0, 0
    for key, p in pairs(playerTotals) do
        local isPlayer = false
        if p.guid and p.guid == playerGUID then isPlayer = true
        elseif p.name and p.name == playerName then isPlayer = true end
        if isPlayer then
            dmgVal     = p.damage  or 0
            healVal    = p.healing or 0
            takenVal   = p.taken   or 0
            kicksVal   = p.kicks   or 0
            dispelsVal = p.dispels or 0
            break
        end
    end

    -- Update run stats (only increase, never decrease)
    if anyData then
        if dmgVal > 0 then run._dmgSource = "C_DamageMeter" end
        if healVal > 0 then run._healSource = "C_DamageMeter" end

        if dmgVal > (run.stats.damageTotal or 0) then
            run.stats.damageTotal = dmgVal
        end
        if healVal > (run.stats.healingTotal or 0) then
            run.stats.healingTotal = healVal
        end
        if takenVal > (run.stats.damageTaken or 0) then
            run.stats.damageTaken = takenVal
        end
        if kicksVal > (run.stats.kicks or 0) then
            run.stats.kicks = kicksVal
        end
        if dispelsVal > (run.stats.dispels or 0) then
            run.stats.dispels = dispelsVal
        end

        -- Log first successful poll
        if not self._meterValuesLogged and self.ErrorLogger and self.ErrorLogger.LogEvent then
            self._meterValuesLogged = true
            self.ErrorLogger:LogEvent("METER", "V2 poll success (ID-based)", {
                dmg = dmgVal,
                heal = healVal,
                taken = takenVal,
                kicks = kicksVal,
                dispels = dispelsVal,
                sessions = sessions and #sessions or 0,
                source = "C_DamageMeter",
            })
        end
    else
        -- Log first poll with no data (once per run)
        if not self._meterNoMatchLogged and self.ErrorLogger and self.ErrorLogger.LogEvent then
            self._meterNoMatchLogged = true
            self.ErrorLogger:LogEvent("METER", "V2 poll: no data", {
                playerGUID = playerGUID or "nil",
                playerName = playerName or "nil",
                sessions = sessions and #sessions or 0,
                hasSourceFromID = cdm.GetCombatSessionSourceFromID and true or false,
                hasSourceFromType = cdm.GetCombatSessionSourceFromType and true or false,
            })
        end
    end
end

-- BUG FIX (verify reporte Run #10: damageTotal=0, healingTotal=0):
-- Antes matcheábamos al jugador estrictamente con `memberData.guid == playerGUID`.
-- En Midnight, C_DamageMeter.GetPartyData puede usar otros nombres (GUID,
-- playerGUID, unitToken). Ahora:
--   1) probamos múltiples nombres para GUID
--   2) fallback: match por UnitName("player")
--   3) multi-field para damageDone/healingDone/interrupts/dispels/damageTaken
-- Además, la PRIMERA vez que matcheamos hacemos un dump raw a SavedVariables
-- para diagnóstico (se limpia tras /reload).
local POLL_GUID_FIELDS    = { "guid", "unitGUID", "GUID", "playerGUID", "unitToken", "unit" }
local POLL_NAME_FIELDS    = { "name", "playerName", "unitName" }
local POLL_DMG_FIELDS     = { "damageDone", "damage", "damageTotal", "totalDamage" }
local POLL_HEAL_FIELDS    = { "healingDone", "healing", "healTotal", "totalHealing" }
local POLL_TAKEN_FIELDS   = { "damageTaken", "damageReceived", "takenDamage" }
local POLL_KICKS_FIELDS   = { "interrupts", "kicks", "interruptCount" }
local POLL_DISPELS_FIELDS = { "dispels", "dispelCount" }

-- FIX BUG-SECRET-2: C_DamageMeter fields may be Secret Values in Midnight 12.0.5.
-- issecretvalue() check prevents crashes when reading opaque wrapped values.
-- NOTE: _issecretvalue is defined at module scope (line ~32) for use across all handlers.

local function _pollPickNum(tbl, fields)
    for _, f in ipairs(fields) do
        local ok, v = pcall(function() return tbl[f] end)
        if ok and v ~= nil then
            if _issecretvalue and _issecretvalue(v) then
                -- Secret value: can't use as number, skip
            else
                local n = tonumber(v)
                if n and n > 0 then return n end
            end
        end
    end
    return 0
end

local function _pollPickStr(tbl, fields)
    for _, f in ipairs(fields) do
        local ok, v = pcall(function() return tbl[f] end)
        if ok and v ~= nil then
            if _issecretvalue and _issecretvalue(v) then
                -- Secret value: can't use as string, skip
            elseif type(v) == "string" and v ~= "" then
                return v
            end
        end
    end
    return nil
end

-- Dump un snapshot raw de partyData al SavedVariables para que el usuario
-- pueda mandarnos la estructura si nada matchea. Se hace UNA sola vez por
-- sesión del juego.
local function _dumpPartyDataOnce(partyData)
    if MitzuMPlus._partyDataDumped then return end
    MitzuMPlus._partyDataDumped = true
    local sv = _G.MitzuMPlusDB
    if not sv then return end
    sv._diag = sv._diag or {}
    sv._diag.partyDataDump = {
        timestamp = time(),
        sample = {}
    }
    -- Copia superficial de hasta 6 entries con todos sus campos
    -- FIX BUG-SECRET-2: guard against secret values when copying fields
    local count = 0
    for k, m in pairs(partyData) do
        if count >= 6 then break end
        if type(m) == "table" then
            local copy = {}
            for kk, vv in pairs(m) do
                local skip = false
                if _issecretvalue and _issecretvalue(vv) then
                    copy[kk] = "<secret>"
                    skip = true
                end
                if not skip and type(vv) ~= "table" and type(vv) ~= "function" then
                    copy[kk] = vv
                end
            end
            sv._diag.partyDataDump.sample[tostring(k)] = copy
            count = count + 1
        end
    end
end

-- Leer datos de C_DamageMeter y aplicarlos al run actual
-- Routes to V2 (session-based API) first, then legacy GetPartyData fallback
function MitzuMPlus:PollDamageMeterData(run)
    if not run then return end
    if not C_DamageMeter then return end

    -- PRIMARY: Use V2 session-based API (the REAL Midnight 12.0.5 API)
    if C_DamageMeter.GetCombatSessionSourceFromType then
        self:PollDamageMeterDataV2(run)
        return
    end

    -- LEGACY FALLBACK: GetPartyData path (never executes in Midnight)
    local _log = self.ErrorLogger and self.ErrorLogger.LogEvent
    local function diag(msg, data)
        if _log then self.ErrorLogger:LogEvent("METER", msg, data) end
    end

    if not C_DamageMeter.GetPartyData or not C_DamageMeter.GetCurrentSessionID then
        if not self._meterMissingLogged then
            diag("C_DamageMeter sin GetPartyData ni GetCombatSessionSourceFromType", {
                hasGetPartyData = C_DamageMeter.GetPartyData ~= nil,
                hasGetCurrentSessionID = C_DamageMeter.GetCurrentSessionID ~= nil,
                hasSourceFromType = C_DamageMeter.GetCombatSessionSourceFromType ~= nil,
            })
            self._meterMissingLogged = true
        end
        return
    end

    local sessionID
    local okSid, sidResult = pcall(C_DamageMeter.GetCurrentSessionID)
    if okSid then sessionID = sidResult end
    if not sessionID then
        -- Log once per run to avoid spam
        if not self._meterNoSessionLogged then
            diag("GetCurrentSessionID retornó nil", { pcallOk = okSid })
            self._meterNoSessionLogged = true
        end
        return
    end

    local playerGUID = UnitGUID("player")
    local playerName = UnitName("player")
    if not playerGUID then return end

    local ok, partyData = pcall(C_DamageMeter.GetPartyData, sessionID)
    if not ok then
        diag("GetPartyData pcall falló", { sessionID = tostring(sessionID), error = tostring(partyData) })
        return
    end
    if not partyData then
        diag("GetPartyData retornó nil", { sessionID = tostring(sessionID) })
        return
    end

    -- Count entries and check for secret values in the top-level structure
    local entryCount = 0
    local hasSecretKeys = false
    for k, v in pairs(partyData) do
        entryCount = entryCount + 1
        if _issecretvalue and type(k) ~= "number" and type(k) ~= "string" then
            hasSecretKeys = true
        end
    end

    -- Log first successful poll with structure info (once per run)
    if not self._meterFirstPollLogged then
        self._meterFirstPollLogged = true
        diag("GetPartyData OK", {
            sessionID = tostring(sessionID),
            entries = entryCount,
            hasSecretKeys = hasSecretKeys,
        })
    end

    _dumpPartyDataOnce(partyData)

    -- Buscar la entrada del jugador con matching robusto.
    local playerEntry
    local matchMethod = "none"
    for _, memberData in pairs(partyData) do
        if type(memberData) == "table" then
            local guid = _pollPickStr(memberData, POLL_GUID_FIELDS)
            if guid and guid == playerGUID then
                playerEntry = memberData
                matchMethod = "guid"
                break
            end
        end
    end
    -- Fallback: match por nombre
    if not playerEntry and playerName then
        for _, memberData in pairs(partyData) do
            if type(memberData) == "table" then
                local nm = _pollPickStr(memberData, POLL_NAME_FIELDS)
                if nm == playerName then
                    playerEntry = memberData
                    matchMethod = "name"
                    break
                end
            end
        end
    end
    -- Último fallback en Midnight: si sólo hay 1 entry, asumir que es el jugador
    if not playerEntry then
        local count, firstEntry = 0, nil
        for _, memberData in pairs(partyData) do
            if type(memberData) == "table" then
                count = count + 1
                firstEntry = firstEntry or memberData
            end
        end
        if count == 1 then
            playerEntry = firstEntry
            matchMethod = "single_entry"
        end
    end
    if not playerEntry then
        -- Log why matching failed (once per run)
        if not self._meterNoMatchLogged then
            self._meterNoMatchLogged = true
            diag("No se encontró entrada del jugador en partyData", {
                entries = entryCount,
                playerGUID = playerGUID,
                playerName = playerName or "nil",
            })
        end
        return
    end

    -- Ahora extraer campos con múltiples nombres posibles.
    local dmg   = _pollPickNum(playerEntry, POLL_DMG_FIELDS)
    local heal  = _pollPickNum(playerEntry, POLL_HEAL_FIELDS)
    local taken = _pollPickNum(playerEntry, POLL_TAKEN_FIELDS)
    local kicks = _pollPickNum(playerEntry, POLL_KICKS_FIELDS)
    local disp  = _pollPickNum(playerEntry, POLL_DISPELS_FIELDS)

    -- Log extracted values (once per run, or when values change significantly)
    if not self._meterValuesLogged then
        self._meterValuesLogged = true
        diag("Datos extraídos del meter", {
            matchMethod = matchMethod,
            dmg = dmg, heal = heal, taken = taken,
            kicks = kicks, dispels = disp,
        })
    end

    -- Track data source for healing: C_DamageMeter vs UNIT_COMBAT fallback
    if heal > 0 then
        run._healSource = "C_DamageMeter"
    end

    if dmg > 0 then
        run.stats.damageTotal = dmg
        run._dmgSource = "C_DamageMeter"
        self._lastMeterDamage = dmg
    end
    if heal  > 0 then run.stats.healingTotal  = heal  end
    if taken > 0 then run.stats.damageTaken   = taken end
    if kicks > 0 then run.stats.kicks   = kicks end
    if disp  > 0 then run.stats.dispels = disp  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- CHALLENGE MODE — COMPLETADO
-- ─────────────────────────────────────────────────────────────────────────────

-- v5.4.2 (BUG A4): cierre unico del ciclo de vida de una run.
-- Antes ni OnChallengeCompleted ni OnChallengeReset apagaban el Coach,
-- reseteaban KeystoneTracker ni paraban RouteAdvisor. El overlay solo
-- desaparecia como efecto colateral de que Refresh() viera la run a nil, y
-- KeystoneTracker._active se quedaba en true indefinidamente entre runs.
-- IMPORTANTE: llamar SIEMPRE despues de haber capturado Enemy Forces.
function MitzuMPlus:_TeardownRun(reason)
    if self.HideOverlay then pcall(self.HideOverlay, self) end
    if self.RouteAdvisor and self.RouteAdvisor.Stop then
        pcall(self.RouteAdvisor.Stop, self.RouteAdvisor)
    end
    if self.KeystoneTracker and self.KeystoneTracker.Reset then
        pcall(self.KeystoneTracker.Reset, self.KeystoneTracker)
    end
    -- v5.4.9: aqui se limpiaba _lastNotifyKey/_lastNotifyAt "para que el aviso
    -- pueda volver a salir en la proxima key". Era justo lo que permitia que,
    -- nada mas terminar la llave, cualquier disparo posterior sacara el popup
    -- otra vez. No se toca: la clave lleva la mazmorra y la ventana es de 5
    -- minutos, asi que la siguiente llave avisa sola sin necesidad de resetear.
    self._trackingActive = false
    -- La linea base de C_DamageMeter NO se limpia tras completar: el resumen guardado
    -- repinta a 0.75/2.25/5.25 s y los reintentos de poll a 0.5/2/5 s siguen
    -- necesitandola para acotar los totales a la key.
    if reason ~= "completed" and self.ClearCombatBaseline then
        pcall(self.ClearCombatBaseline, self)
    end
    _G.MitzuMPlusCurrentRun = nil
    if self.EventBus then
        self.EventBus:Emit("RUN_TEARDOWN", reason)
    end
end

function MitzuMPlus:OnChallengeCompleted()
    local run = _G.MitzuMPlusCurrentRun
    if not run then return end

    -- FIX DEDUP-1: Protección contra runs duplicadas.
    -- Si ya procesamos un CHALLENGE_MODE_COMPLETED para esta startTime, ignorar.
    local runKey = tostring(run.dungeonID) .. "_" .. tostring(run.startTime)
    if self._lastCompletedRunKey == runKey then
        if self.Print then
            self:Print("|cFFFF9922Duplicado ignorado:|r Esta run ya fue registrada.")
        end
        return
    end
    self._lastCompletedRunKey = runKey

    local completionTime, inTime = 0, false
    local isPractice = false

    -- ═══════════════════════════════════════════════════════════════════════
    -- FIX COMPLETION-1 (CRÍTICO): GetCompletionInfo() retorna:
    --   mapChallengeModeID, level, time, onTime, keystoneUpgradeLevels, practiceRun, ...
    -- El código anterior capturaba solo 3 retornos (completionMs, onTime, isPractice)
    -- pensando que era (time, onTime, practice) — INCORRECTO desde 7.2.0.
    --
    -- En 12.0+ existe GetChallengeCompletionInfo() que retorna un struct.
    -- Usamos la nueva API si existe, con fallback a la antigua correctamente parseada.
    -- ═══════════════════════════════════════════════════════════════════════

    if C_ChallengeMode then
        -- Ruta 1: Nueva API de 12.0+ (GetChallengeCompletionInfo retorna struct)
        if C_ChallengeMode.GetChallengeCompletionInfo then
            local ok, info = pcall(C_ChallengeMode.GetChallengeCompletionInfo)
            if ok and info and type(info) == "table" then
                completionTime = math.floor((tonumber(info.time) or 0) / 1000)
                inTime = info.onTime and true or false
                isPractice = info.practiceRun and true or false
                run.keystoneUpgradeLevels = tonumber(info.keystoneUpgradeLevels) or 0
            end
        end

        -- Ruta 2: API clásica con retornos CORRECTOS (pre-12.0 o fallback)
        if completionTime == 0 and C_ChallengeMode.GetCompletionInfo then
            local ok, mapID, level, timeMs, onTime, keystoneUpgradeLevels, practiceRun =
                pcall(C_ChallengeMode.GetCompletionInfo)
            if ok then
                -- Verificar que timeMs es un número real (no Secret Value)
                local timeNum = tonumber(timeMs)
                if timeNum and timeNum > 0 then
                    completionTime = math.floor(timeNum / 1000)
                end
                -- onTime es el 4to retorno (boolean)
                if type(onTime) == "boolean" then
                    inTime = onTime
                elseif onTime and onTime ~= 0 then
                    -- Algunos clientes retornan 1/0 en vez de true/false
                    inTime = true
                end
                -- practiceRun es el 6to retorno
                if practiceRun == true then
                    isPractice = true
                end
                run.keystoneUpgradeLevels = tonumber(keystoneUpgradeLevels) or run.keystoneUpgradeLevels or 0
            end
        end

        -- Ruta 3: Usar GetDeathCount para obtener muertes del grupo (disponible en todas las versiones)
        if C_ChallengeMode.GetDeathCount then
            local ok, numDeaths, timeLost = pcall(C_ChallengeMode.GetDeathCount)
            if ok and numDeaths then
                run.stats.deaths = math.max(run.stats.deaths or 0, tonumber(numDeaths) or 0)
            end
        end
    end

    if isPractice then
        if self.Print then self:Print("Run de práctica detectada, no se guardará.") end
        self:_TeardownRun("practice")
        return
    end

    -- Fallback: calcular tiempo desde startTime si las APIs no dieron datos
    local endNow = Now()
    if completionTime == 0 and run.startTime and run.startTime > 0 then
        completionTime = math.max(0, endNow - run.startTime)
    end

    -- Si completionTime sigue en 0, la run probablemente no se completó realmente
    if completionTime == 0 then
        if self.Print then
            self:Print("|cFFFF9922Advertencia:|r No se pudo determinar el tiempo de completado. Run descartada.")
        end
        self:_TeardownRun("no-completion-time")
        return
    end

    run.endTime        = endNow
    run.completionTime = completionTime
    run.inTime         = inTime

    -- ── Recolectar datos finales según la fuente ─────────────────────────────
    -- FIX STATS-1: Intentar C_DamageMeter primero si existe, luego CLEU fallback
    if IS_MIDNIGHT and C_DamageMeter then
        -- Primera lectura inmediata
        self:PollDamageMeterData(run)

        -- FIX RACE-2: Escalated retries — C_DamageMeter can take several
        -- seconds to finalize data after CHALLENGE_MODE_COMPLETED.
        -- Retry at 0.5s, 2s, and 5s to maximize capture probability.
        if C_Timer and C_Timer.After then
            local capturedRun = run
            local function retryPoll()
                if capturedRun and capturedRun.stats then
                    MitzuMPlus:PollDamageMeterData(capturedRun)
                    if capturedRun.runID and MitzuMPlus.db and MitzuMPlus.db.global then
                        MitzuMPlus.db.global.runs[capturedRun.runID] = capturedRun
                    end
                end
            end
            C_Timer.After(0.5, retryPoll)
            C_Timer.After(2.0, retryPoll)
            C_Timer.After(5.0, retryPoll)
        end

        self:UnregisterMidnightCombatTracking()
        self._lastMeterDamage = nil
        self._playerDeadFlag = nil
    end

    -- BUG FIX (ADDON_ACTION_FORBIDDEN): en lugar de UnregisterEvent, apagamos
    -- el gate. _combatFrame sigue recibiendo eventos pero OnEvent los descarta.
    self._trackingActive = false

    self._currentRunRole = nil

    run.timeline[#run.timeline + 1] = {
        timestamp = Now(),
        type      = "finish",
        note      = inTime and "Finalizada en tiempo" or "Finalizada fuera de tiempo",
    }

    -- Party combat events are intentionally not reconstructed in Midnight.

    -- ── LootTracker: guardar loot por jugador en run.loot ────────────────
    if self.LootTracker then
        self.LootTracker:Stop()
        self.LootTracker:ApplyToRun(run)
    end

    -- ── Capture Enemy Forces final state from KeystoneTracker ──────────
    -- BUG FIX (verify reporte: enemyForcesFinalPct=0, enemyForcesTotal=0):
    -- antes la captura estaba protegida por KeystoneTracker:IsActive(), pero
    -- el tracker ya se reseteaba antes de llegar aquí → nunca se capturaba EF.
    -- Ahora forzamos una lectura final con C_Scenario/KeystoneTracker sin
    -- depender del flag _active. Hacemos un Update() extra para refrescar.
    if self.KeystoneTracker then
        -- Refrescar una última vez los criterios (sin importar _active).
        local okUpd = pcall(function()
            if self.KeystoneTracker.Update then
                -- forzar _active=true temporalmente para que Update() haga su trabajo
                local prev = self.KeystoneTracker._active
                self.KeystoneTracker._active = true
                self.KeystoneTracker:Update(true)
                self.KeystoneTracker._active = prev
            end
        end)

        local okEF, ef = pcall(self.KeystoneTracker.GetEnemyForces, self.KeystoneTracker)
        if okEF and type(ef) == "table" then
            run.stats.enemyForcesFinalPct   = tonumber(ef.pct)     or 0
            run.stats.enemyForcesFinalCount = tonumber(ef.current) or 0
            run.stats.enemyForcesTotal      = tonumber(ef.total)   or 0
        end

        local okDI, dCount, dTime = pcall(self.KeystoneTracker.GetDeathInfo, self.KeystoneTracker)
        if okDI then
            local apiDeaths = tonumber(dCount) or 0
            if apiDeaths > (run.stats.deaths or 0) then
                run.stats.deaths = apiDeaths
            end
            run.stats.deathPenaltyTime = tonumber(dTime) or 0
        end
    end

    -- ── Midnight-safe final normalization ─────────────────────────────────
    -- Never synthesize values Blizzard no longer exposes. C_DamageMeter is
    -- authoritative for combat metrics and may only be readable post-combat.
    local st = run.stats or {}
    if st.damageTotal or st.healingTotal or st.damageTaken or st.avoidableDmg
        or st.kicks or st.dispels or st.deaths then
        st.dmgDataSource = run.dataSource == "C_DamageMeter" and "C_DamageMeter" or st.dmgDataSource
        st.healDataSource = run.dataSource == "C_DamageMeter" and "C_DamageMeter" or st.healDataSource
    end

    -- Explicitly discard legacy/inferred fields so old code cannot present a
    -- fabricated zero as a real measurement.
    local blocked = {
        "damagePeak10s", "damageBoss", "damageTrash",
        "healingOverheal", "healingPeak", "healingGroupTotal", "healingSelfTotal",
        "healingCastEfficiency", "healingCrisisEvents", "healingBrezCount",
        "healingCDUptimeSec", "healingSelfAsHealTotal",
        "tankDamageMitigated", "tankMitigationPct", "tankPeakDTPS10s",
        "tankSelfHealTotal", "tankAvoidEvents", "tankParryEvents",
        "tankDodgeEvents", "tankBlockEvents", "tankMissEvents",
        "tankDefensiveUptimeSec", "tankDefensiveUptimePct", "cc", "brez", "deadTime",
    }
    for _, key in ipairs(blocked) do st[key] = nil end

    local runID = self:SaveRun(run)
    if not runID then
        self:_TeardownRun("save-failed")
        return
    end

    -- ── Personal Best check ─────────────────────────────────────────────
    if self.PersonalBest then
        local pbResults = self.PersonalBest:CheckRun(run)
        if pbResults and #pbResults > 0 then
            self.PersonalBest:AnnounceResults(pbResults)
        end
    end

    -- ── Data integrity: enforce run limit ────────────────────────────────
    if self.DataManager then
        self.DataManager:EnforceRunLimit()
    end

    if self.db and self.db.profile and self.db.profile.settings then
        local settings = self.db.profile.settings
        -- showToasts es el interruptor general de avisos en pantalla;
        -- notifyOnComplete es el especifico de "he terminado una llave". Hasta
        -- la v7.9.0 el segundo no se leia en ninguna parte del addon.
        local wantToast = settings.showToasts
            and (not self.NotifyEnabled or self:NotifyEnabled("notifyOnComplete"))
        if wantToast and self.ShowToast then
            local msg = string.format(
                "%s +%d — %s",
                run.dungeonName or "Run",
                run.keyLevel or 0,
                inTime and "EN TIEMPO" or "FUERA DE TIEMPO"
            )
            self:ShowToast(msg, inTime and "ok" or "bad", 4)
        end

        -- "Resumen en chat": otra casilla que no leia nadie. Va al chat, no a
        -- un toast, porque su utilidad es quedar en el historial de la ventana
        -- y poder copiarse.
        -- "Resumen en chat": otra casilla que no leia nadie. Al chat y no a un
        -- toast, porque su gracia es quedar en el historial y poder copiarse.
        -- Aqui NO se usa NotifyEnabled: esta viene apagada de fabrica (el panel
        -- la lee con "or false"), asi que solo se imprime si se activo a mano.
        if self.db.profile.chatOutput == true and self.Print then
            local secs = run.completionTime or 0
            local t = (self.FormatTime and self:FormatTime(secs)) or tostring(secs)
            self:Print(string.format(
                "%s |cFFe8b84a+%d|r  %s  ·  %s  ·  %d muertes",
                run.dungeonName or "Mythic+", run.keyLevel or 0, t,
                inTime and "|cFF21de66en tiempo|r" or "|cFFff5555fuera de tiempo|r",
                (run.stats and run.stats.deaths) or 0))
        end
    end

    if self.Footer and self.Footer.UpdateStats then
        self.Footer:UpdateStats()
    end

    if self.EventBus then
        -- v5.4.2 (BUG A3): RouteAdvisor se suscribe a RUN_COMPLETED, que no se
        -- emitia en ningun sitio, asi que RouteAdvisor:Stop() nunca corria al
        -- terminar una key. Se emiten los dos: RUN_ENDED por compatibilidad con
        -- los listeners existentes y RUN_COMPLETED como nombre canonico.
        self.EventBus:Emit("RUN_ENDED", run, runID)
        self.EventBus:Emit("RUN_COMPLETED", run, runID)
    end

    -- Auto-refresh de paneles UI tras guardar la run
    if C_Timer and C_Timer.After then
        C_Timer.After(0.3, function()
            if MitzuMPlus.PanelHistorial and MitzuMPlus.PanelHistorial.Refresh then
                pcall(MitzuMPlus.PanelHistorial.Refresh, MitzuMPlus.PanelHistorial)
            end
            if MitzuMPlus.PanelStats and MitzuMPlus.PanelStats.Refresh then
                pcall(MitzuMPlus.PanelStats.Refresh, MitzuMPlus.PanelStats)
            end
            if MitzuMPlus.PanelHistorial and MitzuMPlus.PanelHistorial.UpdateMPlusScore then
                pcall(MitzuMPlus.PanelHistorial.UpdateMPlusScore, MitzuMPlus.PanelHistorial)
            end
        end)
    end

    self:_TeardownRun("completed")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- CHALLENGE MODE — RESET
-- ─────────────────────────────────────────────────────────────────────────────

function MitzuMPlus:OnChallengeReset()
    if self.LootTracker         then self.LootTracker:Reset() end
    self._currentRunRole = nil
    self._lastMeterDamage = nil
    self._playerDeadFlag = nil
    self._lastCompletedRunKey = nil
    -- Reset per-run diagnostic flags
    self._meterNoSessionLogged = nil
    self._meterFirstPollLogged = nil
    self._meterValuesLogged = nil
    self._meterNoMatchLogged = nil
    self._meterEventLogged = nil
    self._meterExplored = nil
    self._pendingMeterSources = nil
    self._lastMeterExploreTime = nil
    self._meterSingleArgLogged = nil

    -- FIX BUG-RESET-1: cancelar el ticker de polling de C_DamageMeter si sigue activo.
    -- Sin esto, el ticker sigue ejecutándose indefinidamente tras el reset.
    if self._meterPollTicker then
        self._meterPollTicker:Cancel()
        self._meterPollTicker = nil
    end

    -- BUG FIX (ADDON_ACTION_FORBIDDEN): apagar gate en lugar de UnregisterEvent.
    self._trackingActive = false
    if IS_MIDNIGHT then
        self:UnregisterMidnightCombatTracking()
    end

    self:_TeardownRun("reset")

    if self.EventBus then
        self.EventBus:Emit("RUN_RESET")
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- BOSS KILL
-- ─────────────────────────────────────────────────────────────────────────────

function MitzuMPlus:OnBossKill(event, encounterID, encounterName, difficultyID, groupSize, success)
    local run = _G.MitzuMPlusCurrentRun
    if not run then return end
    if success == 1 then
        run.timeline[#run.timeline + 1] = {
            timestamp = Now(),
            type      = "boss_kill",
            note      = encounterName or "Jefe derrotado",
        }
        -- En Midnight, forzar lectura de C_DamageMeter tras cada boss
        if IS_MIDNIGHT then
            self:PollDamageMeterData(run)
        end
        if self.EventBus then
            self.EventBus:Emit("BOSS_KILLED", encounterName, encounterID)
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- SCENARIO CRITERIA UPDATE — Boss kills + Enemy Forces changes
-- ─────────────────────────────────────────────────────────────────────────────

-- Dump raw scenario criteria a SavedVariables (una vez por sesión) para
-- diagnosticar por qué KeystoneTracker no detecta Enemy Forces en este cliente.
local function _dumpScenarioCriteriaOnce()
    if MitzuMPlus._scenarioDumped then return end
    local sv = _G.MitzuMPlusDB
    if not sv then return end
    local GetStepNumCriteria = _G.C_ScenarioInfo and _G.C_ScenarioInfo.GetStepInfo
        and function()
            local ok, info = pcall(_G.C_ScenarioInfo.GetStepInfo)
            if ok and info and info.numCriteria then return info.numCriteria end
            return 0
        end
        or _G.C_Scenario and _G.C_Scenario.GetStepNumCriteria
        or _G.GetStepNumCriteria

    local GetCriteriaData = _G.C_ScenarioInfo and _G.C_ScenarioInfo.GetCriteriaInfo
        or _G.C_Scenario and _G.C_Scenario.GetCriteriaInfo
        or nil

    local numCriteria = 0
    if GetStepNumCriteria then
        local ok, n = pcall(GetStepNumCriteria)
        if ok then numCriteria = tonumber(n) or 0 end
    end
    if numCriteria == 0 then return end  -- reintentar próximo evento

    MitzuMPlus._scenarioDumped = true
    sv._diag = sv._diag or {}
    sv._diag.scenarioDump = {
        timestamp    = time(),
        numCriteria  = numCriteria,
        criteria     = {},
        apiUsed      = GetCriteriaData and "C_ScenarioInfo" or "legacy",
    }
    for i = 1, numCriteria do
        local info
        if GetCriteriaData then
            local ok, res = pcall(GetCriteriaData, i)
            if ok then info = res end
        else
            -- API legacy retorna múltiples valores; los envolvemos en struct
            local ok, desc, crType, completed, quantity, totalQuantity,
                  flags, assetID, quantityString, criteriaID, duration,
                  elapsed, weightedProgress, isFailed, isWeightedProgress = pcall(function()
                return _G.GetCriteriaInfo(i)
            end)
            if ok then
                info = {
                    description        = desc,
                    criteriaType       = crType,
                    completed          = completed,
                    quantity           = quantity,
                    totalQuantity      = totalQuantity,
                    quantityString     = quantityString,
                    elapsed            = elapsed,
                    duration           = duration,
                    isWeightedProgress = isWeightedProgress,
                }
            end
        end
        if type(info) == "table" then
            local copy = {}
            for k, v in pairs(info) do
                if type(v) ~= "table" and type(v) ~= "function" then
                    copy[k] = v
                end
            end
            sv._diag.scenarioDump.criteria[i] = copy
        end
    end
end

function MitzuMPlus:OnScenarioCriteriaUpdate()
    if not _G.MitzuMPlusCurrentRun then return end
    _dumpScenarioCriteriaOnce()
    if self.KeystoneTracker then
        self.KeystoneTracker:Update()
    end
    if self.EventBus then
        self.EventBus:Emit("SCENARIO_CRITERIA_UPDATED")
    end
end

-- El handler clásico de CombatLog fue eliminado en v6.6.0.
-- Midnight bloquea CombatLogGetCurrentEventInfo para este uso; el addon conserva
-- únicamente fuentes permitidas (Challenge Mode, C_DamageMeter y eventos seguros).

-- ═══════════════════════════════════════════════════════════════════════════
-- ARRANQUE REAL DE LA LLAVE (v7.11.0)
--
-- Core ya no decide cuando empieza una llave: se lo dice DungeonContext, que
-- es quien tiene la maquina de estados y comprueba IsChallengeModeActive().
-- Aqui solo se reacciona. Sin esto, la guarda de BUG CTX-1 dejaria la run sin
-- arrancar nunca, porque CHALLENGE_MODE_START ya paso.
-- ═══════════════════════════════════════════════════════════════════════════
if MitzuMPlus.EventBus then
    MitzuMPlus.EventBus:On("MITZU_KEY_STARTED", function()
        if _G.MitzuMPlusCurrentRun then return end
        pcall(function() MitzuMPlus:OnChallengeStart() end)
    end)
end

return true
