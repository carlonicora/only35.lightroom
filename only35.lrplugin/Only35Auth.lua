--[[----------------------------------------------------------------------------
    Only35 OAuth Authentication Module

    Handles OAuth 2.0 authentication flow, token storage, and refresh.
------------------------------------------------------------------------------]]

local LrHttp = import 'LrHttp'
local LrDialogs = import 'LrDialogs'
local LrTasks = import 'LrTasks'
local LrPrefs = import 'LrPrefs'
local LrFunctionContext = import 'LrFunctionContext'
local LrBinding = import 'LrBinding'
local LrView = import 'LrView'

local Only35Utils = require 'Only35Utils'

local Only35Auth = {}

--------------------------------------------------------------------------------
-- PKCE State (module-level to persist between authorize and token exchange)
--------------------------------------------------------------------------------

local currentCodeVerifier = nil

--------------------------------------------------------------------------------
-- Token Storage Keys
--------------------------------------------------------------------------------

local TOKEN_KEYS = {
    ACCESS_TOKEN = "only35_access_token",
    REFRESH_TOKEN = "only35_refresh_token",
    TOKEN_EXPIRY = "only35_token_expiry",
    USER_ID = "only35_user_id",
    COMPANY_ID = "only35_company_id",
}

--------------------------------------------------------------------------------
-- Token Storage Functions
--------------------------------------------------------------------------------

--- Store tokens in Lightroom preferences
-- @param tokens Table with access_token, refresh_token, expires_in, user_id, company_id
function Only35Auth.storeTokens(tokens)
    local prefs = LrPrefs.prefsForPlugin()

    prefs[TOKEN_KEYS.ACCESS_TOKEN] = tokens.access_token
    prefs[TOKEN_KEYS.REFRESH_TOKEN] = tokens.refresh_token
    prefs[TOKEN_KEYS.TOKEN_EXPIRY] = os.time() + (tokens.expires_in or 3600)

    if tokens.user_id then
        prefs[TOKEN_KEYS.USER_ID] = tokens.user_id
    end
    if tokens.company_id then
        prefs[TOKEN_KEYS.COMPANY_ID] = tokens.company_id
    end

    Only35Utils.logInfo("Tokens stored successfully")
end

--- Clear all stored tokens (logout)
function Only35Auth.clearTokens()
    local prefs = LrPrefs.prefsForPlugin()

    prefs[TOKEN_KEYS.ACCESS_TOKEN] = nil
    prefs[TOKEN_KEYS.REFRESH_TOKEN] = nil
    prefs[TOKEN_KEYS.TOKEN_EXPIRY] = nil
    prefs[TOKEN_KEYS.USER_ID] = nil
    prefs[TOKEN_KEYS.COMPANY_ID] = nil

    Only35Utils.logInfo("Tokens cleared")
end

--- Check if current token is valid
-- @return boolean True if token exists and not expired (with 60s buffer)
function Only35Auth.isTokenValid()
    local prefs = LrPrefs.prefsForPlugin()
    local accessToken = prefs[TOKEN_KEYS.ACCESS_TOKEN]
    local expiry = prefs[TOKEN_KEYS.TOKEN_EXPIRY]

    if not accessToken or not expiry then
        return false
    end

    -- 60 second buffer before expiry
    return expiry > (os.time() + 60)
end

--- Get current access token, refreshing if needed
-- @return string Access token or nil if not authenticated
function Only35Auth.getAccessToken()
    local prefs = LrPrefs.prefsForPlugin()

    if Only35Auth.isTokenValid() then
        return prefs[TOKEN_KEYS.ACCESS_TOKEN]
    end

    -- Try to refresh
    if Only35Auth.refreshAccessToken() then
        return prefs[TOKEN_KEYS.ACCESS_TOKEN]
    end

    return nil
end

--- Get stored user ID
-- @return string User ID or nil
function Only35Auth.getUserId()
    local prefs = LrPrefs.prefsForPlugin()
    return prefs[TOKEN_KEYS.USER_ID]
end

--------------------------------------------------------------------------------
-- OAuth Flow
--------------------------------------------------------------------------------

