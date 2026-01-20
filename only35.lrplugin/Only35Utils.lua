--[[----------------------------------------------------------------------------
    Only35 Utilities Module

    Constants, configuration, and helper functions used across the plugin.
------------------------------------------------------------------------------]]

local LrLogger = import 'LrLogger'

local Only35Utils = {}

--------------------------------------------------------------------------------
-- API Configuration
--------------------------------------------------------------------------------

Only35Utils.API_BASE_URL = "http://api.only35.app"
Only35Utils.WEB_BASE_URL = "http://only35.app"

--------------------------------------------------------------------------------
-- OAuth Configuration
--------------------------------------------------------------------------------

Only35Utils.CLIENT_ID = "lightroom"
Only35Utils.REDIRECT_URI = "http://only35.app/oauth/success"

Only35Utils.SCOPES = {
    "photographs:read",
    "photographs:write",
    "rolls:read",
    "rolls:write",
}

-- Scopes as space-separated string for OAuth URL
Only35Utils.SCOPES_STRING = table.concat(Only35Utils.SCOPES, " ")

--------------------------------------------------------------------------------
-- API Endpoints
--------------------------------------------------------------------------------

Only35Utils.ENDPOINTS = {
    -- OAuth endpoints (relative to WEB_BASE_URL)
    AUTHORIZE = "/oauth/authorize",

    -- API endpoints (relative to API_BASE_URL)
    TOKEN = "/oauth/token",
    REVOKE = "/oauth/revoke",
    UPLOAD_URL = "/photographs/upload-url",
    PHOTOGRAPHS = "/photographs",
    ROLLS = "/rolls",
}

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

--- Generate a random alphanumeric string for CSRF state parameter
-- @param length Number of characters to generate (default: 32)
-- @return Random alphanumeric string
function Only35Utils.generateRandomString(length)
    length = length or 32
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local result = ""

    -- Seed random number generator with current time
    math.randomseed(os.time())

    for i = 1, length do
        local idx = math.random(1, #chars)
        result = result .. chars:sub(idx, idx)
    end

    return result
end

--- Generate a UUID v4
-- @return string UUID in format xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
function Only35Utils.generateUUID()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    math.randomseed(os.time() + os.clock() * 1000000)

    return string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end)
end

--------------------------------------------------------------------------------
-- Logging
--------------------------------------------------------------------------------

local logger = LrLogger('Only35Plugin')
logger:enable("logfile")

--- Log a debug message
-- @param message The message to log
function Only35Utils.log(message)
    logger:trace(message)
end

--- Log an info message
-- @param message The message to log
function Only35Utils.logInfo(message)
    logger:info(message)
end

--- Log a warning message
-- @param message The message to log
function Only35Utils.logWarn(message)
    logger:warn(message)
end

--- Log an error message
-- @param message The message to log
function Only35Utils.logError(message)
    logger:error(message)
end

--------------------------------------------------------------------------------
-- URL Helpers
--------------------------------------------------------------------------------

--- URL encode a string for use in query parameters
-- @param str The string to encode
-- @return URL encoded string
function Only35Utils.urlEncode(str)
    if str then
        str = string.gsub(str, "\n", "\r\n")
        str = string.gsub(str, "([^%w _%%%-%.~])",
            function(c)
                return string.format("%%%02X", string.byte(c))
            end)
        str = string.gsub(str, " ", "+")
    end
    return str
end

--- Build full API URL from endpoint
-- @param endpoint Endpoint key from ENDPOINTS table or path string
-- @return Full API URL
function Only35Utils.apiUrl(endpoint)
    local path = Only35Utils.ENDPOINTS[endpoint] or endpoint
    return Only35Utils.API_BASE_URL .. path
end

--- Build full web URL from endpoint
-- @param endpoint Endpoint key from ENDPOINTS table or path string
-- @return Full web URL
function Only35Utils.webUrl(endpoint)
    local path = Only35Utils.ENDPOINTS[endpoint] or endpoint
    return Only35Utils.WEB_BASE_URL .. path
end

return Only35Utils
