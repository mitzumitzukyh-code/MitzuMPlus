-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus · RouteSchema v1  —  MitzuRoute, normalizador y validador
--
-- EL FORMATO NATIVO DE RUTA, y las dos funciones que lo custodian: convertir
-- a él (normalizar) y comprobar que lo cumple (validar). Van juntas porque las
-- tres son la misma cosa —el formato— y separarlas obligaría a que dos ficheros
-- conocieran los mismos campos.
--
-- POR QUÉ EXISTE
-- RouteManager no debe conocer `MPlusAdaptiveRouteDB.profiles[k].plannedPulls`.
-- Ese es el formato heredado del importador de MDT, y atarlo a él dejaría al
-- manager sin poder aceptar nunca una ruta escrita a mano o traída de otro
-- sitio. Aquí entra cualquier origen y sale siempre lo mismo: MitzuRoute v1.
--
-- FUENTE DE DATOS ≠ DEPENDENCIA EN EJECUCIÓN
-- `dataOrigin = "MDT"` dice de dónde salieron los datos. No dice que MDT tenga
-- que estar instalado: los datos ya están dentro de Mitzu, en la DB de perfiles
-- y en data/MDTEnemyData.lua. Un `mdtRuntimeRequired=false` con
-- `dataOrigin="MDT"` es correcto y hay que poder afirmarlo sin ambigüedad.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local RouteSchema = {}
MitzuMPlus.RouteSchema = RouteSchema

RouteSchema.VERSION = 1

RouteSchema.SOURCE = {
    MITZU_NATIVE = "MITZU_NATIVE",
    USER_IMPORTED = "USER_IMPORTED",
    MDT_IMPORTED = "MDT_IMPORTED",
}

-- Clasificación de cada clon al validar. Un clon que no se puede resolver no
-- invalida la ruta: se marca y se sigue.
RouteSchema.CLONE_STATUS = {
    VALID = "VALID",
    UNRESOLVED_CLONE_INDEX = "UNRESOLVED_CLONE_INDEX",
    MISSING_ENEMY = "MISSING_ENEMY",
}

local function copyPhysical(meta)
    if type(meta) ~= "table" then return nil end
    local copy = {
        g = tonumber(meta.g), sublevel = tonumber(meta.sublevel),
        x = tonumber(meta.x), y = tonumber(meta.y),
    }
    if type(meta.patrol) == "table" then
        copy.patrol = {}
        for _, point in ipairs(meta.patrol) do
            if type(point) == "table" and tonumber(point.x) and tonumber(point.y) then
                copy.patrol[#copy.patrol + 1] = {
                    x = tonumber(point.x), y = tonumber(point.y),
                }
            end
        end
    end
    if not copy.g and not copy.sublevel and not copy.x and not copy.y and not copy.patrol then
        return nil
    end
    return copy
end

-- ─────────────────────────────────────────────────────────────────────────
-- IDENTIDAD NATIVA
--
-- La ruta heredada se llama "elitzur_rlp_1": es el nombre que le puso su autor
-- en MDT y no es una identidad que Mitzu deba adoptar. Se genera un id propio,
-- estable y derivado del dungeonKey —no del nombre, que está localizado— y el
-- original se conserva en legacyIDs para poder migrar la selección guardada.
-- ─────────────────────────────────────────────────────────────────────────

function RouteSchema.NativeID(dungeonKey, variant)
    return string.format("mitzu_%s_%s", tostring(dungeonKey), variant or "standard")
end

-- ─────────────────────────────────────────────────────────────────────────
-- NORMALIZADOR
--
-- Entrada: un perfil del formato heredado (plannedPulls[i].enemies[]).
-- Salida: MitzuRoute v1, o nil + motivo.
--
-- No se inventa NADA. Un npcID que el perfil no trae sale como nil, no como 0
-- ni como un valor de relleno: quien lo lea tiene que poder distinguir
-- "no lo sé" de "vale cero".
-- ─────────────────────────────────────────────────────────────────────────

