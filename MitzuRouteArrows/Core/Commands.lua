-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuRouteArrows · Core/Commands  —  /mra
--
-- Los comandos de flechas, placas, evidencias y alignment. Vivian dentro del
-- /emp de MitzuMPlus; con la separacion pasan aqui, a su propio espacio de
-- nombres, sin alias: un solo nombre por comando.
--
-- GENERADO a partir de las ramas de Init.lua (ver docs/ARCHITECTURE.md) y
-- revisado a mano. Todo lo que antes era self.X del core es ahora MRA.X (este
-- addon) o Host.X (lectura de MitzuMPlus por la API publica).
--
-- Si MitzuMPlus no esta, solo responden `status` y `help`: el resto no tiene
-- estado de llave valido sobre el que trabajar.
-- ═══════════════════════════════════════════════════════════════════════════

local MRA = _G.MitzuRouteArrows
if not MRA then return end

local Host = MRA.Host
local Commands = {}
MRA.Commands = Commands

local COMANDOS = {}
Commands.HANDLERS = COMANDOS

-- ═══════════════════════════════════════════════════════════════════
-- SPIKE FASE S — cuanto se puede resolver de una placa viva.
-- Solo diagnostico. No cambia el comportamiento del addon.
-- ═══════════════════════════════════════════════════════════════════
-- (antes: /emp probe | /emp sondeo)
COMANDOS["probe"] = function(args)

    local LER = MRA and MRA.LiveEnemyResolver
    if not LER then
        MRA:Print("|cFFff9922LiveEnemyResolver no esta cargado.|r")
        return
    end
    local unit = args[2] or "target"
    MRA:Print("|cFFe8b84a--- probe " .. tostring(unit) .. " ---|r")
    for _, line in ipairs(LER:UnitLines(unit)) do MRA:Print(line) end
end

-- (antes: /emp plates | /emp placas)
COMANDOS["plates"] = function(args)

    -- Informe de ANCLAJE, no de identidad. Aqui no se lee ni una API de
    -- unidad: solo tokens de placa y constantes del provider. El volcado
    -- del spike, que si mira tropas e identidad, vive en probeplates.
    local NAP = MRA and MRA.NameplateAnchorProvider
    if not NAP then
        MRA:Print("|cFFff9922NameplateAnchorProvider no esta cargado.|r")
        return
    end
    for _, line in ipairs(NAP:StatusLines()) do MRA:Print(line) end
end

