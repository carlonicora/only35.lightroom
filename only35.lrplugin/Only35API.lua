--[[----------------------------------------------------------------------------
    Only35 API Client Module

    HTTP client for communicating with the Only35 API.
    Handles authentication, JSON encoding, and error handling.
------------------------------------------------------------------------------]]

local LrHttp = import 'LrHttp'
local LrDialogs = import 'LrDialogs'
local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'
local LrTasks = import 'LrTasks'

local Only35Utils = require 'Only35Utils'
local Only35Auth = require 'Only35Auth'
local json = require 'json'

local Only35API = {}

--------------------------------------------------------------------------------
-- HTTP Helpers
--------------------------------------------------------------------------------

--- Make a POST request with JSON body
-- @param url Full URL to POST to
-- @param data Table to encode as JSON body
-- @param retryCount Current retry attempt (internal)
-- @param authRetryCount Number of 401 refresh attempts (internal)
-- @return table Parsed JSON response
function Only35API.postJson(url, data, retryCount, authRetryCount)
    retryCount = retryCount or 0
    authRetryCount = authRetryCount or 0
    local maxRetries = 3
    local maxAuthRetries = 1

    local token = Only35Auth.getAccessToken()
    if not token then
        error("Not authenticated. Please log in first.")
    end

    local headers = {
        { field = "Authorization", value = "Bearer " .. token },
        { field = "Content-Type", value = "application/vnd.api+json" },
        { field = "Accept", value = "application/vnd.api+json" },
    }

    local body = json.encode(data)

    local result, responseHeaders = LrHttp.post(url, body, headers)

    if not result then
        if retryCount < maxRetries then
            LrTasks.sleep(2 ^ retryCount)
            return Only35API.postJson(url, data, retryCount + 1, authRetryCount)
        end
        error("Network error: no response from server")
    end

    local status = responseHeaders.status

    -- Handle 401 Unauthorized - try token refresh (only once)
    if status == 401 then
        if authRetryCount < maxAuthRetries then
            if Only35Auth.refreshAccessToken() then
                return Only35API.postJson(url, data, 0, authRetryCount + 1)
            end
        end
        error("Authentication expired. Please log in again.")
    end

    -- Handle rate limiting
    if status == 429 then
        local retryAfter = 60
        for _, header in ipairs(responseHeaders) do
            if header.field:lower() == "retry-after" then
                retryAfter = tonumber(header.value) or 60
                break
            end
        end
        LrTasks.sleep(retryAfter)
        return Only35API.postJson(url, data, retryCount)
    end

    -- Handle server errors with retry
    if status >= 500 and retryCount < maxRetries then
        LrTasks.sleep(2 ^ retryCount)
        return Only35API.postJson(url, data, retryCount + 1)
    end

    -- Handle client errors
    if status >= 400 then
        local errorMsg = "API error " .. status
        pcall(function()
            local errorBody = json.decode(result)
            if errorBody.message then
                errorMsg = errorMsg .. ": " .. errorBody.message
            elseif errorBody.error then
                errorMsg = errorMsg .. ": " .. errorBody.error
            end
        end)
        error(errorMsg)
    end

    -- Parse successful response
    if result and result ~= "" then
        return json.decode(result)
    end

    return nil
end

--- Make a PATCH request with JSON body
-- @param url Full URL to PATCH
-- @param data Table to encode as JSON body
-- @param authRetryCount Number of 401 refresh attempts (internal)
-- @return table Parsed JSON response
function Only35API.patchJson(url, data, authRetryCount)
    authRetryCount = authRetryCount or 0
    local maxAuthRetries = 1

    local token = Only35Auth.getAccessToken()
    if not token then
        error("Not authenticated. Please log in first.")
    end

    local headers = {
        { field = "Authorization", value = "Bearer " .. token },
        { field = "Content-Type", value = "application/vnd.api+json" },
        { field = "Accept", value = "application/vnd.api+json" },
    }

    local body = json.encode(data)

    -- LrHttp doesn't support PATCH directly, use POST with X-HTTP-Method-Override
    table.insert(headers, { field = "X-HTTP-Method-Override", value = "PATCH" })

    local result, responseHeaders = LrHttp.post(url, body, headers)

    if not result then
        error("Network error: no response from server")
    end

    local status = responseHeaders.status

    if status == 401 then
        if authRetryCount < maxAuthRetries and Only35Auth.refreshAccessToken() then
            return Only35API.patchJson(url, data, authRetryCount + 1)
        end
        error("Authentication expired. Please log in again.")
    end

    if status >= 400 then
        local errorMsg = "API error " .. status
        pcall(function()
            local errorBody = json.decode(result)
            if errorBody.message then
                errorMsg = errorMsg .. ": " .. errorBody.message
            end
        end)
        error(errorMsg)
    end

    if result and result ~= "" then
        return json.decode(result)
    end

    return nil