function RouteSchema.FromLegacyProfile(profile, dungeonKey, opts)
    if type(profile) ~= "table" then return nil, "perfil vacío" end
    if type(profile.plannedPulls) ~= "table" then return nil, "perfil sin plannedPulls" end
    dungeonKey = tonumber(dungeonKey) or tonumber(profile.challengeMapID)
    if not dungeonKey then return nil, "perfil sin dungeonKey" end
    opts = opts or {}

    local pulls, nMobs, nClones = {}, 0, 0
    for i = 1, #profile.plannedPulls do
        local p = profile.plannedPulls[i]
        local mobs = {}
        if type(p) == "table" and type(p.enemies) == "table" then
            for _, e in ipairs(p.enemies) do
                local clones = {}
                local cloneMetadata = {}
                if type(e.clones) == "table" then
                    for _, c in ipairs(e.clones) do
                        local ci = tonumber(c)
                        if ci then
                            clones[#clones + 1] = ci
                            local meta = type(e.cloneMetadata) == "table"
                                         and copyPhysical(e.cloneMetadata[ci]) or nil
                            if meta then cloneMetadata[ci] = meta end
                        end
                    end
                end
                if #clones > 0 then
                    mobs[#mobs + 1] = {
                        npcID    = tonumber(e.npcID),
                        enemyIdx = tonumber(e.enemyIdx),
                        forces   = tonumber(e.forceCount),
                        amount   = #clones,     -- una unidad por clon
                        cloneIDs = clones,
                        cloneMetadata = next(cloneMetadata) and cloneMetadata or nil,
                        packID   = nil,         -- MDT no lo expone; no se inventa
                    }
                    nMobs = nMobs + 1
                    nClones = nClones + #clones
                end
            end
        end
        pulls[#pulls + 1] = {
            id    = i,
            count = tonumber(p and p.count),
            mobs  = mobs,
        }
    end

    if #pulls == 0 then return nil, "el perfil no tiene ningún pull" end

    local legacyID = profile.name
    return {
        schemaVersion = RouteSchema.VERSION,
        id            = opts.id or RouteSchema.NativeID(dungeonKey),
        dungeonKey    = dungeonKey,
        name          = opts.name or "Mitzu Standard",
        dungeonName   = profile.dungeonName,
        totalForces   = tonumber(profile.totalForces),
        pulls         = pulls,
        legacyIDs     = legacyID and { legacyID } or {},
        source = {
            type            = opts.sourceType or RouteSchema.SOURCE.MITZU_NATIVE,
            dataOrigin      = profile.source or "UNKNOWN",
            originalRouteID = legacyID,
            generatedAt     = (time and time()) or 0,
            forcePrecision  = profile.forcePrecision,
        },
        stats = { mobEntries = nMobs, clones = nClones },
    }
end

-- ─────────────────────────────────────────────────────────────────────────
-- VALIDADOR
--
-- ERROR   la ruta no se puede usar.
-- WARNING la ruta se usa, pero hay algo que conviene saber.
--
-- El caso real que obliga a la distinción: Ruby Life Pools trae 9 clones cuyo
-- índice supera el número de clones que ese enemigo tiene según
-- data/MDTEnemyData.lua (por ejemplo cloneIdx 8 en un enemigo con 6). Eso NO
-- rompe la ruta —los pulls, las tropas y los npcIDs siguen siendo correctos—
-- así que es WARNING. Descartar la ruta entera por eso sería tirar 77 clones
-- buenos por 9 dudosos.
-- ─────────────────────────────────────────────────────────────────────────

local function enemyRef(dungeonIdx, enemyIdx)
    local ED = MitzuMPlus.MDTEnemyData and MitzuMPlus.MDTEnemyData[dungeonIdx]
    local emap = ED and ED.e
    return emap and emap[enemyIdx] or nil
end

function RouteSchema.Validate(route, mdtDungeonIdx)
    local r = {
        valid = true,
        errors = {}, warnings = {},
        clones = { total = 0, valid = 0, unresolved = 0, missingEnemy = 0 },
        pullCount = 0,
    }
    local function err(s) r.errors[#r.errors + 1] = s; r.valid = false end
    local function warn(s) r.warnings[#r.warnings + 1] = s end

    if type(route) ~= "table" then err("la ruta no es una tabla"); return r end
    if route.schemaVersion ~= RouteSchema.VERSION then
        err("schemaVersion " .. tostring(route.schemaVersion) ..
            " (se esperaba " .. RouteSchema.VERSION .. ")")
    end
    if not route.id or route.id == "" then err("ruta sin id") end
    if not tonumber(route.dungeonKey) then err("ruta sin dungeonKey") end
    if not route.name or route.name == "" then warn("ruta sin nombre") end
    if type(route.pulls) ~= "table" or #route.pulls == 0 then
        err("ruta sin pulls"); return r
    end

    r.pullCount = #route.pulls
    local vistos = {}
    for _, pull in ipairs(route.pulls) do
        local pid = pull.id
        if not tonumber(pid) then
            err("pull sin id")
        elseif vistos[pid] then
            err("id de pull duplicado: " .. tostring(pid))
        else
            vistos[pid] = true
        end

        if type(pull.mobs) ~= "table" or #pull.mobs == 0 then
            warn("pull " .. tostring(pid) .. " vacío")
        else
            for _, m in ipairs(pull.mobs) do
                if m.amount == nil or m.amount <= 0 then
                    err("pull " .. tostring(pid) .. ": amount no positivo")
                end
                if m.npcID ~= nil and (type(m.npcID) ~= "number" or m.npcID <= 0) then
                    err("pull " .. tostring(pid) .. ": npcID inválido")
                end
                if m.enemyIdx == nil then
                    warn("pull " .. tostring(pid) .. ": mob sin enemyIdx")
                end

                -- Rango de clones, contrastado con la foto de datos.
                local ref = mdtDungeonIdx and m.enemyIdx
                            and enemyRef(mdtDungeonIdx, m.enemyIdx) or nil
                local maxClones = ref and tonumber(ref[3]) or nil
                for _, ci in ipairs(m.cloneIDs or {}) do
                    r.clones.total = r.clones.total + 1
                    if not ref and mdtDungeonIdx then
                        r.clones.missingEnemy = r.clones.missingEnemy + 1
                    elseif maxClones and ci > maxClones then
                        r.clones.unresolved = r.clones.unresolved + 1
                    else
                        r.clones.valid = r.clones.valid + 1
                    end
                end
            end
        end
    end

    if r.clones.unresolved > 0 then
        warn(string.format(
            "%d clon(es) con índice fuera del rango que declara MDTEnemyData; " ..
            "la ruta es utilizable, pero esos clones no se pueden situar",
            r.clones.unresolved))
    end
    if r.clones.missingEnemy > 0 then
        warn(string.format("%d clon(es) de un enemigo que no está en la foto de datos",
            r.clones.missingEnemy))
    end
    return r
end

return RouteSchema