-- ═══════════════════════════════════════════════════════════════════
-- CAPA DE EVIDENCIAS (fase 3)
--
-- Informe de INVESTIGACION. Estas evidencias no llegan a Guidance ni
-- producen flechas: solo se miden. Aqui no se imprime GUID, nombre,
-- vida, tropas, npcID ni el numero de threat — unicamente los enums de
-- EngagementEvidence y UnitLinkEvidence, que son literales nuestros.
--
-- ENGAGED no es MATCH y SAME_UNIT tampoco. Por eso el informe usa el
-- vocabulario de cada modulo tal cual, sin traducirlo al de Guidance:
-- una traduccion invitaria a confundirlos.
-- ═══════════════════════════════════════════════════════════════════
-- (antes: /emp evidence | /emp evidencia)
COMANDOS["evidence"] = function(args)

    local ARe = MRA
    local EE  = ARe and ARe.EngagementEvidence
    local UL  = ARe and ARe.UnitLinkEvidence
    if not (EE and UL) then
        MRA:Print("|cFFff9922La capa de evidencias no esta cargada.|r")
        return
    end

    local visibles = MRA:VisibleNameplates()

    MRA:Print("|cFFe8b84a--- evidence ---|r")
    MRA:Print("visible=" .. #visibles)
    if #visibles == 0 then
        MRA:Print("|cFFff9922No hay placas visibles.|r Acercate a unos mobs.")
        return
    end

    local eng,   rE = EE:EvaluateTokens(visibles)
    local links, rL = UL:EvaluateTokens(visibles)

    if args[2] == "summary" or args[2] == "resumen" then
        MRA:Print("engaged=" .. rE.engaged)
        MRA:Print("notEngaged=" .. rE.notEngaged)
        MRA:Print("unknownEngagement=" .. rE.unknown)
        MRA:Print(" ")
        MRA:Print("targetLinked=" .. rL.TARGET)
        MRA:Print("mouseoverLinked=" .. rL.MOUSEOVER)
        MRA:Print("focusLinked=" .. rL.FOCUS)
        MRA:Print("softenemyLinked=" .. rL.SOFTENEMY)
        MRA:Print("|cFF999999(enlace = SAME_UNIT; DIFFERENT_UNIT y UNKNOWN no cuentan)|r")
        return
    end

    for _, tok in ipairs(visibles) do
        local l = links[tok] or {}
        MRA:Print(" ")
        MRA:Print("|cFFf7d470" .. tok .. "|r")
        MRA:Print("engagement=" .. tostring(eng[tok]))
        MRA:Print("target=" .. tostring(l.TARGET))
        MRA:Print("mouseover=" .. tostring(l.MOUSEOVER))
        MRA:Print("focus=" .. tostring(l.FOCUS))
        MRA:Print("softenemy=" .. tostring(l.SOFTENEMY))
    end
    MRA:Print(" ")
    MRA:Print("|cFF999999(investigacion: estas evidencias NO producen flechas)|r")
end

-- ═══════════════════════════════════════════════════════════════════
-- CASTS (fase 3, experimental)
--
-- Combina el sondeo actual con los eventos escuchados. Ningun valor del
-- cliente se imprime sin haber pasado primero la guarda de secreto.
-- ═══════════════════════════════════════════════════════════════════
-- (antes: /emp castevidence | /emp castevidencia)
COMANDOS["castevidence"] = function(args)

    local CE = MRA and MRA.CastEvidence
    local ECE = MRA and MRA.EventCastEvidence
    if not CE or not ECE then
        MRA:Print("|cFFff9922CastEvidence/EventCastEvidence no estan cargados.|r")
        return
    end
    local visibles = MRA:VisibleNameplates()
    MRA:Print("|cFFe8b84a--- cast evidence ---|r")
    MRA:Print("visible=" .. #visibles)
    if #visibles == 0 then
        MRA:Print("|cFFff9922No hay placas visibles.|r Acercate a unos mobs.")
    end

    local mapa = CE:EvaluateTokens(visibles)
    local resumen = { tokensWithCast = 0, tokensWithSafeSpellID = 0,
        tokensWithSecretSpellID = 0, tokensWithEventOnly = 0 }
    for _, tok in ipairs(visibles) do
        local polled = mapa[tok] or {}
        local event = ECE:InspectToken(tok)
        local castState = polled.state
        if castState == "NOT_CASTING" then castState = "NONE" end
        if (castState == "NONE" or castState == "UNKNOWN") and
           (event.castState == "CASTING" or event.castState == "CHANNELING") then
            castState = event.castState
        end
        if castState == "CASTING" or castState == "CHANNELING" then
            resumen.tokensWithCast = resumen.tokensWithCast + 1
        end
        if event.spellIDState == "AVAILABLE" then
            resumen.tokensWithSafeSpellID = resumen.tokensWithSafeSpellID + 1
        elseif event.spellIDState == "SECRET" then
            resumen.tokensWithSecretSpellID = resumen.tokensWithSecretSpellID + 1
        end
        if event.eventState == "SEEN" and event.spellIDState ~= "AVAILABLE" then
            resumen.tokensWithEventOnly = resumen.tokensWithEventOnly + 1
        end
        if args[2] ~= "summary" and args[2] ~= "resumen" then
            MRA:Print(" ")
            MRA:Print("|cFFf7d470" .. tok .. "|r")
            MRA:Print("unitExists=" .. CE:UnitExistsState(tok))
            MRA:Print("castState=" .. castState)
            MRA:Print("eventState=" .. event.eventState)
            MRA:Print("tokenLinked=" .. event.tokenLinked)
            MRA:Print("spellIDState=" .. event.spellIDState)
            MRA:Print("safeSpellID=" .. event.safeSpellID)
            MRA:Print("eventType=" .. event.eventType)
            MRA:Print("identityState=" .. event.identityState)
            MRA:Print("ageMs=" .. (event.ageMs and string.format("%d", event.ageMs) or "-"))
            -- Este campo solo existe cuando EventCastEvidence ya probo
            -- que el valor es un numero publico.
            if event.safeSpellIDValue then
                MRA:Print("safeSpellIDValue=" .. string.format("%d", event.safeSpellIDValue))
            end
        end
    end
    MRA:Print(" ")
    MRA:Print("tokensWithCast=" .. resumen.tokensWithCast)
    MRA:Print("tokensWithSafeSpellID=" .. resumen.tokensWithSafeSpellID)
    MRA:Print("tokensWithSecretSpellID=" .. resumen.tokensWithSecretSpellID)
    MRA:Print("tokensWithEventOnly=" .. resumen.tokensWithEventOnly)
    MRA:Print("|cFF999999(CAST EVENT + SAFE SPELLID + TOKEN LINKED != IDENTITY RESOLVED)|r")
end

-- ═══════════════════════════════════════════════════════════════════
-- AURAS (fase 3, experimental)
--
-- Cabecera con la POLITICA del cliente (C_Secrets.ShouldAurasBeSecret) y
-- con que API de lectura existe. Esas dos lineas valen mas que el resto
-- del informe: contestan la pregunta de la subfase de una sola vez.
-- ═══════════════════════════════════════════════════════════════════
-- (antes: /emp auraevidence | /emp auraevidencia)
COMANDOS["auraevidence"] = function(args)

    local AE = MRA and MRA.AuraEvidence
    if not AE then
        MRA:Print("|cFFff9922AuraEvidence no esta cargado.|r")
        return
    end
    local visibles = MRA:VisibleNameplates()
    MRA:Print("|cFFe8b84a--- aura evidence ---|r")
    MRA:Print("policy=" .. AE:SecrecyPolicy())
    MRA:Print("api=" .. AE:APIStatus())
    MRA:Print("visible=" .. #visibles)
    if #visibles == 0 then
        MRA:Print("|cFFff9922No hay placas visibles.|r Acercate a unos mobs.")
        return
    end

    local mapa, r = AE:EvaluateTokens(visibles)
    if args[2] == "summary" or args[2] == "resumen" then
        MRA:Print("available=" .. r.available)
        MRA:Print("none=" .. r.none)
        MRA:Print("unknown=" .. r.unknown)
        MRA:Print("safeSpellIDs=" .. r.safeSpellIDs)
        return
    end
    for _, tok in ipairs(visibles) do
        local e = mapa[tok] or {}
        local ids = e.spellIDs or {}
        MRA:Print(" ")
        MRA:Print("|cFFf7d470" .. tok .. "|r")
        MRA:Print("state=" .. tostring(e.state))
        MRA:Print("safeSpellIDs=" .. #ids)
        if #ids > 0 then
            -- Solo numeros ya comprobados. Se formatean con %d, que
            -- reventaria con cualquier cosa que no fuera un numero.
            local partes = {}
            for i = 1, #ids do partes[i] = string.format("%d", ids[i]) end
            MRA:Print("ids=" .. table.concat(partes, ","))
        end
    end
    MRA:Print(" ")
    MRA:Print("|cFF999999(no hay correlacion spellID -> npcID: eso es otra fase)|r")
end

-- ═══════════════════════════════════════════════════════════════════
-- CASTS POR EVENTO (fase 3, experimental)
--
-- Aqui NO se consultan las placas visibles: se enseña lo que el modulo
-- lleva escuchado, que es otra cosa. Una placa puede haber dejado de
-- verse y su cast seguir en la cache hasta que caduque.
--
-- spellIDEventSafeObserved es la respuesta de la subfase en una linea:
-- si alguna vez un evento trajo un spellID que se pudo tocar.
-- ═══════════════════════════════════════════════════════════════════
-- (antes: /emp eventcast | /emp eventocast)
COMANDOS["eventcast"] = function(args)

    local ECE = MRA and MRA.EventCastEvidence
    if not ECE then
        MRA:Print("|cFFff9922EventCastEvidence no esta cargado.|r")
        return
    end
    local lista, r = ECE:Snapshot()
    MRA:Print("|cFFe8b84a--- event cast evidence ---|r")
    MRA:Print("tracked=" .. r.tracked)
    MRA:Print("spellIDEventSafeObserved=" ..
        (ECE:HasSafeSpellID() and "true" or "false"))

    if args[2] == "summary" or args[2] == "resumen" then
        MRA:Print("castStart=" .. r.castStart)
        MRA:Print("channelStart=" .. r.channelStart)
        MRA:Print("succeeded=" .. r.succeeded)
        MRA:Print("stopped=" .. r.stopped)
        MRA:Print("interrupted=" .. r.interrupted)
        MRA:Print("safeSpellIDs=" .. r.safeSpellIDs)
        MRA:Print("secretSpellIDs=" .. r.secretSpellIDs)
        MRA:Print("eventOnly=" .. r.eventOnly)
        MRA:Print("unknown=" .. r.unknown)
        return
    end

    if r.tracked == 0 then
        MRA:Print("|cFFff9922Nada escuchado.|r Haz un pull y repite mientras castean.")
        return
    end
    for _, e in ipairs(lista) do
        MRA:Print(" ")
        MRA:Print("|cFFf7d470" .. e.unitToken .. "|r")
        MRA:Print("eventType=" .. e.eventType)
        MRA:Print("tokenLinked=" .. e.tokenLinked)
        MRA:Print("castState=" .. e.castState)
        MRA:Print("spellIDState=" .. e.spellIDState)
        MRA:Print("safeSpellID=" .. e.safeSpellID)
        MRA:Print("identityState=" .. e.identityState)
        MRA:Print("ageMs=" .. (e.ageMs and string.format("%d", e.ageMs) or "-"))
        if e.safeSpellIDValue then
            MRA:Print("safeSpellIDValue=" .. string.format("%d", e.safeSpellIDValue))
        end
    end
    MRA:Print(" ")
    MRA:Print("|cFF999999(TTL " .. tostring(ECE.TTL) .. "s · un spellID legible seria una firma, no un MATCH)|r")
end

-- ═══════════════════════════════════════════════════════════════════
-- FORMA DEL PACK (fase 3, experimental)
--
-- Aqui se juntan las dos mitades: cuantos espera la ruta (dato estatico,
-- de RouteProgress, que sigue siendo el dueño del pull) y cuantos estan
-- peleando (EngagementEvidence). PackEvidence no conoce a ninguno de los
-- dos: se le pasan los numeros ya hechos.
--
-- ALIGNED NO ES MATCH. Ni marca, ni avanza pull, ni pinta nada.
-- ═══════════════════════════════════════════════════════════════════
-- (antes: /emp packevidence | /emp pack)
COMANDOS["packevidence"] = function(args)

    local PE = MRA and MRA.PackEvidence
    if not PE then
        MRA:Print("|cFFff9922PackEvidence no esta cargado.|r")
        return
    end
    local RP = Host.RouteProgress
    local DC = Host.DungeonContext
    local runtimeState = DC and DC.GetState and DC:GetState() or nil
    local route = RP and RP.GetRoute and RP:GetRoute() or nil
    local pull  = RP and RP.GetCurrentPull and RP:GetCurrentPull() or nil
    local esperado, estadoCuenta = PE:ExpectedFromPull(pull)

    local res = PE:Evaluate({
        expectedCount      = esperado,
        expectedCountState = estadoCuenta,
        visibleTokens      = MRA:VisibleNameplates(),
        runtimeState       = runtimeState,
    })

    local pullTxt = "-"
    if RP and RP.GetPullIndex and RP:GetPullIndex() then
        pullTxt = tostring(RP:GetPullIndex()) .. "/" .. tostring(RP:GetPullCount())
    end

    MRA:Print("|cFFe8b84a--- pack evidence ---|r")
    MRA:Print("runtimeState=" .. tostring(runtimeState or "-"))
    MRA:Print("route=" .. tostring(route and route.id or "-"))
    MRA:Print("pull=" .. pullTxt)
    MRA:Print("expectedCount=" .. tostring(res.expectedCount or "-"))
    MRA:Print("expectedCountState=" .. tostring(res.expectedCountState))
    MRA:Print("identityState=" .. tostring(res.identityState))
    MRA:Print("reasonCode=" .. tostring(res.reasonCode or "-"))

    if args[2] == "summary" or args[2] == "resumen" then
        MRA:Print("visible=" .. res.visible)
        MRA:Print("engaged=" .. res.engaged)
        MRA:Print("notEngaged=" .. res.notEngaged)
        MRA:Print("unknownEngagement=" .. res.unknownEngagement)
        MRA:Print("packState=" .. res.packState)
        MRA:Print("targetInEngaged=" .. tostring(res.links.TARGET))
        return
    end

    MRA:Print("visible=" .. res.visible)
    MRA:Print("engaged=" .. res.engaged)
    MRA:Print("notEngaged=" .. res.notEngaged)
    MRA:Print("unknownEngagement=" .. res.unknownEngagement)
    MRA:Print("packState=" .. res.packState)
    MRA:Print(" ")
    MRA:Print("targetInEngaged=" .. tostring(res.links.TARGET))
    MRA:Print("mouseoverInEngaged=" .. tostring(res.links.MOUSEOVER))
    MRA:Print("focusInEngaged=" .. tostring(res.links.FOCUS))
    MRA:Print("softenemyInEngaged=" .. tostring(res.links.SOFTENEMY))

    if #res.engagedTokens > 0 then
        MRA:Print(" ")
        MRA:Print("candidateTokens:")
        for _, tok in ipairs(res.engagedTokens) do MRA:Print(tok) end
    end
    MRA:Print(" ")
    MRA:Print("|cFFff9922ALIGNED no significa MATCH de ruta.|r|cFF999999 Un pack")
    MRA:Print("equivocado con el mismo numero de mobs dice ALIGNED igual.|r")
end

-- (antes: /emp probeplates)
COMANDOS["probeplates"] = function(args)

    local LER = MRA and MRA.LiveEnemyResolver
    if not LER then
        MRA:Print("|cFFff9922LiveEnemyResolver no esta cargado.|r")
        return
    end
    for _, line in ipairs(LER:PlateLines()) do MRA:Print(line) end
end

-- (antes: /emp resolverdump)
COMANDOS["resolverdump"] = function(args)

    local LER = MRA and MRA.LiveEnemyResolver
    if not LER then
        MRA:Print("|cFFff9922LiveEnemyResolver no esta cargado.|r")
        return
    end
    MRA:Print("|cFFe8b84a--- resolverdump ---|r")
    for _, line in ipairs(LER:ResolverDumpLines()) do MRA:Print(line) end
end

-- (antes: /emp physicalgroups)
COMANDOS["physicalgroups"] = function(args)

    local PG = MRA and MRA.PhysicalGroupMetadata
    local RM = Host.RouteManager
    local route = RM and RM:GetActiveRoute() or nil
    if not PG then
        MRA:Print("|cFFff9922PhysicalGroupMetadata no esta cargado.|r")
        return
    end
    if not route then
        MRA:Print("|cFFff9922No hay una ruta activa.|r")
        return
    end
    local RP = Host.RouteProgress
    local pullIndex = tonumber(args[2]) or (RP and RP:GetPullIndex()) or 1
    MRA:Print("|cFFe8b84a--- physicalgroups ---|r")
    for _, line in ipairs(PG:StatusLines(route, pullIndex)) do MRA:Print(line) end
end

-- (antes: /emp groupcorrelation)
COMANDOS["groupcorrelation"] = function(args)

    local ARc = MRA
    local GC = ARc and ARc.PhysicalGroupCorrelation
    local RM = Host.RouteManager
    local RP = Host.RouteProgress
    local DC = Host.DungeonContext
    if not GC then
        MRA:Print("|cFFff9922PhysicalGroupCorrelation no esta cargado.|r")
        return
    end
    local route = RM and RM:GetActiveRoute() or nil
    local pullIndex = RP and RP:GetPullIndex() or nil
    local runtimeState = DC and DC:GetState() or "UNKNOWN"
    local result = GC:Correlate(route, pullIndex, MRA:VisibleNameplates(), runtimeState)
    MRA:Print("|cFFe8b84a--- group correlation ---|r")
    for _, line in ipairs(GC:StatusLines(result)) do MRA:Print(line) end
end

-- (antes: /emp forcemap)
COMANDOS["forcemap"] = function(args)

    local LER = MRA and MRA.LiveEnemyResolver
    if not LER then
        MRA:Print("|cFFff9922LiveEnemyResolver no esta cargado.|r")
        return
    end
    for _, line in ipairs(LER:ForceMapLines()) do MRA:Print(line) end
end

-- (antes: /emp resolveplates)
COMANDOS["resolveplates"] = function(args)

    local LER = MRA and MRA.LiveEnemyResolver
    if not LER then
        MRA:Print("|cFFff9922LiveEnemyResolver no esta cargado.|r")
        return
    end
    local marcadas, total, err, r = LER:MarkMatchesOnly()
    if err then
        MRA:Print("|cFFff9922" .. tostring(err) .. "|r")
        return
    end
    MRA:Print(string.format(
        "|cFF21de66Resolve:|r %d flecha(s) sobre %d placa(s) — SOLO los MATCH.",
        marcadas, total))
    if r then
        MRA:Print(string.format("  match=%d ambiguous=%d no_match=%d unknown=%d",
            r.match or 0, r.ambiguous or 0, r.no_match or 0, r.unknown or 0))
    end
end

-- (antes: /emp guidance)
COMANDOS["guidance"] = function(args)

    local G = MRA.GuidanceEngine
    if not G then
        MRA:Print("|cFFff9922GuidanceEngine no esta cargado.|r")
        return
    end
    MRA:Print("|cFFe8b84a--- guidance ---|r")
    for _, line in ipairs(G:StatusLines()) do MRA:Print(line) end
end

-- (antes: /emp guidancedetail)
COMANDOS["guidancedetail"] = function(args)

    local G = MRA.GuidanceEngine
    if not G then
        MRA:Print("|cFFff9922GuidanceEngine no esta cargado.|r")
        return
    end
    MRA:Print("|cFFe8b84a--- guidance detail ---|r")
    for _, line in ipairs(G:DetailLines()) do MRA:Print(line) end
end

-- ═══════════════════════════════════════════════════════════════════
-- ARROW DEMO (experimental)
--
-- Pipeline visual APARTE del de produccion: asigna flechas por una
-- heuristica aproximada y registra telemetria de toda la llave. No es
-- identidad, no es MATCH y no mueve el pull. Ver ArrowDemo.lua.
-- ═══════════════════════════════════════════════════════════════════
-- (antes: /emp arrowdemo)
COMANDOS["arrowdemo"] = function(args)

    local ARd = MRA
    local AD  = ARd and ARd.ArrowDemo
    local TEL = ARd and ARd.ArrowDemoTelemetry
    if not (AD and TEL) then
        MRA:Print("|cFFff9922Arrow Demo no esta cargado.|r")
        return
    end
    local sub = args[2]
    if sub == "on" then
        AD:SetEnabled(true)
    elseif sub == "off" then
        if not AD:SetEnabled(false) then MRA:Print("Arrow Demo ya estaba apagado.") end
    elseif sub == "report" or sub == "informe" then
        local run = TEL:GetRun(args[3] and tonumber(args[3]) or nil)
        for _, line in ipairs(TEL:ReportLines(run)) do MRA:Print(line) end
    elseif sub == "log" then
        local run = TEL:GetRun(nil)
        local lineas = TEL:LogLines(run, tonumber(args[3]) or 15)
        if #lineas == 0 then
            MRA:Print("|cFFff9922Sin eventos registrados.|r")
        else
            MRA:Print("|cFFe8b84a--- arrow demo log ---|r")
            for _, line in ipairs(lineas) do MRA:Print(line) end
        end
    elseif sub == "export" or sub == "exportar" then
        local run = TEL:GetRun(args[3] and tonumber(args[3]) or nil)
        local texto = TEL:Export(run)
        if not texto then
            MRA:Print("|cFFff9922No hay ninguna run de Arrow Demo que exportar.|r")
        elseif MRA.CopyBox and MRA.CopyBox:Show(texto) then
            -- (la caja ya esta abierta)
        else
            MRA:Print("|cFFff9922La ventana de exportacion no esta disponible.|r")
        end
    elseif sub == "clear" or sub == "borrar" then
        local n = TEL:ClearStored()
        MRA:Print(string.format("Arrow Demo: %d run(s) guardada(s) borrada(s).", n))
    else
        for _, line in ipairs(AD:StatusLines()) do MRA:Print(line) end
        if sub ~= "status" and sub ~= "estado" then
            MRA:Print("Uso: /mra arrowdemo on | off | status | report [n] | log [n] | export [n] | clear")
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- ALINEACION RUTA <-> EJECUCION FISICA (fase 4). SOLO DIAGNOSTICO.
-- Nada de lo que se imprima aqui ha movido el pull ni ha pintado nada.
-- ═══════════════════════════════════════════════════════════════════
-- (antes: /emp alignmentdetail | /emp alignedetail)
COMANDOS["alignmentdetail"] = function(args)

    local RAl = MRA and MRA.RouteAlignment
    if not RAl then
        MRA:Print("|cFFff9922La capa de alineacion no esta cargada.|r")
        return
    end
    for _, line in ipairs(RAl:DetailLines()) do MRA:Print(line) end
end

-- (antes: /emp align | /emp alineacion)
COMANDOS["alignment"] = function(args)

    local ARd = MRA
    local RAl = ARd and ARd.RouteAlignment
    if not RAl then
        MRA:Print("|cFFff9922La capa de alineacion no esta cargada.|r")
        return
    end
    local sub = args[2]
    if sub == "detail" or sub == "detalle" then
        for _, line in ipairs(RAl:DetailLines()) do MRA:Print(line) end
    elseif sub == "candidates" or sub == "candidatos" then
        for _, line in ipairs(RAl:CandidateLines()) do MRA:Print(line) end
    elseif sub == "history" or sub == "historial" then
        for _, line in ipairs(RAl:HistoryLines()) do MRA:Print(line) end
    elseif sub == "episodes" or sub == "episodios" then
        local EET = ARd.ExecutionEpisodeTracker
        if not EET then
            MRA:Print("|cFFff9922ExecutionEpisodeTracker no esta cargado.|r")
        else
            for _, line in ipairs(EET:StatusLines()) do MRA:Print(line) end
        end
    elseif sub == "signature" or sub == "firma" then
        local RM = Host.RouteManager
        local RP = Host.RouteProgress
        local n = tonumber(args[3]) or (RP and RP:GetPullIndex()) or 1
        local RS = MRA.RouteSignature
        local ruta = RM and RM:GetActiveRoute()
        local sig, err = nil, "sin ruta"
        if RS and ruta then sig = RS:ForPull(ruta, n) end
        if not sig then
            MRA:Print("|cFFff9922" .. tostring(err or "sin ruta") .. "|r")
        else
            MRA:Print("|cFFe8b84a--- Firma estatica del pull " .. n .. " ---|r")
            for _, line in ipairs(ARd.RouteSignature:Lines(RM:GetActiveRoute(), n)) do
                MRA:Print(line)
            end
        end
    elseif sub == "on" then
        RAl:SetEnabled(true)
        MRA:Print("Inferencia de alineacion ACTIVADA (sigue sin mover la ruta).")
    elseif sub == "off" then
        RAl:SetEnabled(false)
        MRA:Print("Inferencia de alineacion APAGADA.")
    else
        for _, line in ipairs(RAl:StatusLines()) do MRA:Print(line) end
        if sub ~= "status" and sub ~= "estado" then
            MRA:Print("Uso: /mra alignment [status] | detail | candidates | history | episodes | signature [n] | on/off")
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- PRUEBA VISUAL DEL PIPELINE
--
-- Recorre RouteProgress -> GuidanceEngine -> RouteArrowPresenter ->
-- RouteArrows con decisiones DEBUG_FORCED. NO llama a RouteArrows
-- directamente: si lo hiciera, no probaria nada del camino.
-- ═══════════════════════════════════════════════════════════════════
-- (antes: /emp arrowpulltest)
COMANDOS["arrowpulltest"] = function(args)

    local G  = MRA.GuidanceEngine
    local P  = MRA.RouteArrowPresenter
    local RP = Host.RouteProgress
    local RM = Host.RouteManager
    if not (G and P) then
        MRA:Print("|cFFff9922GuidanceEngine o RouteArrowPresenter no cargados.|r")
        return
    end
    if args[2] == "clear" or args[2] == "limpiar" then
        local n = G:ClearDebugForced()
        P:Reevaluate()
        MRA:Print(string.format("|cFF21de66Prueba visual apagada|r (%d placas forzadas).", n))
        return
    end

    -- Las placas se toman del registro de Guidance, no de una consulta
    -- propia: asi la prueba usa exactamente lo que el motor ve.
    local visibles = G:GetVisible()
    if #visibles == 0 then
        MRA:Print("|cFFff9922No hay placas visibles.|r Acercate a unos mobs.")
        return
    end
    local cuantas = tonumber(args[2]) or 3
    local elegidas = {}
    for i = 1, math.min(cuantas, #visibles) do elegidas[i] = visibles[i] end
    G:SetDebugForced(elegidas)
    local marcadas = P:Reevaluate()

    local route = RM and RM:GetActiveRoute()
    MRA:Print("|cFFe8b84aMitzuRouteArrows ARROW PULL TEST|r")
    MRA:Print("mode=|cFFf7d470DEBUG_VISUAL|r")
    MRA:Print("route=" .. tostring(route and route.id or "ninguna"))
    MRA:Print("pull=" .. tostring(RP and RP:GetPullIndex() or "?"))
    MRA:Print("visible=" .. #visibles)
    MRA:Print("forcedGuidance=" .. G:CountForced())
    MRA:Print("arrowsVisible=" .. tostring(marcadas))
    MRA:Print("realEnemyMatching=|cFFff9922false|r")
    MRA:Print("|cFF999999Esto NO es identificacion automatica: son decisiones")
    MRA:Print("DEBUG_FORCED que recorren Guidance y Presenter para demostrar")
    MRA:Print("el pipeline. Se apagan solas al cambiar de pull, o con")
    MRA:Print("|cFFf7d470/mra arrowpulltest clear|r.|r")
end

-- (antes: /emp marktarget)
COMANDOS["marktarget"] = function(args)

    local PUR = MRA and MRA.PullUnitResolver
    if not PUR then
        MRA:Print("|cFFff9922PullUnitResolver no esta cargado.|r")
        return
    end
    local ok, info, pull = PUR:MarkTarget()
    MRA:Print(ok and string.format("|cFF21de66Objetivo asignado|r al pull %d (%s).",
                                    pull, tostring(info))
                  or ("|cFFff9922No se pudo asignar:|r " .. tostring(info)))
end

-- (antes: /emp unmarktarget)
COMANDOS["unmarktarget"] = function(args)

    local PUR = MRA and MRA.PullUnitResolver
    if not PUR then
        MRA:Print("|cFFff9922PullUnitResolver no esta cargado.|r")
        return
    end
    local ok, info = PUR:UnmarkTarget()
    MRA:Print(ok and "|cFF21de66Asignacion retirada del objetivo.|r"
                  or ("|cFFff9922No se pudo retirar:|r " .. tostring(info)))
end

-- ═══════════════════════════════════════════════════════════════════
-- ROUTE ARROWS (fase 1) — capa visual aislada.
--
-- Estos comandos no tocan MDT, ni npcIDs, ni el solver. Sirven para
-- demostrar que el renderizado funciona por si solo antes de conectarle
-- nada. /mra arrowall es DEPURACION y desaparecera cuando lo este.
-- ═══════════════════════════════════════════════════════════════════
-- (antes: /emp arrow | /emp flecha)
COMANDOS["arrow"] = function(args)

    local RA = MRA and MRA.RouteArrows
    if not RA then
        MRA:Print("|cFFff9922RouteArrows no esta cargado.|r")
        return
    end
    local sub = args[2]
    if sub == "clear" or sub == "limpiar" then
        MRA:Print(string.format("|cFF21de66Flechas retiradas:|r %d", RA:ClearAll()))
    elseif sub == "debug" then
        local on = RA:SetDebug(not RA._debug)
        MRA:Print("Debug de RouteArrows: " ..
            (on and "|cFF21de66activado|r" or "|cFFff9922desactivado|r"))
        for _, line in ipairs(RA:StatusLines()) do MRA:Print(line) end
    elseif sub == "size" or sub == "tamano" then
        if args[3] == nil then
            MRA:Print(string.format("Tamano actual: |cFFf7d470%s|r. Usa |cFFf7d470/mra arrow size 48|r (10 a 120).",
                tostring(RA:GetOption("arrowSize"))))
            return
        end
        local ok, info = RA:SetOption("arrowSize", args[3])
        MRA:Print(ok and string.format("|cFF21de66Tamano de flecha:|r %s", tostring(info))
                      or ("|cFFff9922No se pudo cambiar:|r " .. tostring(info)))
    elseif sub == "offset" then
        if args[3] == nil then
            MRA:Print(string.format("Offset actual: |cFFf7d470%s, %s|r. Usa |cFFf7d470/mra arrow offset 0 14|r.",
                tostring(RA:GetOption("arrowOffsetX")), tostring(RA:GetOption("arrowOffsetY"))))
            return
        end
        local okX, infoX = RA:SetOption("arrowOffsetX", args[3])
        if not okX then
            MRA:Print("|cFFff9922No se pudo cambiar:|r " .. tostring(infoX))
            return
        end
        local infoY = RA:GetOption("arrowOffsetY")
        if args[4] ~= nil then
            local okY, r = RA:SetOption("arrowOffsetY", args[4])
            if not okY then
                MRA:Print("|cFFff9922No se pudo cambiar:|r " .. tostring(r))
                return
            end
            infoY = r
        end
        MRA:Print(string.format("|cFF21de66Offset de flecha:|r %s, %s", tostring(infoX), tostring(infoY)))
    elseif sub == "alpha" or sub == "opacidad" then
        if args[3] == nil then
            MRA:Print(string.format("Opacidad actual: |cFFf7d470%s|r. Usa |cFFf7d470/mra arrow alpha 0.8|r (0.1 a 1).",
                tostring(RA:GetOption("arrowAlpha"))))
            return
        end
        local ok, info = RA:SetOption("arrowAlpha", args[3])
        MRA:Print(ok and string.format("|cFF21de66Opacidad de flecha:|r %s", tostring(info))
                      or ("|cFFff9922No se pudo cambiar:|r " .. tostring(info)))
    elseif sub == "anchor" or sub == "anclaje" then
        if args[3] == nil then
            MRA:Print(string.format("Anclaje actual: |cFFf7d470%s|r. Modos: |cFFf7d470auto|r (Threat Plates si esta), |cFFf7d470placa|r (centrado en el nameplate de Blizzard), |cFFf7d470tp|r.",
                tostring(RA:GetOption("arrowAnchor"))))
            return
        end
        local ok, info = RA:SetAnchorMode(args[3])
        MRA:Print(ok and string.format("|cFF21de66Anclaje de flecha:|r %s", tostring(info))
                      or ("|cFFff9922No se pudo cambiar:|r " .. tostring(info)))
    elseif sub == "anim" or sub == "animacion" then
        local on = RA:ToggleAnimate()
        if on == nil then
            MRA:Print("|cFFff9922La DB de ajustes aun no esta lista.|r")
        else
            MRA:Print("Animacion de flechas: " ..
                (on and "|cFF21de66activada|r" or "|cFFff9922desactivada|r"))
        end
    elseif sub == "reset" then
        if RA:ResetOptions() then
            MRA:Print("|cFF21de66Aspecto de las flechas restaurado|r (tamano 40, offset 0/8, opacidad 1, anclaje auto).")
        else
            MRA:Print("|cFFff9922La DB de ajustes aun no esta lista.|r")
        end
    elseif sub == "off" or sub == "quitar" then
        if not UnitExists("target") then
            MRA:Print("|cFFff9922No tienes objetivo.|r")
            return
        end
        MRA:Print(RA:UnmarkUnit("target")
            and "|cFF21de66Flecha quitada del objetivo.|r"
            or "|cFFff9922El objetivo no tenia flecha.|r")
    else
        if not UnitExists("target") then
            MRA:Print("|cFFff9922No tienes objetivo.|r Apunta a un mob y repite |cFFf7d470/mra arrow|r.")
            return
        end
        local ok, info = RA:MarkUnit("target")
        if ok then
            MRA:Print("|cFF21de66Flecha puesta|r sobre " .. tostring(info) .. ".")
        else
            MRA:Print("|cFFff9922No se pudo poner la flecha:|r " .. tostring(info))
        end
    end
end

-- (antes: /emp arrowall)
COMANDOS["arrowall"] = function(args)

    local RA = MRA and MRA.RouteArrows
    if not RA then
        MRA:Print("|cFFff9922RouteArrows no esta cargado.|r")
        return
    end
    local marcadas, placas = RA:DebugMarkAllPlates()
    MRA:Print(string.format(
        "|cFF21de66Route Arrows:|r %d flechas sobre %d placas visibles.",
        marcadas, placas))
    if placas == 0 then
        MRA:Print("  No hay ninguna placa visible ahora mismo. Acercate a unos mobs.")
    elseif marcadas < placas then
        MRA:Print("  Alguna placa se rechazo. Usa |cFFf7d470/mra arrow debug|r para ver por que.")
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- COMANDOS PROPIOS DEL ADDON  (no vienen de Init.lua)
-- ═══════════════════════════════════════════════════════════════════════════

local function detectarPlacas()
    local out = {}
    for _, n in ipairs({ "ThreatPlates", "TidyPlatesThreat", "TidyPlates_ThreatPlates",
                         "Plater", "ElvUI" }) do
        if type(rawget(_G, n)) == "table" then out[#out + 1] = n end
    end
    return out
end
Commands._detectPlateAddons = detectarPlacas

-- Estado del addon y de su conexion con MitzuMPlus. Responde siempre, incluso
-- sin MitzuMPlus: es justo el caso en que mas hace falta.
COMANDOS["status"] = function()
    MRA:Print("|cFFe8b84a--- MitzuRouteArrows ---|r")
    MRA:Print("version=" .. tostring(MRA.VERSION) .. "  status=|cFFFF6600" .. MRA.STATUS .. "|r")
    local st = MRA:HostState()
    local api = MRA:GetAPI()
    local ver = api and Host._call("GetVersion") or nil
    MRA:Print("host=MitzuMPlus  state=" .. st ..
              "  version=" .. tostring(ver or "-") ..
              "  requiredAPI=" .. tostring(MRA.REQUIRED_API_VERSION))
    if st ~= MRA.HOST_STATES.OK then
        MRA:Print("|cFFff9922" .. MRA:HostMessage() .. "|r")
    end
    local placas = detectarPlacas()
    MRA:Print("nameplateAddons=" .. (#placas > 0 and table.concat(placas, ",") or "ninguno (placa de Blizzard)"))
    local RA = MRA.RouteArrows
    MRA:Print("routeArrows=" .. tostring(RA and RA:IsEnabled() and "ON" or "OFF") ..
              "  arrowDemo=" .. tostring(MRA.ArrowDemo and MRA.ArrowDemo:IsEnabled() and "ON" or "OFF") ..
              "  alignment=" .. tostring(MRA.RouteAlignment and MRA.RouteAlignment:IsEnabled() and "ON" or "OFF"))
    MRA:Print("pendingSubscriptions=" .. tostring(Host:PendingCount()))
    MRA:Print("|cFF999999Solo lectura de MitzuMPlus: no mueve el pull, no escribe identidad, " ..
              "no toca la sesion de la run.|r")
end

-- Lo que antes salia en /emp ruta del core sobre flechas y asignaciones.
COMANDOS["debug"] = function()
    MRA:Print("|cFFe8b84a--- MitzuRouteArrows debug ---|r")
    local any = false
    for _, nombre in ipairs({ "RouteArrows", "PullUnitResolver", "GuidanceEngine",
                              "RouteArrowPresenter" }) do
        local m = MRA[nombre]
        if m and type(m.StatusLines) == "function" then
            any = true
            local ok, lines = pcall(m.StatusLines, m)
            if ok and type(lines) == "table" then
                for _, l in ipairs(lines) do MRA:Print(l) end
            else
                MRA:Print("|cFFff5555" .. nombre .. ":StatusLines fallo.|r")
            end
        end
    end
    if not any then MRA:Print("No hay modulos con diagnostico cargados.") end
end

local AYUDA = {
    { "status",            "Estado del addon y de la conexion con MitzuMPlus" },
    { "debug",             "Diagnostico de RouteArrows, asignaciones y Guidance" },
    { "arrow ...",         "Flecha sobre tu objetivo (off, clear, size, offset, alpha, anchor, anim, reset, debug)" },
    { "arrowall",          "DEBUG: flecha sobre todas las placas visibles" },
    { "marktarget",        "Asigna tu objetivo al pull actual" },
    { "unmarktarget",      "Quita esa asignacion" },
    { "plates",            "A que frame se ancla cada flecha" },
    { "guidance",          "Que decide el motor sobre las placas visibles" },
    { "guidancedetail",    "Decision placa por placa" },
    { "arrowpulltest [n]", "Prueba VISUAL del pipeline completo" },
    { "arrowdemo ...",     "DEMO de flechas aproximadas + telemetria (on/off/status/report/log/export/clear)" },
    { "alignment ...",     "En que pull cree estar la inferencia (candidates/history/episodes/signature/detail/on/off)" },
    { "alignmentdetail",   "Best/runner-up, margen y desglose pasivo" },
    { "evidence [summary]","Engagement y enlaces de cada placa visible" },
    { "castevidence",      "Que esta casteando cada placa visible" },
    { "auraevidence",      "Auras legibles de cada placa visible" },
    { "eventcast",         "Casts escuchados por evento" },
    { "packevidence",      "Cuantos espera el pull vs cuantos pelean" },
    { "physicalgroups [n]","Grupos fisicos MDT (diagnostico)" },
    { "groupcorrelation",  "Engaged vs grupos fisicos (diagnostico)" },
    { "probe [unidad]",    "SPIKE: todo lo legible de una placa" },
    { "probeplates",       "SPIKE: una linea por placa visible" },
    { "resolverdump",      "Resolver por placa (solo estados seguros)" },
    { "resolveplates",     "SPIKE: flecha solo sobre los MATCH" },
    { "forcemap",          "SPIKE: colisiones de tropas por pull" },
}

COMANDOS["help"] = function()
    MRA:Print("|cFFFF6600MitzuRouteArrows " .. tostring(MRA.VERSION) ..
              " · EXPERIMENTAL / IN DEVELOPMENT|r")
    for _, fila in ipairs(AYUDA) do
        MRA:Print(string.format("|cFFf7d470/mra %s|r - %s", fila[1], fila[2]))
    end
end

-- Los unicos que funcionan sin MitzuMPlus.
local SIN_HOST = { status = true, help = true }

function Commands:Handle(input)
    local args = { strsplit(" ", (tostring(input or "")):lower()) }
    local cmd = args[1]
    if cmd == nil or cmd == "" then cmd = "help" end

    local handler = COMANDOS[cmd]
    if not handler then
        MRA:Print("Comando desconocido: " .. tostring(cmd) .. ". Usa |cFFf7d470/mra help|r.")
        return false
    end
    if not SIN_HOST[cmd] and not MRA:CanOperate() then
        MRA:Print("|cFFff9922" .. MRA:HostMessage() .. "|r")
        return false
    end
    local ok, err = pcall(handler, args)
    if not ok then
        MRA:Print("|cFFff5555Error en /mra " .. cmd .. ":|r " .. tostring(err))
        return false
    end
    return true
end

function Commands:List()
    local out = {}
    for nombre in pairs(COMANDOS) do out[#out + 1] = nombre end
    table.sort(out)
    return out
end

-- /mra y su forma larga. Nombres propios: no colisionan con /emp ni /mitzumplus.
-- No se reasigna la global SlashCmdList (seria escribir una variable de
-- Blizzard y contaminarla): solo se anade la entrada de este addon.
SLASH_MITZUROUTEARROWS1 = "/mra"
SLASH_MITZUROUTEARROWS2 = "/mitzuroutearrows"
if type(SlashCmdList) == "table" then
    SlashCmdList["MITZUROUTEARROWS"] = function(msg) Commands:Handle(msg) end
end

return Commands