end

--- Make a GET request
-- @param url Full URL to GET
-- @param authRetryCount Number of 401 refresh attempts (internal)
-- @return table Parsed JSON response
function Only35API.get(url, authRetryCount)
    authRetryCount = authRetryCount or 0
    local maxAuthRetries = 1

    local token = Only35Auth.getAccessToken()
    if not token then
        error("Not authenticated. Please log in first.")
    end

    local headers = {
        { field = "Authorization", value = "Bearer " .. token },
        { field = "Accept", value = "application/vnd.api+json" },
    }

    local result, responseHeaders = LrHttp.get(url, headers)

    if not result then
        error("Network error: no response from server")
    end

    local status = responseHeaders.status

    if status == 401 then
        if authRetryCount < maxAuthRetries and Only35Auth.refreshAccessToken() then
            return Only35API.get(url, authRetryCount + 1)
        end
        error("Authentication expired. Please log in again.")
    end

    if status >= 400 then
        local errorMsg = "API error " .. status
        pcall(function()
            local errorBody = json.decode(result)
            if errorBody.message then
                errorMsg = errorMsg .. ": " .. errorBody.message
            end
        end)
        error(errorMsg)
    end

    if result and result ~= "" then
        return json.decode(result)
    end

    return nil
end

--------------------------------------------------------------------------------
-- S3 Upload
--------------------------------------------------------------------------------

--- Upload a file to S3 using a presigned URL
-- @param presignedUrl The presigned S3 PUT URL
-- @param filePath Local path to the file
-- @param uploadHeaders Headers required for the upload (from getUploadUrl)
function Only35API.uploadToS3(presignedUrl, filePath, uploadHeaders)
    -- Read file content
    local file = io.open(filePath, "rb")
    if not file then
        error("Could not open file: " .. filePath)
    end
    local content = file:read("*all")
    file:close()

    -- Build headers
    local headers = {}
    if uploadHeaders then
        for key, value in pairs(uploadHeaders) do
            table.insert(headers, { field = key, value = value })
        end
    end

    -- S3 PUT request
    local result, responseHeaders = LrHttp.post(presignedUrl, content, headers, "PUT")

    local status = responseHeaders.status

    if status ~= 200 and status ~= 204 then
        error("Failed to upload photo to storage. Status: " .. status)
    end
end

--------------------------------------------------------------------------------
-- API Methods
--------------------------------------------------------------------------------

--- Get a presigned upload URL for a photo
-- @param publishSettings The publish settings table
-- @param params Table with rollId, filename, contentType
-- @return table { url, headers, photographId, key }
function Only35API.getUploadUrl(publishSettings, params)
    local url = Only35Utils.apiUrl("UPLOAD_URL")

    -- JSON:API format
    local data = {
        data = {
            type = "upload-url-requests",
            attributes = {
                rollId = params.rollId,
                filename = params.filename,
                contentType = params.contentType or "image/jpeg",
            }
        }
    }

    local response = Only35API.postJson(url, data)

    -- Parse JSON:API response
    if not response or not response.data or not response.data.attributes then
        error("Invalid upload URL response from server")
    end

    local attrs = response.data.attributes

    return {
        url = attrs.uploadUrl,
        headers = attrs.headers or {},
        photographId = attrs.photographId or response.data.id,
        key = attrs.s3Key,
    }
end