--- Show dialog for user to enter authorization code
-- @return string Authorization code or nil if cancelled
local function showCodeEntryDialog()
    return LrFunctionContext.callWithContext("codeEntry", function(context)
        local viewFactory = LrView.osFactory()
        local propertyTable = LrBinding.makePropertyTable(context)
        propertyTable.authCode = ""

        local contents = viewFactory:column {
            bind_to_object = propertyTable,
            spacing = viewFactory:control_spacing(),

            viewFactory:static_text {
                title = "After logging in on Only35, you will see an authorization code.",
                wrap = true,
                width = 400,
            },

            viewFactory:static_text {
                title = "Please copy and paste that code below:",
                wrap = true,
                width = 400,
            },

            viewFactory:spacer { height = 10 },

            viewFactory:edit_field {
                value = LrView.bind("authCode"),
                width_in_chars = 40,
                immediate = true,
            },
        }

        local result = LrDialogs.presentModalDialog({
            title = "Enter Authorization Code",
            contents = contents,
            actionVerb = "Submit",
            cancelVerb = "Cancel",
        })

        if result == "ok" then
            local code = propertyTable.authCode
            if code and code ~= "" then
                return code:match("^%s*(.-)%s*$") -- trim whitespace
            end
        end

        return nil
    end)
end

--- Start the OAuth flow: open browser and show code entry dialog
-- @param propertyTable The publish settings property table to update
function Only35Auth.startOAuthFlow(propertyTable)
    LrTasks.startAsyncTask(function()
        Only35Utils.logInfo("Starting OAuth flow")

        -- Generate state parameter for CSRF protection
        local state = Only35Utils.generateRandomString(32)

        -- Generate PKCE code_verifier (43-128 characters, URL-safe)
        currentCodeVerifier = Only35Utils.generateRandomString(64)

        -- For plain method, code_challenge equals code_verifier
        local codeChallenge = currentCodeVerifier

        -- Build authorization URL with PKCE
        local authUrl = Only35Utils.webUrl("AUTHORIZE") .. "?" ..
            "client_id=" .. Only35Utils.CLIENT_ID ..
            "&redirect_uri=" .. Only35Utils.urlEncode(Only35Utils.REDIRECT_URI) ..
            "&response_type=code" ..
            "&scope=" .. Only35Utils.urlEncode(Only35Utils.SCOPES_STRING) ..
            "&state=" .. state ..
            "&code_challenge=" .. Only35Utils.urlEncode(codeChallenge) ..
            "&code_challenge_method=plain"

        Only35Utils.logInfo("Opening browser for authentication")
        LrHttp.openUrlInBrowser(authUrl)

        -- Show dialog for code entry
        local code = showCodeEntryDialog()

        if not code or code == "" then
            Only35Utils.logInfo("OAuth flow cancelled by user")
            return
        end

        Only35Utils.logInfo("Exchanging authorization code for tokens")

        -- Exchange code for tokens
        local tokens = Only35Auth.exchangeCodeForTokens(code)

        if tokens then
            Only35Auth.storeTokens(tokens)

            -- Update property table for UI
            propertyTable.isLoggedIn = true
            propertyTable.loginStatus = "Logged in"
            propertyTable.loginButtonTitle = "Logout"

            if tokens.user_id then
                propertyTable.loginStatus = "Logged in as user " .. tokens.user_id
            end

            LrDialogs.message("Success", "You have been logged in to Only35.", "info")
        end
    end)
end

