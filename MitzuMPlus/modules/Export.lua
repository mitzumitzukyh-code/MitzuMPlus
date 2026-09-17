-- ===========================================================================
-- MitzuMPlus M+ Historial - Export Module (v2.2)
-- Funciones de exportación CSV, clipboard y código de importación web.
--
-- NUEVO v2.2:
--   • ExportToCode()  - serializa todas las runs a un JSON compacto con el
--     prefijo "MPLUS2:" para identificar y versionar el formato.
--     Incluye: runs completas, stats, composición de grupo e info del char.
--   • JSONEncode()    - serializador JSON mínimo en Lua puro (WoW no tiene
--     JSON nativo). Soporta: string, number, boolean, nil, table (array/map).
--
-- FIX BUG-T2: usa MitzuMPlus:FormatDate() / FormatTime() en lugar del
--   inexistente MitzuMPlus.Formatters (error original de crash en CSV).
-- ===========================================================================

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
local L = MitzuMPlus.L

local Export = {}
MitzuMPlus.Export = Export

-- -----------------------------------------------------------------------------
-- VERSIÓN DEL FORMATO DE EXPORTACIÓN
-- Cambiar si se modifica la estructura de datos para poder detectar versiones
-- incompatibles en el lado web.
-- -----------------------------------------------------------------------------

Export.CODE_VERSION = 2
Export.CODE_PREFIX  = "MPLUS2:"

-- -----------------------------------------------------------------------------
-- JSON SERIALIZER MINIMALISTA
-- WoW Lua no incluye ninguna librería JSON. Este serializer cubre los tipos
-- que genera el addon: string, number, boolean, nil y table (arrays/maps).
-- No soporta valores circulares ni metatables.
-- -----------------------------------------------------------------------------

local function jsonEscapeString(s)
    s = tostring(s)
    s = s:gsub('\\', '\\\\')
    s = s:gsub('"',  '\\"')
    s = s:gsub('\n', '\\n')
    s = s:gsub('\r', '\\r')
    s = s:gsub('\t', '\\t')
    return '"' .. s .. '"'
end

local function isArray(t)
    if type(t) ~= "table" then return false end
    local maxN = 0
    local count = 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
            return false
        end
        if k > maxN then maxN = k end
        count = count + 1
    end
    -- Consideramos array si no hay huecos (o la tabla está vacía)
    return count == maxN
end

local jsonEncode  -- forward declaration para recursión

