-- ═══════════════════════════════════════════════════════════════════════════
-- Cargador de addons para los bancos de pruebas.
--
-- Lee un .toc como lo lee WoW: en orden, saltando comentarios y metadatos, y
-- expandiendo los .xml de las librerias (<Script file> / <Include file>).
-- Devuelve la lista de ficheros Lua y los carga uno a uno, anotando cualquier
-- error con el fichero en el que ocurrio.
-- ═══════════════════════════════════════════════════════════════════════════

local Loader = {}

local function leer(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end
Loader.read = leer

local function dirDe(path)
    return (path:match("^(.*)/[^/]*$")) or "."
end

local function norm(path)
    return (path:gsub("\\", "/"))
end

-- Expande un .xml de libreria a sus ficheros Lua, recursivamente.
local function expandirXML(xmlPath, out)
    local src = leer(xmlPath)
    if not src then
        out[#out + 1] = { missing = xmlPath }
        return
    end
    local base = dirDe(xmlPath)
    src = src:gsub("<!%-%-.-%-%->", "")
    for tag, file in src:gmatch("<(%a+)%s+file%s*=%s*\"([^\"]+)\"") do
        local full = base .. "/" .. norm(file)
        if tag == "Script" then
            out[#out + 1] = { lua = full }
        elseif tag == "Include" then
            expandirXML(full, out)
        end
    end
end

-- Metadatos `## Clave: valor` del .toc.
function Loader.metadata(tocPath)
    local src = leer(tocPath) or ""
    local meta = {}
    for line in (src .. "\n"):gmatch("([^\r\n]*)\r?\n") do
        local k, v = line:match("^##%s*([%w%-_]+)%s*:%s*(.-)%s*$")
        if k then meta[k] = v end
    end
    return meta
end

-- Lista de ficheros en orden de carga. Cada entrada: { lua = ruta } o
-- { missing = ruta } si el .toc nombra algo que no existe.
function Loader.files(tocPath)
    local src = leer(tocPath)
    assert(src, "no existe " .. tostring(tocPath))
    local base = dirDe(norm(tocPath))
    local out = {}
    for line in (src .. "\n"):gmatch("([^\r\n]*)\r?\n") do
        local l = line:match("^%s*(.-)%s*$")
        if l ~= "" and l:sub(1, 1) ~= "#" then
            local full = base .. "/" .. norm(l)
            if l:lower():match("%.xml$") then
                expandirXML(full, out)
            elseif l:lower():match("%.lua$") then
                if leer(full) then
                    out[#out + 1] = { lua = full }
                else
                    out[#out + 1] = { missing = full }
                end
            end
        end
    end
    return out
end

-- Carga todos los ficheros. Devuelve la lista de errores (vacia si todo bien).
function Loader.load(tocPath, opts)
    opts = opts or {}
    local errores, cargados = {}, {}
    for _, e in ipairs(Loader.files(tocPath)) do
        if e.missing then
            errores[#errores + 1] = "FALTA " .. e.missing
        else
            local ok, err = pcall(dofile, e.lua)
            if ok then
                cargados[#cargados + 1] = e.lua
            else
                errores[#errores + 1] = e.lua .. ": " .. tostring(err)
                if opts.stopOnError then break end
            end
        end
    end
    return errores, cargados
end

return Loader