--- Create a photograph record after upload
-- @param photographId The photograph ID from getUploadUrl
-- @param params Table with rollId, s3Key, filename, position
-- @return string The created photograph ID
function Only35API.createPhotograph(photographId, params)
    local url = Only35Utils.apiUrl("PHOTOGRAPHS")

    -- JSON:API format
    local data = {
        data = {
            type = "photographs",
            id = photographId,
            attributes = {
                url = params.s3Key,
                filename = params.filename,
                position = params.position or 0,
            },
            relationships = {
                roll = {
                    data = {
                        type = "rolls",
                        id = params.rollId,
                    }
                }
            }
        }
    }

    local response = Only35API.postJson(url, data)

    if response and response.data and response.data.id then
        return response.data.id
    end

    return photographId
end

--- Update an existing photograph's metadata
-- @param publishSettings The publish settings table
-- @param photographId The photograph ID to update
-- @param metadata Updated metadata table
function Only35API.updatePhotograph(publishSettings, photographId, metadata)
    local url = Only35Utils.apiUrl("PHOTOGRAPHS") .. "/" .. photographId

    local data = {
        stars = metadata.stars,
        selected = metadata.selected,
        keywords = metadata.keywords,
        description = metadata.description,
    }

    Only35API.patchJson(url, data)
end

--- Delete a photograph
-- @param publishSettings The publish settings table
-- @param photographId The photograph ID to delete
function Only35API.deletePhotograph(publishSettings, photographId)
    -- Use POST with X-HTTP-Method-Override for DELETE
    local url = Only35Utils.apiUrl("PHOTOGRAPHS") .. "/" .. photographId

    local token = Only35Auth.getAccessToken()
    if not token then
        error("Not authenticated")
    end

    local headers = {
        { field = "Authorization", value = "Bearer " .. token },
        { field = "X-HTTP-Method-Override", value = "DELETE" },
    }

    LrHttp.post(url, "", headers)
end

--- Get list of rolls (fetches all pages)
-- @param publishSettings The publish settings table
-- @return table Array of roll objects
function Only35API.getRolls(publishSettings)
    local allRolls = {}
    local url = Only35Utils.apiUrl("ROLLS") .. "?fields[rolls]=name,description,date&page[size]=100"

    while url do
        local response = Only35API.get(url)

        if response and response.data then
            for _, roll in ipairs(response.data) do
                table.insert(allRolls, roll)
            end
        end

        -- Check for next page in JSON:API links
        url = nil
        if response and response.links and response.links.next then
            url = response.links.next
        end
    end

    return allRolls
end

--- Create a new roll
-- @param publishSettings The publish settings table
-- @param name Name for the new roll
-- @param date Date for the roll (YYYY-MM-DD format)
-- @return table The created roll object
function Only35API.createRoll(publishSettings, name, date)
    local url = Only35Utils.apiUrl("ROLLS")

    -- Generate a UUID for the new roll
    local rollId = Only35Utils.generateUUID()

    -- JSON:API format
    local data = {
        data = {
            type = "rolls",
            id = rollId,
            attributes = {
                name = name,
                date = date,
            },
            relationships = {},
        }
    }

    local response = Only35API.postJson(url, data)

    -- Return the roll with its ID
    if response and response.data then
        return response.data
    end

    return response
end

--- Refresh the rolls list and update property table
-- @param propertyTable The property table to update with roll list
function Only35API.refreshRolls(propertyTable)
    local rolls = Only35API.getRolls(propertyTable)

    local rollItems = {}
    table.insert(rollItems, { title = "-- Select a Roll --", value = nil })

    for _, roll in ipairs(rolls) do
        -- JSON:API format: attributes are nested
        local attrs = roll.attributes or {}
        local name = attrs.name or roll.name or roll.id
        local isoDate = attrs.date

        -- Extract just the date part from ISO timestamp (e.g., "2009-10-07T22:00:00.000Z" -> "2009-10-07")
        local displayDate = nil
        if isoDate then
            displayDate = isoDate:match("^(%d%d%d%d%-%d%d%-%d%d)")
        end

        -- Display name with date if available
        local displayName = name
        if displayDate then
            displayName = name .. " (" .. displayDate .. ")"
        end

        table.insert(rollItems, {
            title = displayName,
            value = roll.id,
        })
    end

    propertyTable.availableRolls = rollItems
end

return Only35API