jsonEncode = function(val)
    local t = type(val)

    if t == "nil"     then return "null"
    elseif t == "boolean" then return val and "true" or "false"
    elseif t == "number"  then
        -- Evitar notación científica y NaN/Inf que JSON no acepta
        if val ~= val then return "0" end           -- NaN
        if val == math.huge  then return "9e15"  end
        if val == -math.huge then return "-9e15" end
        if math.floor(val) == val then
            return string.format("%d", val)
        else
            return string.format("%.4f", val)
        end
    elseif t == "string" then
        return jsonEscapeString(val)
    elseif t == "table" then
        if isArray(val) then
            -- Array JSON
            local items = {}
            for i = 1, #val do
                items[i] = jsonEncode(val[i])
            end
            return "[" .. table.concat(items, ",") .. "]"
        else
            -- Objeto JSON
            local items = {}
            for k, v in pairs(val) do
                if type(k) == "string" or type(k) == "number" then
                    items[#items + 1] = jsonEscapeString(tostring(k)) .. ":" .. jsonEncode(v)
                end
            end
            return "{" .. table.concat(items, ",") .. "}"
        end
    else
        -- function, userdata, thread -> null
        return "null"
    end
end

-- Exponer para uso interno o debug
Export.JSONEncode = jsonEncode

-- -----------------------------------------------------------------------------
-- CLIPBOARD - abre una EditBox pre-rellenada para copiar con Ctrl+A / Ctrl+C
-- -----------------------------------------------------------------------------

-- opts (opcional, v7.14.0; sin opts el comportamiento es el de siempre):
--   title       titulo de la ventana          (por defecto L["EXPORT_TITLE"])
--   hint        texto de ayuda bajo el titulo
--   autoClose   false para no cerrar sola a los 60 s (un informe largo se lee)
--   mono        true para fuente monoespaciada
--   clearLabel / onClear   boton opcional para limpiar (p. ej. logs de QA)
function Export:CopyToClipboard(text, opts)
    if not text or text == "" then return end
    opts = type(opts) == "table" and opts or {}

    if not MitzuMPlus._clipboardFrame then
        local Theme = MitzuMPlus.Theme
        local f = CreateFrame("Frame", "MitzuMPlusClipboard", UIParent,
                              BackdropTemplateMixin and "BackdropTemplate")
        f:SetSize(700, 500)
        f:SetPoint("CENTER")
        -- Debe quedar por encima de la ventana principal (DIALOG nivel 100).
        -- Bug Report y exportaciones usan este mismo visor.
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetFrameLevel(500)
        f:SetToplevel(true)
        f:SetClampedToScreen(true)

        if Theme and Theme.StyleWindow then
            Theme:StyleWindow(f)
        else
            f:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            f:SetBackdropColor(0.039, 0.039, 0.047, 0.95)
            f:SetBackdropBorderColor(0.290, 0.235, 0.094, 1)
        end

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title = title
        if Theme and Theme.ApplyFont then Theme:ApplyFont(title,"title",16) end
        title:SetPoint("TOP", 0, -10)
        title:SetText(L["EXPORT_TITLE"])
        if Theme and Theme.GOLD and Theme.GOLD.title then
            title:SetTextColor(Theme.GOLD.title.r, Theme.GOLD.title.g, Theme.GOLD.title.b)
        else
            title:SetTextColor(0.784, 0.627, 0.188)
        end

        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        f.hint = hint
        if Theme and Theme.ApplyFont then Theme:ApplyFont(hint,"normal",12) end
        hint:SetPoint("TOP", 0, -28)
        hint:SetText(L["EXPORT_HINT"])
        hint:SetTextColor(0.5, 0.5, 0.5)

        local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT",  10, -46)
        sf:SetPoint("BOTTOMRIGHT", -28, 36)

        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetFontObject(GameFontHighlightSmall)
        if Theme and Theme.ApplyFont then Theme:ApplyFont(eb,"normal",13) end
        eb:SetWidth(sf:GetWidth() or 560)
        eb:SetAutoFocus(true)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        eb:SetScript("OnTextChanged", function(self2)
            sf:UpdateScrollChildRect()
        end)
        sf:SetScrollChild(eb)
        f.scrollFrame = sf
        f.editBox = eb

        local closeBtn = MitzuMPlus:CreateButton(f, L["EXPORT_CLOSE"], "primary", function() f:Hide() end)
        closeBtn:SetPoint("BOTTOM", 0, 8)
        closeBtn:SetWidth(100)
        f.closeBtn = closeBtn

        -- Boton opcional de limpieza. Existe siempre, se muestra solo si se pide.
        local clearBtn = MitzuMPlus:CreateButton(f, "Limpiar", "secondary", function()
            if type(f._onClear) == "function" then pcall(f._onClear) end
            f:Hide()
        end)
        clearBtn:SetPoint("BOTTOMRIGHT", -30, 8)
        clearBtn:SetWidth(130)
        clearBtn:Hide()
        f.clearBtn = clearBtn

        f:Hide()
        MitzuMPlus._clipboardFrame = f
    end

    local cf = MitzuMPlus._clipboardFrame
    local Theme = MitzuMPlus.Theme
    if cf.title then cf.title:SetText(opts.title or L["EXPORT_TITLE"]) end
    if cf.hint then
        cf.hint:SetText(opts.hint or L["EXPORT_HINT"])
    end
    if Theme and Theme.ApplyFont then
        pcall(Theme.ApplyFont, Theme, cf.editBox, opts.mono and "mono" or "normal", opts.mono and 12 or 13)
    end
    cf._onClear = opts.onClear
    if cf.clearBtn then
        if type(opts.onClear) == "function" then
            if cf.clearBtn.SetText then cf.clearBtn:SetText(opts.clearLabel or "Limpiar") end
            cf.clearBtn:Show()
        else
            cf.clearBtn:Hide()
        end
    end
    cf.editBox:SetText(text)
    cf.editBox:HighlightText()
    cf.editBox:SetFocus()

    -- Reafirmar la capa en cada apertura: el frame se reutiliza entre
    -- exportaciones y Bug Report y no debe quedar detrás de MitzuMPlus.
    cf:SetFrameStrata("FULLSCREEN_DIALOG")
    cf:SetFrameLevel(500)
    if cf.SetToplevel then cf:SetToplevel(true) end
    cf:Show()
    if cf.Raise then cf:Raise() end

    -- Auto-cerrar tras 60 segundos para no quedar abierto indefinidamente.
    -- Con una marca por apertura: el temporizador de una exportacion anterior
    -- ya no cierra la ventana si mientras tanto se abrio otra.
    cf._openSeq = (cf._openSeq or 0) + 1
    local seq = cf._openSeq
    if opts.autoClose ~= false and C_Timer and C_Timer.After then
        C_Timer.After(60, function()
            if cf and cf:IsShown() and cf._openSeq == seq then cf:Hide() end
        end)
    end
end

-- -----------------------------------------------------------------------------
-- EXPORT TO CODE - formato "MPLUS2:{json}"
--
-- Estructura del JSON exportado (claves cortas para minimizar tamaño):
--   v    -> versión del formato (int)
--   c    -> info del personaje { n, r, cl, sp, ro, il }
--   runs -> array de runs, cada una:
--          { d, k, i, t, tl, s, st:{dt,pk,de,ki,di,cc,bz}, g:[{n,c,r}] }
--
-- Abreviaturas:
--   d=dungeonName, k=keyLevel, i=inTime, t=completionTime, tl=timeLimit,
--   s=startTime, st=stats (dt=damageTotal, pk=damagePeak10s, de=deaths,
--   ki=kicks, di=dispels, cc=cc, bz=brez), g=group
--   c.n=name, c.r=realm, c.cl=class, c.sp=spec, c.ro=role, c.il=ilvl
--   g[i].n=name, g[i].c=class, g[i].r=role
-- -----------------------------------------------------------------------------

function Export:ExportToCode()
    local runs = MitzuMPlus:GetAllRuns() or {}

    if #runs == 0 then
        MitzuMPlus:Print(L["EXPORT_EMPTY"])
        return
    end

    -- -- Info del personaje (de la run más reciente disponible) --------------
    local charInfo = {
        n  = "",  -- name
        r  = "",  -- realm
        cl = "",  -- class
        sp = "",  -- spec
        ro = "",  -- role
        il = 0,   -- ilvl
    }
    if runs[1] then
        local r0 = runs[1]
        charInfo.n  = r0.playerName  or ""
        charInfo.r  = r0.playerRealm or ""
        charInfo.cl = r0.playerClass or ""
        charInfo.sp = r0.playerSpec  or ""
        charInfo.ro = r0.playerRole  or ""
        charInfo.il = tonumber(r0.playerIlvl) or 0
    end

    -- -- Serializar runs -----------------------------------------------------
    local serialized = {}
    for _, run in ipairs(runs) do
        local st = run.stats or {}

        -- Grupo: solo nombre, clase y rol (evitar datos sensibles extra)
        local group = {}
        if type(run.group) == "table" then
            for _, member in ipairs(run.group) do
                if type(member) == "table" then
                    group[#group + 1] = {
                        n = tostring(member.name  or member.playerName or ""),
                        c = tostring(member.class or member.playerClass or ""),
                        r = tostring(member.role  or member.playerRole or ""),
                    }
                end
            end
        end

        serialized[#serialized + 1] = {
            d  = tostring(run.dungeonName or ""),
            k  = tonumber(run.keyLevel)   or 0,
            i  = run.inTime == true,
            t  = tonumber(run.completionTime) or 0,
            tl = tonumber(run.timeLimit)      or 0,
            s  = tonumber(run.startTime)      or 0,
            st = {
                dt = tonumber(st.damageTotal)  or 0,
                ht = tonumber(st.healingTotal) or 0,
                ab = tonumber(st.absorbTotal) or 0,
                dr = tonumber(st.damageTaken) or 0,
                av = tonumber(st.avoidableDmg) or 0,
                de = tonumber(st.deaths) or 0,
                ki = tonumber(st.kicks) or 0,
                di = tonumber(st.dispels) or 0,
            },
            g = group,
        }
    end

    -- -- Ensamblar payload ----------------------------------------------------
    local payload = {
        v    = Export.CODE_VERSION,
        c    = charInfo,
        runs = serialized,
    }

    local code = Export.CODE_PREFIX .. jsonEncode(payload)

    self:CopyToClipboard(code)
    MitzuMPlus:Print(string.format(
        L["EXPORT_CODE_DONE"] ..
        L["EXPORT_CODE_HINT"],
        #runs
    ))
end

-- -----------------------------------------------------------------------------
-- EXPORTAR A DISCORD - formato markdown para pegar en un canal de Discord
-- Recibe UNA run y devuelve el texto formateado (no abre clipboard).
-- -----------------------------------------------------------------------------

function MitzuMPlus:ExportToDiscord(run)
    if not run then return "" end

    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    local dName = run.dungeonName or L["HIST_UNKNOWN_DUNGEON"]
    local kLvl  = tonumber(run.keyLevel) or 0
    local ct    = tonumber(run.completionTime) or 0
    local tl    = tonumber(run.timeLimit) or 0
    local inT   = run.inTime and true or false

    -- Header
    add("```")
    add("[M+] MitzuMPlus Report")
    add("=======================================")
    add(string.format("%s +%d  -  %s", dName, kLvl, inT and "[OK] EN TIEMPO" or "[X] FUERA DE TIEMPO"))
    add("")

    -- Tiempo
    local function fmtT(s)
        s = tonumber(s) or 0
        return string.format("%02d:%02d", math.floor(s / 60), s % 60)
    end
    add(string.format(L["EXPORT_TIME"], fmtT(ct), tl > 0 and fmtT(tl) or "--:--"))

    -- Fecha
    local ts = tonumber(run.startTime) or 0
    if ts > 0 then
        local ok, d = pcall(date, "%Y-%m-%d %H:%M", ts)
        if ok and d then add(string.format(L["EXPORT_DATE"], d)) end
    end
    add("")

    -- Stats
    local st = run.stats or {}
    local dmg    = tonumber(st.damageTotal) or 0
    local dps    = ct > 0 and math.floor(dmg / ct) or 0
    local deaths = tonumber(st.deaths)  or 0
    local kicks  = tonumber(st.kicks)   or 0
    local dispels= tonumber(st.dispels) or 0

    add(L["EXPORT_STATS"])
    add("---------------------------------------")
    add(string.format(L["EXPORT_AVG_DPS"], self:FormatNumber(dps)))
    add(string.format(L["EXPORT_DAMAGE"], self:FormatNumber(dmg)))
    add(string.format(L["EXPORT_DEATHS"], deaths))
    add(string.format(L["EXPORT_KICKS"], kicks))
    add(string.format(L["EXPORT_DISPELS"], dispels))

    -- Role-specific
    local role = run.playerRole or "DAMAGER"
    if role == "HEALER" then
        local hps = ct > 0 and math.floor((tonumber(st.healingTotal) or 0) / ct) or 0
        add(string.format(L["EXPORT_AVG_HPS"], self:FormatNumber(hps)))
    elseif role == "TANK" then
        local dtps = ct > 0 and math.floor((tonumber(st.damageTaken) or 0) / ct) or 0
        add(string.format(L["EXPORT_AVG_DTPS"], self:FormatNumber(dtps)))
        local avoidable = tonumber(st.avoidableDmg) or 0
        if avoidable > 0 then add(string.format(L["EXPORT_AVOIDABLE"], self:FormatNumber(avoidable))) end
    end
    add("")

    -- Jugador
    local pName = run.playerName or L["COL_PLAYER"]
    local pSpec = run.playerSpec or ""
    local pIlvl = tonumber(run.playerIlvl) or 0
    add(string.format(L["EXPORT_PLAYER"], pName, pSpec ~= "" and pSpec or role, pIlvl))
    add("")

    -- Grupo
    local members = run.groupMembers or run.group or {}
    if #members > 0 then
        add("Grupo")
        add("---------------------------------------")
        for _, m in ipairs(members) do
            local mn = m.name or m.playerName or "?"
            local mr = m.role or m.playerRole or ""
            add(string.format("  %s  (%s)", mn, mr))
        end
        add("")
    end

    -- Afijos
    local affixes = run.affixes
    if type(affixes) == "table" and #affixes > 0 then
        local affNames = {}
        for _, a in ipairs(affixes) do
            local id = type(a) == "table" and a.id or tonumber(a)
            if id and C_ChallengeMode and C_ChallengeMode.GetAffixInfo then
                local n = C_ChallengeMode.GetAffixInfo(id)
                affNames[#affNames + 1] = n or ("Afijo " .. id)
            end
        end
        if #affNames > 0 then
            add(L["EXPORT_AFFIXES"] .. table.concat(affNames, ", "))
            add("")
        end
    end

    add(L["EXPORT_FOOTER"])
    add("```")

    return table.concat(lines, "\n")
end

-- -----------------------------------------------------------------------------
-- EXPORTAR CSV (sin cambios funcionales respecto a v2.1)
-- -----------------------------------------------------------------------------

function Export:ExportToCSV(runList)
    local runs = type(runList)=="table" and runList or (MitzuMPlus:GetAllRuns() or {})

    if #runs == 0 then
        MitzuMPlus:Print(L["EXPORT_EMPTY"])
        return
    end

    local csv = {}
    csv[#csv + 1] = L["EXPORT_CSV_HEADER"]

    for _, run in ipairs(runs) do
        local dungeonName = run.dungeonName or ""
        if dungeonName == "" and run.dungeonID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
            dungeonName = C_ChallengeMode.GetMapUIInfo(run.dungeonID) or "Unknown"
        end
        if dungeonName == "" then dungeonName = "Unknown" end

        local completionTime = tonumber(run.completionTime) or 0
        if completionTime > 86400 then completionTime = math.floor(completionTime / 1000) end
        local dateStr = "--"
        if MitzuMPlus.FormatDate then
            dateStr = MitzuMPlus:FormatDate(run.startTime)
        elseif run.startTime and run.startTime > 0 then
            local ok, d = pcall(date, "*t", run.startTime)
            if ok and d then
                dateStr = string.format("%04d-%02d-%02d", d.year or 2000, d.month or 1, d.day or 1)
            end
        end

        local timeStr = MitzuMPlus:FormatTime(completionTime)
        local function csvText(value) return '"'..tostring(value or ""):gsub('"','""')..'"' end
        local RM=MitzuMPlus.RunMetrics
        local metric,metricLabel
        if RM then metric,metricLabel=RM:GetRoleMetric(run) end
        local deaths=RM and RM:GetGroupDeaths(run)
        local kicks=RM and RM:GetOwnKicks(run)
        local dispels=RM and RM:GetOwnDispels(run)
        local roleLabel=RM and select(2,RM:GetRole(run)) or tostring(run.playerRole or "")
        local tags=type(run.tags)=="table" and table.concat(run.tags,";") or ""

        csv[#csv + 1] = string.format(
            '%s,%s,%d,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s',
            csvText(dateStr),
            csvText(dungeonName),
            run.keyLevel or 0,
            run.inTime and "SI" or "NO",
            csvText(timeStr),
            csvText(metricLabel or ""),
            metric and tostring(math.floor(metric)) or "",
            deaths~=nil and tostring(deaths) or "",
            kicks~=nil and tostring(kicks) or "",
            dispels~=nil and tostring(dispels) or "",
            (tonumber(run.playerIlvl) or 0)>0 and tostring(run.playerIlvl) or "",
            csvText(roleLabel),
            csvText(run.notes or ""),
            csvText(tags)
        )
    end

    local csvText = table.concat(csv, "\n")
    self:CopyToClipboard(csvText)
    MitzuMPlus:Print(string.format(
        L["EXPORT_DONE"],
        #runs
    ))
end

return Export
