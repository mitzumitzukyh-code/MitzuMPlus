-- ═══════════════════════════════════════════════════════════════════════════
-- 1.1.0-dev.10 -- LOCALIZATION_COMPLETE, la puerta de release.
--
-- El idioma del addon ES el idioma del cliente. No hay selector, ni opción, ni
-- SavedVariable. Este banco arranca el addon COMPLETO por su .toc real con el
-- cliente en distintos idiomas y comprueba lo que un jugador vería:
--
--   enUS / enGB          inglés
--   esES / esMX          español
--   deDE / frFR / ptBR   inglés por el locale por defecto de AceLocale
--
-- Y lo que NUNCA debe pasar: español en un cliente inglés, inglés donde hay
-- traducción, una clave cruda pintada, o un nil.
-- ═══════════════════════════════════════════════════════════════════════════
local tests, assertions, failures = 0, 0, {}
local function equal(a, b, l)
    assertions = assertions + 1
    if a ~= b then error((l or "equal") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end
local function truthy(v, l) equal(not not v, true, l) end
local function test(n, f) tests = tests + 1; local ok, e = pcall(f); if not ok then failures[#failures + 1] = n .. ": " .. tostring(e) end end

local S = dofile("tests/harness/core_scenario.lua")
local newLocale = dofile("tests/harness/locale_stub.lua")

-- Palabras que delatan español en una interfaz que debería estar en inglés.
-- Se comparan sobre el texto real que producen los módulos, no sobre el código.
local SPANISH_MARKERS = {
    "Historial", "Estadísticas", "Configuración", "Fuerzas", "faltan", "RITMO",
    "Muertes", "Jefes", "LLAVE", "Llave", "Esperando", "Vista previa",
    "VISTA PREVIA", "Cerrar", "Eliminar", "Jugadores", "Mazmorra", "MAZMORRA",
    "Temporada", "Todas", "Todos", "Buscar", "Guardar", "Personaje", "Ninguno",
    "Mítica", "Nivel de llave", "Duración", "Añadir", "Restablecer", "ÉXITO",
    "RESULTADO", "JUGADOR", "MEJOR", "TIEMPO", "FECHA",
}
local ENGLISH_MARKERS = {
    "History", "Statistics", "Settings", "Enemy Forces", "remaining", "PACE",
    "Deaths", "Bosses", "KEY ", "Waiting", "PREVIEW", "Close", "Delete",
    "Players", "Dungeon", "DUNGEON", "Season", "Search", "Character",
}

local function contamination(text, markers)
    local hits = {}
    for _, word in ipairs(markers) do
        if tostring(text):find(word, 1, true) then hits[#hits + 1] = word end
    end
    return hits
end

-- Todo lo que un jugador ve en la ventana principal, el tracker y los avisos.
-- Se recoge del addon YA CARGADO, no de una lista escrita a mano.
local function visibleStrings(MP)
    local out = {}
    local function add(v) if type(v) == "string" and v ~= "" then out[#out + 1] = v end end

    local L = MP.L
    -- Pestañas, botones y vacíos de la ventana principal.
    for _, key in ipairs({ "TABBAR_HISTORY", "TABBAR_STATS", "TABBAR_PLAYERS", "TABBAR_SETTINGS",
        "HIST_SEARCH", "HIST_EMPTY", "HIST_RUN_DETAIL", "HIST_DELETE", "HIST_SEASON",
        "COL_DUNGEON", "COL_LEVEL", "COL_RESULT", "COL_CHARACTER", "COL_DATE",
        "STATS_BY_DUNGEON", "STATS_ALL_CHARS", "STATS_TREND",
        "PLR_SEARCH", "PLR_EMPTY", "PLR_EMPTY_DESC", "PLR_BEST_KEY",
        "CFG_TRACKER_SECTION", "CFG_SHOW_PACE", "CFG_PREDICTION_D", "CFG_MINIMAP",
        "CFG_RESET_SETTINGS", "CFG_DELETE_HISTORY", "CFG_ABOUT_SECTION",
        "POPUP_DELETE_RUN", "POPUP_BTN_DELETE", "POPUP_BTN_CANCEL", "POPUP_CLEAR_ALL",
        "MINIMAP_LEFT_CLICK", "MINIMAP_SETTINGS", "EXPORT_TITLE", "EXPORT_CLOSE",
        "FOOTER_NO_RUNS", "BTN_EXPORT", "FILTER_ALL_F", "RESULT_OUT", "RESULT_INCOMPLETE",
        "WIDGET_NO_DATA", "BIND_TOGGLE", "DATE_TODAY", "SEASON_NONE",
    }) do add(L[key]) end

    -- Tracker: el modelo integrado y el resumen, tal cual se pintan.
    local TP = MP.TrackerPresenter
    local state = { mapName = nil, keystoneLevel = 4, timeLimit = 1920, elapsed = 834,
                    forcesCurrent = 502, forcesTotal = 729, forcesPercent = 502 / 729 * 100,
                    bossesCompleted = 2, bossesTotal = 3, deaths = 3, deathTimeLost = 15 }
    local model = TP.Build({ enabled = true, status = "RUNNING", state = state, elapsed = 834,
        prediction = { result = "+2", confidence = 50, plus2Time = 1536, plus3Time = 1152, timeLimit = 1920 },
        constants = { KEY_UPGRADE_PLUS2_RATIO = 0.8, KEY_UPGRADE_PLUS3_RATIO = 0.6 },
        settings = { showConfidence = true, showETA = true } })
    add(model.dungeonName)
    local emb = TP.BuildEmbedded(model, { showConfidence = true })
    add(emb.paceText); add(emb.forcesPrimary); add(emb.forcesSecondary); add(emb.penaltyText)
    add(model.forces.remainingText); add(model.bosses.label); add(model.deaths.label)
    -- Resumen y vista previa.
    local done = { timeLimit = 1920, finalElapsed = 1533, terminalStateConfirmed = true }
    local summary = TP.Build({ enabled = true, status = "COMPLETED", summary = true, state = done,
        final = { code = "+2", source = "OFFICIAL", time = 1533 },
        constants = { KEY_UPGRADE_PLUS2_RATIO = 0.8, KEY_UPGRADE_PLUS3_RATIO = 0.6 } })
    add(summary.summary.title); add(summary.prediction.label); add(summary.prediction.sourceText)
    add(TP.Build(TP.PreviewInput({})).dungeonName); add(TP.TEXT.PREVIEW)
    local pending = TP.Build({ enabled = true, status = "PENDING", state = { timeLimit = 1920 } })
    add(pending.timer.subText)
    return out
end

local function bootWith(locale, fn)
    return S.isolated(function()
        local env = S.boot({ locale = locale })
        local MP = _G.MitzuMPlus
        equal(#env.errors, 0, table.concat(env.errors, "\n"))
        return fn(MP, env)
    end)
end

-- ---------------------------------------------------------------------------

test("locale files: enUS is the canonical set and Spanish matches it key by key", function()
    local en = newLocale("enUS")
    local es = newLocale("esES")
    local enKeys, esKeys = getmetatable(en).keys, getmetatable(es).keys
    truthy(#enKeys > 300, "canonical key count: " .. #enKeys)
    equal(#enKeys, #esKeys, "enUS and esES must define the same number of keys")
    local enSet, esSet = {}, {}
    for _, k in ipairs(enKeys) do enSet[k] = true end
    for _, k in ipairs(esKeys) do esSet[k] = true end
    for _, k in ipairs(enKeys) do truthy(esSet[k], "esES is missing " .. k) end
    for _, k in ipairs(esKeys) do truthy(enSet[k], "enUS (canonical) is missing " .. k) end
    -- Ningún valor puede ser nil ni la propia clave (eso es una traducción olvidada).
    for _, k in ipairs(enKeys) do
        local v = rawget(getmetatable(en).raw, k)
        truthy(type(v) == "string" and v ~= "", "enUS value for " .. k)
        -- DPS/HPS/ROLE... se traducen a si mismos: eso es una traduccion, no
        -- una ausencia. El resto no puede valer exactamente su propia clave.
        local SELF = { COL_INDEX = true, DPS = true, HPS = true, COL_RUNS = true }
        if not SELF[k] then truthy(v ~= k, "enUS value for " .. k .. " is the raw key") end
    end
    for _, k in ipairs(esKeys) do
        local v = rawget(getmetatable(es).raw, k)
        truthy(type(v) == "string" and v ~= "", "esES value for " .. k)
    end
    equal(rawget(getmetatable(en).raw, "LOCALE_ID"), "enUS")
end)

test("format specifiers survive translation (a %d that becomes %s crashes in game)", function()
    local en, es = newLocale("enUS"), newLocale("esES")
    local enRaw, esRaw = getmetatable(en).raw, getmetatable(es).raw
    local function specs(text)
        local found = {}
        for spec in tostring(text):gmatch("%%[%-%d%.]*([diufsxXq])") do found[#found + 1] = spec end
        return table.concat(found, ",")
    end
    for _, key in ipairs(getmetatable(en).keys) do
        equal(specs(esRaw[key]), specs(enRaw[key]), "format specifiers differ for " .. key)
    end
end)

test("enUS client: the whole visible surface is English, with no Spanish left", function()
    bootWith("enUS", function(MP)
        equal(MP.Localization:ClientLocale(), "enUS")
        equal(MP.Localization:ActiveLocale(), "enUS")
        equal(MP.Localization:IsEnglishDefault(), true)
        equal(MP.Localization:MissingKeys(), 0)
        local strings = visibleStrings(MP)
        truthy(#strings > 50, "collected " .. #strings .. " visible strings")
        for _, text in ipairs(strings) do
            local hits = contamination(text, SPANISH_MARKERS)
            equal(#hits, 0, "Spanish in an English client: " .. text .. " -> " .. table.concat(hits, ","))
            -- Una clave cruda de AceLocale se reconoce por el guion bajo:
            -- "TABBAR_HISTORY" frente a la etiqueta real "HISTORY".
            truthy(not text:find("^[A-Z][A-Z0-9]*_[A-Z0-9_]+$"), "raw locale key rendered: " .. text)
        end
        equal(MP.L["TABBAR_HISTORY"], "HISTORY"); equal(MP.L["TABBAR_STATS"], "STATISTICS")
        equal(MP.L["TABBAR_PLAYERS"], "PLAYERS"); equal(MP.L["TABBAR_SETTINGS"], "SETTINGS")
        equal(MP.TrackerPresenter.TEXT.PACE, "PACE")
        equal(MP.TrackerPresenter.TEXT.FORCES, "Enemy Forces")
        equal(MP.TrackerPresenter.TEXT.KEY_COMPLETE, "KEY COMPLETE")
    end)
end)

test("enGB client: English through AceLocale's own mapping, no enGB file needed", function()
    bootWith("enGB", function(MP)
        equal(MP.Localization:ClientLocale(), "enGB")
        equal(MP.Localization:ActiveLocale(), "enUS", "enGB resolves to the enUS table")
        equal(MP.Localization:MissingKeys(), 0)
        for _, text in ipairs(visibleStrings(MP)) do
            local hits = contamination(text, SPANISH_MARKERS)
            equal(#hits, 0, "Spanish on an enGB client: " .. text)
        end
        equal(MP.L["TABBAR_HISTORY"], "HISTORY")
        equal(MP.TrackerPresenter.TEXT.PACE, "PACE")
        equal(MP.TrackerPresenter.TEXT.REMAINING, "%s remaining")
    end)
    -- Y no existe un fichero enGB duplicado que mantener.
    local f = io.open("MitzuMPlus/Locales/enGB.lua", "rb")
    if f then f:close() end
    equal(f, nil, "enGB must be served by the fallback, not by a copied file")
end)

for _, locale in ipairs({ "esES", "esMX" }) do
    test("Spanish client (" .. locale .. "): the interface is Spanish where a translation exists", function()
        bootWith(locale, function(MP)
            equal(MP.Localization:ClientLocale(), locale)
            equal(MP.Localization:ActiveLocale(), locale, "the Spanish file registers for " .. locale)
            equal(MP.Localization:MissingKeys(), 0)
            equal(MP.L["TABBAR_HISTORY"], "HISTORIAL")
            equal(MP.L["TABBAR_STATS"], "ESTADÍSTICAS")
            equal(MP.L["TABBAR_PLAYERS"], "JUGADORES")
            equal(MP.L["TABBAR_SETTINGS"], "CONFIGURACIÓN")
            equal(MP.TrackerPresenter.TEXT.PACE, "RITMO")
            equal(MP.TrackerPresenter.TEXT.FORCES, "Fuerzas enemigas")
            equal(MP.TrackerPresenter.TEXT.KEY_COMPLETE, "LLAVE COMPLETADA")
            -- Ni una sola cadena inglesa donde hay traducción española.
            local english = 0
            for _, text in ipairs(visibleStrings(MP)) do
                english = english + #contamination(text, ENGLISH_MARKERS)
            end
            equal(english, 0, "unexpected English on a Spanish client")
        end)
    end)
end

for _, locale in ipairs({ "deDE", "frFR", "ptBR", "ruRU", "koKR", "zhCN", "zhTW", "itIT" }) do
    test("untranslated client (" .. locale .. ") falls back to English automatically", function()
        bootWith(locale, function(MP)
            equal(MP.Localization:ClientLocale(), locale)
            equal(MP.Localization:ActiveLocale(), "enUS", locale .. " must fall back to enUS")
            equal(MP.Localization:IsEnglishDefault(), true)
            equal(MP.Localization:MissingKeys(), 0, "no missing keys on " .. locale)
            equal(MP.L["TABBAR_HISTORY"], "HISTORY")
            equal(MP.TrackerPresenter.TEXT.PACE, "PACE")
            for _, text in ipairs(visibleStrings(MP)) do
                local hits = contamination(text, SPANISH_MARKERS)
                equal(#hits, 0, "Spanish leaked into " .. locale .. ": " .. text)
                truthy(text ~= nil and text ~= "", "no empty string on " .. locale)
            end
        end)
    end)
end

test("the tracker reads the same in both languages, and the layout measures the real text", function()
    local glyphs = function(text) return #(tostring(text):gsub("[\128-\191]", "")) * 6 end
    local function trackerLines(locale)
        return bootWith(locale, function(MP)
            local TP = MP.TrackerPresenter
            local state = { keystoneLevel = 4, timeLimit = 1920, forcesCurrent = 502, forcesTotal = 729,
                            forcesPercent = 502 / 729 * 100, deaths = 3, deathTimeLost = 15 }
            local model = TP.Build({ enabled = true, status = "RUNNING", state = state, elapsed = 834,
                prediction = { result = "+2", confidence = 50, plus2Time = 1536, plus3Time = 1152, timeLimit = 1920 },
                constants = { KEY_UPGRADE_PLUS2_RATIO = 0.8, KEY_UPGRADE_PLUS3_RATIO = 0.6 },
                settings = { showConfidence = true, showETA = true } })
            local emb = TP.BuildEmbedded(model, { showConfidence = true })
            local lay = TP.LayoutEmbedded(emb, { timerWidth = 114, forcesWidth = 191 }, glyphs)
            return { threshold = lay.threshold.text, pace = lay.pace.text, confidence = lay.pace.confidence,
                     primary = lay.forces.primary, secondary = lay.forces.secondary,
                     forcesMode = lay.forces.mode, penalty = emb.penaltyText }
        end)
    end
    local en, es = trackerLines("enUS"), trackerLines("esES")
    -- Números, reloj y códigos son universales: idénticos en los dos idiomas.
    equal(en.threshold, "+3 5:18"); equal(es.threshold, "+3 5:18")
    equal(en.primary, "502 / 729"); equal(es.primary, "502 / 729")
    equal(en.confidence, "50%"); equal(es.confidence, "50%")
    equal(en.penalty, "-0:15"); equal(es.penalty, "-0:15")
    -- Solo el texto cambia.
    equal(en.pace, "PACE +2"); equal(es.pace, "RITMO +2")
    equal(en.secondary, "227 remaining"); equal(es.secondary, "faltan 227")
    -- Y el layout mide el texto REAL: el inglés aquí es más largo y aun así cabe.
    equal(en.forcesMode, "SPLIT"); equal(es.forcesMode, "SPLIT")
    truthy(glyphs(en.secondary) > glyphs(es.secondary), "English is the longer string here")
    truthy(glyphs(en.primary) + 12 + glyphs(en.secondary) <= 191, "English still fits the bar")
end)

test("a narrow bar sacrifices the same way in both languages", function()
    local glyphs = function(text) return #(tostring(text):gsub("[\128-\191]", "")) * 6 end
    local function forcesMode(locale, width)
        return bootWith(locale, function(MP)
            local TP = MP.TrackerPresenter
            local state = { timeLimit = 1920, forcesCurrent = 502, forcesTotal = 729, forcesPercent = 68 }
            local model = TP.Build({ status = "RUNNING", state = state, elapsed = 834,
                constants = { KEY_UPGRADE_PLUS2_RATIO = 0.8, KEY_UPGRADE_PLUS3_RATIO = 0.6 } })
            local lay = TP.LayoutEmbedded(TP.BuildEmbedded(model, {}), { timerWidth = 114, forcesWidth = width }, glyphs)
            return lay.forces.mode, lay.forces.primary, lay.forces.secondary
        end)
    end
    -- 130 px: "502 / 729" (54) + 12 + "227 remaining" (78) = 144 no cabe en inglés,
    -- pero "faltan 227" (60) sí. El ancho no se codifica por idioma: se mide.
    equal(forcesMode("enUS", 130), "PRIMARY", "English drops the remainder first")
    equal(forcesMode("esES", 130), "SPLIT", "Spanish still fits both columns")
    equal(forcesMode("enUS", 191), "SPLIT")
    -- 50 px: solo cabe el recuento compacto, en los dos idiomas.
    equal(forcesMode("esES", 50), "PRIMARY_COMPACT"); equal(forcesMode("enUS", 50), "PRIMARY_COMPACT")
    equal(forcesMode("esES", 30), "TOO_NARROW"); equal(forcesMode("enUS", 30), "TOO_NARROW")
end)

test("no language setting exists anywhere in the product", function()
    local function read(path) local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s end
    local bootstrap = read("MitzuMPlus/Bootstrap.lua")
    truthy(bootstrap:find('GetLocale(ADDON_NAME)', 1, true), "AceLocale is the single selection layer")
    for _, path in ipairs({ "MitzuMPlus/UI/Panels/Config.lua", "MitzuMPlus/Init.lua",
                            "MitzuMPlus/MitzuMPlus_main.lua", "MitzuMPlus/modules/Database.lua" }) do
        local src = read(path)
        for _, token in ipairs({ "settings.locale", "settings.language", "SetLocale", "selectedLocale",
                                 "languageOverride", "GAME_LOCALE" }) do
            truthy(not src:find(token, 1, true), path .. " must not offer a language setting: " .. token)
        end
    end
end)

test("stored data keeps IDs, not translated words, across a language change", function()
    -- Una run guardada en un cliente español se lee en inglés en uno inglés.
    local spanishRun = { seasonKey = "exp10_s1", keyLevel = 12, dungeonName = "Ara-Kara",
                         timeLimit = 1800, completionTime = 1900, inTime = false,
                         keystoneUpgradeLevels = 0, startTime = 1, stats = {},
                         seasonName = "The War Within - Temporada 1" }
    local function labels(locale)
        return bootWith(locale, function(MP)
            local key, season = MP.RunMetrics:GetSeason(spanishRun)
            local code = MP.PanelHistorial.FormatResult(spanishRun)
            return { key = key, season = season, code = code,
                     label = MP.PanelHistorial.ResultLabel(code) }
        end)
    end
    local en, es = labels("enUS"), labels("esES")
    -- La identidad no cambia nunca.
    equal(en.key, "exp10_s1"); equal(es.key, "exp10_s1")
    equal(en.code, "OUT"); equal(es.code, "OUT", "the result code is an ID, not a word")
    -- Lo que se pinta sí.
    equal(en.label, "Out"); equal(es.label, "Fuera")
    truthy(en.season:find("Season", 1, true), "English season label: " .. en.season)
    truthy(es.season:find("Temporada", 1, true), "Spanish season label: " .. es.season)
    truthy(not en.season:find("Temporada", 1, true), "the stored Spanish name must not leak: " .. en.season)
end)

test("the bug report says which language the player is seeing", function()
    for _, case in ipairs({ { "enUS", "enUS", "enUS" }, { "enGB", "enGB", "enUS" },
                            { "esMX", "esMX", "esMX" }, { "deDE", "deDE", "enUS" } }) do
        bootWith(case[1], function(MP)
            local report = MP.BugReport:Build()
            truthy(report:find("[LOCALIZATION]", 1, true), "the section exists")
            for _, field in ipairs({ "clientLocale=" .. case[2], "activeLocale=" .. case[3],
                                     "fallbackLocale=enUS", "englishDefault=true", "missingKeys=0" }) do
                truthy(report:find(field, 1, true), field .. "\n" .. report:sub(1, 400))
            end
            truthy(report:find("sectionsFailed=none", 1, true))
        end)
    end
end)

test("a missing key is reported, never silently filled", function()
    bootWith("enUS", function(MP)
        equal(MP.Localization:MissingKeys(), 0)
        -- Pedir una clave inexistente: AceLocale avisa por el error handler del
        -- cliente (en el banco eso lanza, asi que cualquier clave olvidada en el
        -- resto de pruebas revienta en el acto) y deja escrita la propia clave.
        -- Nada de "?" ni "UNKNOWN": ni se rellena ni se calla.
        local ok, err = pcall(function() return MP.L["THIS_KEY_DOES_NOT_EXIST"] end)
        equal(ok, false, "a missing key must not pass unnoticed")
        truthy(tostring(err):find("Missing entry for 'THIS_KEY_DOES_NOT_EXIST'", 1, true), tostring(err))
        equal(rawget(MP.L, "THIS_KEY_DOES_NOT_EXIST"), "THIS_KEY_DOES_NOT_EXIST",
            "never nil, never a placeholder")
        local missing, first = MP.Localization:MissingKeys()
        equal(missing, 1); equal(first, "THIS_KEY_DOES_NOT_EXIST")
        local fields = {}
        for _, kv in ipairs(MP.Localization:DiagnosticFields()) do fields[kv[1]] = kv[2] end
        equal(fields.missingKeys, 1)
        equal(fields.localizationWarnings, "MISSING_KEY:THIS_KEY_DOES_NOT_EXIST")
    end)
end)

test("every locale key the runtime asks for exists in both files", function()
    -- La lista sale del CÓDIGO, no de una copia: si alguien añade L["NUEVA"]
    -- sin traducirla, este banco lo ve.
    local used, order = {}, {}
    local function scan(dir)
        local pipe = io.popen('dir /b /s "' .. dir .. '\\*.lua" 2>nul')
        if not pipe then return end
        for path in pipe:lines() do
            local f = io.open(path, "rb")
            if f then
                local src = f:read("*a"); f:close()
                if not path:find("\\libs\\") and not path:find("\\Locales\\") then
                    for key in src:gmatch('L%[%s*"([A-Z][A-Z0-9_]*)"%s*%]') do
                        if not used[key] then used[key] = true; order[#order + 1] = key end
                    end
                end
            end
        end
        pipe:close()
    end
    scan("MitzuMPlus")
    truthy(#order > 100, "found " .. #order .. " keys used by the runtime")
    local en, es = newLocale("enUS"), newLocale("esES")
    local enRaw, esRaw = getmetatable(en).raw, getmetatable(es).raw
    for _, key in ipairs(order) do
        truthy(rawget(enRaw, key) ~= nil, "enUS has no entry for L[\"" .. key .. "\"]")
        truthy(rawget(esRaw, key) ~= nil, "esES has no entry for L[\"" .. key .. "\"]")
    end
end)

if #failures > 0 then error(string.format("Localization: %d failures\n%s", #failures, table.concat(failures, "\n")), 0) end
return { tests = tests, assertions = assertions }
