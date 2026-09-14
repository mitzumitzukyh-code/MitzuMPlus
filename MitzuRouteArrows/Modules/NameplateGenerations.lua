-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuRouteArrows · NameplateGenerations v1.0  —  EXPERIMENTAL
--
-- UNA SOLA PREGUNTA: el mob que ocupa hoy "nameplate3", ¿es el mismo que lo
-- ocupaba hace un momento?
--
-- WoW recicla los tokens. "nameplate3" es un hueco, no un mob: cuando el mob
-- sale de rango, el token se libera, y el siguiente mob que entra puede
-- heredarlo. Sin GUID —que en 12.1 llega secreto— la única forma de
-- distinguir a los dos ocupantes es CONTAR las ocupaciones.
--
-- Cada NAME_PLATE_UNIT_ADDED abre una generación nueva. El número es GLOBAL y
-- MONOTÓNICO durante la sesión: "nameplate3 gen=17" y "nameplate3 gen=18"
-- son dos ocupantes distintos, y ningún otro token tendrá nunca gen=17.
--
-- POR QUÉ NO SE REUTILIZA EL DE EventCastEvidence
-- Aquel contador es por token, privado, y vuelve a 1 en cada cambio de zona:
-- tras un PLAYER_ENTERING_WORLD, "nameplate3 gen=1" podría ser dos mobs
-- distintos. Además el orden entre su frame y cualquier otro frame que
-- escuche el mismo evento no está garantizado. Extraerlo exigiría tocar un
-- módulo que ya está LIVE PASS. Este es pequeño y no depende de nadie.
--
-- NO ES IDENTIDAD. Una generación dice "este hueco lo ocupa alguien nuevo",
-- nunca "este es el clon 4 del enemigo 11".
--
-- NO SE TOCA NINGUNA API DE UNIDAD. Solo la forma del token.
-- ═══════════════════════════════════════════════════════════════════════════

local MRA = _G.MitzuRouteArrows
if not MRA then return end

-- AR: los demas modulos de este mismo addon.
-- Host: fachada de SOLO LECTURA sobre MitzuMPlusAPI (Core/Host.lua).
local AR = MRA
local Host = MRA.Host

local NameplateGenerations = {}
AR.NameplateGenerations = NameplateGenerations

-- Tipos de aviso a los suscriptores. Vocabulario cerrado.
local ADDED, REMOVED, REPLACED, SEEDED, RESET =
      "ADDED", "REMOVED", "REPLACED", "SEEDED", "RESET"
NameplateGenerations.KINDS = {
    ADDED = ADDED, REMOVED = REMOVED, REPLACED = REPLACED,
    SEEDED = SEEDED, RESET = RESET,
}

NameplateGenerations._seq       = 0    -- global, nunca retrocede
NameplateGenerations._current   = {}   -- [token] = gen mientras se ve
NameplateGenerations._listeners = {}
NameplateGenerations._stats     = { added = 0, removed = 0, replaced = 0,
                                    seeded = 0, resets = 0 }

-- ─────────────────────────────────────────────────────────────────────────
-- FORMA DEL TOKEN
-- ─────────────────────────────────────────────────────────────────────────

function NameplateGenerations:IsNameplateToken(unitToken)
    if type(unitToken) ~= "string" then return false end
    local ok, m = pcall(string.match, unitToken, "^nameplate%d+$")
    return ok and m ~= nil
end

-- ─────────────────────────────────────────────────────────────────────────
-- SUSCRIPCIÓN
--
-- Los avisos salen DESPUÉS de actualizar el contador, así que quien escuche
-- lee siempre el valor nuevo. Es la razón de centralizarlo: con dos frames
-- escuchando el mismo evento, el orden entre ellos no está garantizado.
-- ─────────────────────────────────────────────────────────────────────────

function NameplateGenerations:Subscribe(fn)
    if type(fn) ~= "function" then return false end
    self._listeners[#self._listeners + 1] = fn
    return true
end

local function avisar(self, kind, token, gen, prevGen)
    for i = 1, #self._listeners do
        pcall(self._listeners[i], kind, token, gen, prevGen)
    end
end

-- ─────────────────────────────────────────────────────────────────────────
-- CONSULTA
-- ─────────────────────────────────────────────────────────────────────────

function NameplateGenerations:Current(unitToken)
    if type(unitToken) ~= "string" then return nil end
    return self._current[unitToken]
end

function NameplateGenerations:IsCurrent(unitToken, gen)
    if type(gen) ~= "number" then return false end
    return self:Current(unitToken) == gen
end

function NameplateGenerations:ActiveCount()
    local n = 0
    for _ in pairs(self._current) do n = n + 1 end
    return n
end

function NameplateGenerations:LastSequence()
    return self._seq
end

-- ─────────────────────────────────────────────────────────────────────────
-- SIEMBRA
--
-- Tras un /reload las placas que ya estaban en pantalla nunca disparan un
-- ADDED. Quien las vea por otra vía (el registro de Guidance) puede pedir que
-- se les abra una generación. Solo a las que no tienen ninguna.
-- ─────────────────────────────────────────────────────────────────────────

function NameplateGenerations:Seed(tokens)
    if type(tokens) ~= "table" then return 0 end
    local n = 0
    for _, tok in ipairs(tokens) do
        if self:IsNameplateToken(tok) and self._current[tok] == nil then
            self._seq = self._seq + 1
            self._current[tok] = self._seq
            self._stats.seeded = self._stats.seeded + 1
            n = n + 1
            avisar(self, SEEDED, tok, self._seq, nil)
        end
    end
    return n
end

-- ─────────────────────────────────────────────────────────────────────────
-- ENTRADA ÚNICA
--
-- El frame de abajo solo reenvía. Lo que se prueba en el banco es lo mismo
-- que corre en el juego.
-- ─────────────────────────────────────────────────────────────────────────

function NameplateGenerations:Observe(event, unitToken)
    if event == "PLAYER_ENTERING_WORLD" then
        local habia = false
        for tok in pairs(self._current) do
            self._current[tok] = nil
            habia = true
        end
        self._stats.resets = self._stats.resets + 1
        avisar(self, RESET, nil, nil, nil)
        return habia and RESET or nil
    end

    if not self:IsNameplateToken(unitToken) then return nil end

    if event == "NAME_PLATE_UNIT_ADDED" then
        local prev = self._current[unitToken]
        if prev then
            -- Se perdió el REMOVED del ocupante anterior. No se hereda nada:
            -- se cierra su generación y se abre otra.
            self._stats.replaced = self._stats.replaced + 1
            avisar(self, REPLACED, unitToken, nil, prev)
        end
        self._seq = self._seq + 1
        self._current[unitToken] = self._seq
        self._stats.added = self._stats.added + 1
        avisar(self, ADDED, unitToken, self._seq, prev)
        return ADDED
    end

    if event == "NAME_PLATE_UNIT_REMOVED" then
        local prev = self._current[unitToken]
        self._current[unitToken] = nil
        self._stats.removed = self._stats.removed + 1
        avisar(self, REMOVED, unitToken, nil, prev)
        return REMOVED
    end
    return nil
end

-- ─────────────────────────────────────────────────────────────────────────
-- EVENTOS — se registran al cargar y no se desregistran nunca (taint).
-- ─────────────────────────────────────────────────────────────────────────

if type(CreateFrame) == "function" then
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", function(_, event, unitToken)
        return NameplateGenerations:Observe(event, unitToken)
    end)
    NameplateGenerations._frame = frame
end

return NameplateGenerations
