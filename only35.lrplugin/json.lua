--[[----------------------------------------------------------------------------
    Minimal JSON Encoder/Decoder for Lightroom

    Based on public domain JSON implementations.
    Only handles the subset needed for Only35 API.
------------------------------------------------------------------------------]]

local json = {}

-- Encode a Lua value to JSON string
function json.encode(val)
    local t = type(val)

    if val == nil then
        return "null"
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "number" then
        return tostring(val)
    elseif t == "string" then
        -- Escape special characters
        local escaped = val:gsub('\\', '\\\\')
                           :gsub('"', '\\"')
                           :gsub('\n', '\\n')
                           :gsub('\r', '\\r')
                           :gsub('\t', '\\t')
        return '"' .. escaped .. '"'
    elseif t == "table" then
        -- Check if array or object
        local isArray = true
        local maxIndex = 0
        for k, v in pairs(val) do
            if type(k) ~= "number" or k <= 0 or math.floor(k) ~= k then
                isArray = false
                break
            end
            if k > maxIndex then maxIndex = k end
        end

        if isArray and maxIndex == #val then
            -- Encode as array
            local parts = {}
            for i, v in ipairs(val) do
                table.insert(parts, json.encode(v))
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            -- Encode as object
            local parts = {}
            for k, v in pairs(val) do
                table.insert(parts, json.encode(tostring(k)) .. ":" .. json.encode(v))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    else
        error("Cannot encode type: " .. t)
    end
end

-- Decode a JSON string to Lua value
function json.decode(str)
    if not str or str == "" then
        return nil
    end

    local pos = 1

    local function skipWhitespace()
        while pos <= #str and str:sub(pos, pos):match("%s") do
            pos = pos + 1
        end
    end

    local function parseValue()
        skipWhitespace()
        local c = str:sub(pos, pos)

        if c == '"' then
            -- Parse string
            pos = pos + 1
            local result = ""
            while pos <= #str do
                local char = str:sub(pos, pos)
                if char == '"' then
                    pos = pos + 1
                    return result
                elseif char == '\\' then
                    pos = pos + 1
                    local escaped = str:sub(pos, pos)
                    if escaped == 'n' then result = result .. '\n'
                    elseif escaped == 'r' then result = result .. '\r'
                    elseif escaped == 't' then result = result .. '\t'
                    else result = result .. escaped
                    end
                else
                    result = result .. char
                end
                pos = pos + 1
            end
            error("Unterminated string")

        elseif c == '{' then
            -- Parse object
            pos = pos + 1
            local result = {}
            skipWhitespace()
            if str:sub(pos, pos) == '}' then
                pos = pos + 1
                return result
            end
            while true do
                skipWhitespace()
                local key = parseValue()
                skipWhitespace()
                if str:sub(pos, pos) ~= ':' then
                    error("Expected ':' in object")
                end
                pos = pos + 1
                result[key] = parseValue()
                skipWhitespace()
                local sep = str:sub(pos, pos)
                if sep == '}' then
                    pos = pos + 1
                    return result
                elseif sep == ',' then
                    pos = pos + 1
                else
                    error("Expected ',' or '}' in object")
                end
            end

        elseif c == '[' then
            -- Parse array
            pos = pos + 1
            local result = {}
            skipWhitespace()
            if str:sub(pos, pos) == ']' then
                pos = pos + 1
                return result
            end
            while true do
                table.insert(result, parseValue())
                skipWhitespace()
                local sep = str:sub(pos, pos)
                if sep == ']' then
                    pos = pos + 1
                    return result
                elseif sep == ',' then
                    pos = pos + 1
                else
                    error("Expected ',' or ']' in array")
                end
            end

        elseif str:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true

        elseif str:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false

        elseif str:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil

        elseif c:match("[%d%-]") then
            -- Parse number
            local startPos = pos
            if str:sub(pos, pos) == '-' then pos = pos + 1 end
            while pos <= #str and str:sub(pos, pos):match("%d") do
                pos = pos + 1
            end
            if pos <= #str and str:sub(pos, pos) == '.' then
                pos = pos + 1
                while pos <= #str and str:sub(pos, pos):match("%d") do
                    pos = pos + 1
                end
            end
            if pos <= #str and str:sub(pos, pos):lower() == 'e' then
                pos = pos + 1
                if str:sub(pos, pos):match("[%+%-]") then pos = pos + 1 end
                while pos <= #str and str:sub(pos, pos):match("%d") do
                    pos = pos + 1
                end
            end
            return tonumber(str:sub(startPos, pos - 1))
        else
            error("Unexpected character at position " .. pos .. ": " .. c)
        end
    end

    local result = parseValue()
    skipWhitespace()
    return result
end

return json