--- Exchange authorization code for access tokens
-- @param code Authorization code from OAuth redirect
-- @return table Tokens table or nil on failure
function Only35Auth.exchangeCodeForTokens(code)
    local tokenUrl = Only35Utils.apiUrl("TOKEN")

    local body = "grant_type=authorization_code" ..
        "&code=" .. Only35Utils.urlEncode(code) ..
        "&client_id=" .. Only35Utils.CLIENT_ID ..
        "&redirect_uri=" .. Only35Utils.urlEncode(Only35Utils.REDIRECT_URI)

    -- Add PKCE code_verifier if we have one
    if currentCodeVerifier then
        body = body .. "&code_verifier=" .. Only35Utils.urlEncode(currentCodeVerifier)
        -- Clear the verifier after use
        currentCodeVerifier = nil
    end

    local headers = {
        { field = "Content-Type", value = "application/x-www-form-urlencoded" },
        { field = "Accept", value = "application/json" },
    }

    Only35Utils.logInfo("Posting to token endpoint: " .. tokenUrl)

    local result, responseHeaders = LrHttp.post(tokenUrl, body, headers)

    if not result then
        Only35Utils.logError("Token exchange failed: no response")
        LrDialogs.showError("Could not connect to Only35. Please check your internet connection.")
        return nil
    end

    local status = responseHeaders.status
    Only35Utils.logInfo("Token endpoint response status: " .. tostring(status))

    if status == 200 then
        local json = require 'json'
        local tokens = json.decode(result)
        Only35Utils.logInfo("Token exchange successful")
        return tokens
    else
        Only35Utils.logError("Token exchange failed with status: " .. tostring(status))
        Only35Utils.logError("Response: " .. tostring(result))
        LrDialogs.showError("Authentication failed. Please try again.\n\nError: " .. tostring(result))
        return nil
    end
end

--- Refresh the access token using the refresh token
-- @return boolean True if refresh successful
function Only35Auth.refreshAccessToken()
    local prefs = LrPrefs.prefsForPlugin()
    local refreshToken = prefs[TOKEN_KEYS.REFRESH_TOKEN]

    if not refreshToken then
        Only35Utils.logWarn("No refresh token available")
        return false
    end

    Only35Utils.logInfo("Refreshing access token")

    local tokenUrl = Only35Utils.apiUrl("TOKEN")

    local body = "grant_type=refresh_token" ..
        "&refresh_token=" .. Only35Utils.urlEncode(refreshToken) ..
        "&client_id=" .. Only35Utils.CLIENT_ID

    local headers = {
        { field = "Content-Type", value = "application/x-www-form-urlencoded" },
        { field = "Accept", value = "application/json" },
    }

    local result, responseHeaders = LrHttp.post(tokenUrl, body, headers)

    if not result then
        Only35Utils.logError("Token refresh failed: no response")
        Only35Auth.clearTokens()
        return false
    end

    local status = responseHeaders.status

    if status == 200 then
        local json = require 'json'
        local tokens = json.decode(result)
        Only35Auth.storeTokens(tokens)
        Only35Utils.logInfo("Token refresh successful")
        return true
    else
        Only35Utils.logError("Token refresh failed with status: " .. tostring(status))
        Only35Auth.clearTokens()
        return false
    end
end

--- Logout: clear tokens and optionally revoke on server
-- @param propertyTable The publish settings property table to update
function Only35Auth.logout(propertyTable)
    LrTasks.startAsyncTask(function()
        Only35Utils.logInfo("Logging out")

        local prefs = LrPrefs.prefsForPlugin()
        local accessToken = prefs[TOKEN_KEYS.ACCESS_TOKEN]

        -- Try to revoke token on server (best effort)
        if accessToken then
            local revokeUrl = Only35Utils.apiUrl("REVOKE")
            local body = "token=" .. Only35Utils.urlEncode(accessToken)
            local headers = {
                { field = "Content-Type", value = "application/x-www-form-urlencoded" },
            }

            -- Fire and forget - don't wait for response
            pcall(function()
                LrHttp.post(revokeUrl, body, headers)
            end)
        end

        -- Clear local tokens
        Only35Auth.clearTokens()

        -- Update UI
        propertyTable.isLoggedIn = false
        propertyTable.loginStatus = "Not logged in"
        propertyTable.loginButtonTitle = "Login"

        LrDialogs.message("Logged Out", "You have been logged out of Only35.", "info")
    end)
end

--- Check if user is currently logged in
-- @return boolean True if logged in with valid token
function Only35Auth.isLoggedIn()
    return Only35Auth.isTokenValid() or Only35Auth.refreshAccessToken()
end

return Only35Auth
