-- ═══════════════════════════════════════════════════════════════════════════
-- Lectura de codigo Lua para las comprobaciones de dependencias.
--
--   local Src = dofile("tests/harness/lua_source.lua")
--   Src.code(texto)      -- el codigo sin comentarios y con cada string vaciado
--   Src.identifiers(txt) -- conjunto de identificadores que aparecen en el codigo
--
-- Un lexer minimo, pero correcto para lo que importa aqui: distingue codigo de
-- comentarios y de strings (cortos y largos), para que "MitzuMPlus" en un
-- mensaje o en un comentario no cuente como una dependencia, y un nombre en el
-- codigo no se escape por estar junto a un "--" dentro de un string.
-- ═══════════════════════════════════════════════════════════════════════════

local Src = {}

-- Nivel de un corchete largo en la posicion i ("[[", "[=[", ...) o nil.
local function largo(s, i)
    local eq = s:match("^%[(=*)%[", i)
    return eq and #eq or nil
end

function Src.code(s)
    local out, i, n = {}, 1, #s
    while i <= n do
        local c = s:sub(i, i)
        if c == "-" and s:sub(i + 1, i + 1) == "-" then
            local nivel = largo(s, i + 2)
            if nivel then
                local cierre = "]" .. string.rep("=", nivel) .. "]"
                local fin = s:find(cierre, i + 2, true)
                i = fin and (fin + #cierre) or (n + 1)
            else
                local fin = s:find("\n", i, true)
                i = fin or (n + 1)
            end
            out[#out + 1] = " "
        elseif c == "\"" or c == "'" then
            local j = i + 1
            while j <= n do
                local d = s:sub(j, j)
                if d == "\\" then
                    j = j + 2
                elseif d == c or d == "\n" then
                    break
                else
                    j = j + 1
                end
            end
            out[#out + 1] = "\"\""
            i = j + 1
        elseif c == "[" and largo(s, i) then
            local nivel = largo(s, i)
            local cierre = "]" .. string.rep("=", nivel) .. "]"
            local fin = s:find(cierre, i + 2 + nivel, true)
            out[#out + 1] = "\"\""
            i = fin and (fin + #cierre) or (n + 1)
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out)
end

-- Strings literales del codigo (sin comentarios), en orden.
function Src.strings(s)
    local lista, i, n = {}, 1, #s
    while i <= n do
        local c = s:sub(i, i)
        if c == "-" and s:sub(i + 1, i + 1) == "-" then
            local nivel = largo(s, i + 2)
            if nivel then
                local cierre = "]" .. string.rep("=", nivel) .. "]"
                local fin = s:find(cierre, i + 2, true)
                i = fin and (fin + #cierre) or (n + 1)
            else
                i = (s:find("\n", i, true)) or (n + 1)
            end
        elseif c == "\"" or c == "'" then
            local j = i + 1
            while j <= n do
                local d = s:sub(j, j)
                if d == "\\" then j = j + 2
                elseif d == c or d == "\n" then break
                else j = j + 1 end
            end
            lista[#lista + 1] = s:sub(i + 1, j - 1)
            i = j + 1
        elseif c == "[" and largo(s, i) then
            local nivel = largo(s, i)
            local cierre = "]" .. string.rep("=", nivel) .. "]"
            local fin = s:find(cierre, i + 2 + nivel, true)
            lista[#lista + 1] = s:sub(i + 2 + nivel, (fin or n + 1) - 1)
            i = fin and (fin + #cierre) or (n + 1)
        else
            i = i + 1
        end
    end
    return lista
end

function Src.identifiers(s)
    local set = {}
    for id in Src.code(s):gmatch("[%a_][%w_]*") do set[id] = true end
    return set
end

function Src.read(path)
    local f = assert(io.open(path, "rb"), "no existe " .. path)
    local t = f:read("*a")
    f:close()
    return t
end

return Src
