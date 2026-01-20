# Design: Only35 Lightroom Plugin

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                  only35.lrplugin/                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐    ┌─────────────────────────────────┐│
│  │   Info.lua      │    │ Only35PublishServiceProvider.lua ││
│  │   (manifest)    │    │ (publish callbacks, UI)          ││
│  └─────────────────┘    └─────────────────────────────────┘│
│                                    │                        │
│                                    ▼                        │
│  ┌─────────────────┐    ┌─────────────────────────────────┐│
│  │ Only35Utils.lua │◄───│      Only35API.lua              ││
│  │ (constants)     │    │ (HTTP client, API calls)         ││
│  └─────────────────┘    └─────────────────────────────────┘│
│           │                        │                        │
│           ▼                        ▼                        │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                Only35Auth.lua                           ││
│  │         (OAuth flow, token management)                  ││
│  └─────────────────────────────────────────────────────────┘│
│                                                             │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ HTTPS
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      Only35 API                             │
│  /oauth/token, /photographs/upload-url, /photographs, etc.  │
└─────────────────────────────────────────────────────────────┘
```

---

## SDK Implementation Details

### SDK Modules Reference

| Module | Purpose |
|--------|---------|
| LrApplication | Access catalog, photos, and collections |
| LrDialogs | User dialogs, alerts, and prompts |
| LrErrors | Error handling and throwing |
| LrFunctionContext | Async operation context management |
| LrHttp | HTTP requests (GET, POST, PUT) |
| LrLogger | Debug logging to console |
| LrPathUtils | File path manipulation |
| LrPrefs | Plugin preferences storage (token storage) |
| LrTasks | Async task management and yielding |
| LrView | UI view factory for dialogs |
| LrBinding | Property binding for UI |
| LrPublishedCollection | Published collection operations |
| LrPublishedPhoto | Published photo metadata |

---

### Plugin Manifest (Info.lua)

```lua
return {
    LrSdkVersion = 13.0,
    LrSdkMinimumVersion = 10.0,
    LrToolkitIdentifier = "com.only35.lightroom",
    LrPluginName = "Only35",

    LrExportServiceProvider = {
        title = "Only35",
        file = "Only35PublishServiceProvider.lua",
    },

    LrPluginInfoProvider = "Only35InfoProvider.lua",

    VERSION = { major = 1, minor = 0, revision = 0, build = 1 },
}
```

**Required Fields:**
- `LrSdkVersion` - Target SDK version (13.0 for LR Classic 2024)
- `LrSdkMinimumVersion` - Minimum compatible SDK (10.0 for LR Classic 2020)
- `LrToolkitIdentifier` - Unique reverse-domain identifier
- `LrPluginName` - Display name in Plugin Manager

---

### File Structure

```
only35.lrplugin/
├── Info.lua                        # Plugin manifest
├── Only35PublishServiceProvider.lua # Publish service callbacks
├── Only35API.lua                   # HTTP client, API calls
├── Only35Auth.lua                  # OAuth flow, token management
└── Only35Utils.lua                 # Logging, constants, helpers
```

| File | Responsibility |
|------|----------------|
| Info.lua | Plugin manifest, service registration, version |
| Only35PublishServiceProvider.lua | All publish service callbacks, export settings, UI sections |
| Only35API.lua | HTTP requests via LrHttp, JSON encode/decode, API error handling |
| Only35Auth.lua | OAuth flow orchestration, token storage in LrPrefs, token refresh |
| Only35Utils.lua | Logger setup, constants (API URL, client ID), utility functions |

---

### Publish Service Callbacks

#### Required Callbacks

| Callback | Signature | Purpose |
|----------|-----------|---------|
| `processRenderedPhotos` | `(functionContext, exportContext)` | Upload rendered photos to S3 |
| `getCollectionBehaviorInfo` | `(publishSettings)` | Define default collection name, nesting |
| `metadataThatTriggersRepublish` | `(publishSettings)` | Return metadata fields that trigger re-upload |
| `deletePhotosFromPublishedCollection` | `(publishSettings, arrayOfPhotoIds, deletedCallback)` | Handle photo deletion from roll |
| `renamePublishedCollection` | `(publishSettings, info)` | Sync collection rename to roll |
| `deletePublishedCollection` | `(publishSettings, info)` | Delete roll when collection deleted |

#### Optional Callbacks

| Callback | Signature | Purpose |
|----------|-----------|---------|
| `startDialog` | `(propertyTable)` | Initialize settings dialog state |
| `sectionsForTopOfDialog` | `(viewFactory, propertyTable)` | Add login/account UI section |
| `viewForCollectionSettings` | `(viewFactory, propertyTable, info)` | Roll selection UI |
| `canExportVideo` | `()` | Return false (Only35 is photos only) |

#### processRenderedPhotos Implementation Pattern

```lua
processRenderedPhotos = function(functionContext, exportContext)
    local exportSession = exportContext.exportSession
    local publishSettings = exportContext.propertyTable

    local nPhotos = exportSession:countRenditions()
    local progressScope = exportContext:configureProgress({
        title = "Publishing to Only35",
    })

    for i, rendition in exportSession:renditions() do
        progressScope:setPortionComplete(i - 1, nPhotos)

        local success, pathOrMessage = rendition:waitForRender()
        if success then
            local photo = rendition.photo
            local photoId = photo:getPropertyForPlugin(_PLUGIN, "only35_photo_id")

            -- Get pre-signed URL
            local uploadUrl = Only35API.getUploadUrl(publishSettings, {
                rollId = publishSettings.only35_roll_id,
                filename = LrPathUtils.leafName(pathOrMessage),
                contentType = "image/jpeg",
            })

            -- Upload to S3
            Only35API.uploadToS3(uploadUrl.url, pathOrMessage, uploadUrl.headers)

            -- Create/update photograph record
            local metadata = {
                stars = photo:getRawMetadata("rating"),
                selected = photo:getRawMetadata("pickStatus") == "picked",
                keywords = photo:getRawMetadata("keywords"),
                description = photo:getFormattedMetadata("caption"),
            }

            if photoId then
                Only35API.updatePhotograph(publishSettings, photoId, metadata)
            else
                local newPhotoId = Only35API.createPhotograph(publishSettings, uploadUrl.photographId, metadata)
                photo:setPropertyForPlugin(_PLUGIN, "only35_photo_id", newPhotoId)
            end

            rendition:recordPublishedPhotoId(uploadUrl.photographId)
        end
    end
end
```

#### metadataThatTriggersRepublish Implementation

```lua
metadataThatTriggersRepublish = function(publishSettings)
    return {
        default = false,
        title = true,
        caption = true,
        keywords = true,
        gps = true,
        dateCreated = true,
        rating = true,
        pickStatus = true,
    }
end
```

---

### Token Storage (LrPrefs)

```lua
local LrPrefs = import 'LrPrefs'
local prefs = LrPrefs.prefsForPlugin()

-- Store tokens after OAuth exchange
prefs.only35_access_token = accessToken
prefs.only35_refresh_token = refreshToken
prefs.only35_token_expiry = os.time() + expiresIn
prefs.only35_user_id = userId
prefs.only35_company_id = companyId

-- Check token validity
local function isTokenValid()
    return prefs.only35_access_token ~= nil
        and prefs.only35_token_expiry > os.time() + 60  -- 60s buffer
end

-- Clear tokens on logout
local function clearTokens()
    prefs.only35_access_token = nil
    prefs.only35_refresh_token = nil
    prefs.only35_token_expiry = nil
    prefs.only35_user_id = nil
    prefs.only35_company_id = nil
end
```

---

### HTTP Client Patterns (LrHttp)

#### POST Request with JSON Body

```lua
local LrHttp = import 'LrHttp'
local json = require 'json'  -- Lightroom includes a JSON library

local function postJson(url, data, token)
    local headers = {
        { field = "Authorization", value = "Bearer " .. token },
        { field = "Content-Type", value = "application/json" },
        { field = "Accept", value = "application/vnd.api+json" },
    }

    local body = json.encode(data)
    local result, responseHeaders = LrHttp.post(url, body, headers)

    if not result then
        error("Network error: no response")
    end

    local statusCode = responseHeaders.status
    if statusCode >= 400 then
        local errorBody = json.decode(result)
        error("API error " .. statusCode .. ": " .. (errorBody.message or "Unknown"))
    end

    return json.decode(result)
end
```

#### PUT Request for S3 Upload

```lua
local function uploadToS3(presignedUrl, filePath, headers)
    local file = io.open(filePath, "rb")
    local content = file:read("*all")
    file:close()

    local httpHeaders = {}
    for key, value in pairs(headers) do
        table.insert(httpHeaders, { field = key, value = value })
    end

    local result, responseHeaders = LrHttp.post(presignedUrl, content, httpHeaders, "PUT")

    if responseHeaders.status ~= 200 then
        error("S3 upload failed: " .. responseHeaders.status)
    end
end
```

#### GET Request

```lua
local function get(url, token)
    local headers = {
        { field = "Authorization", value = "Bearer " .. token },
        { field = "Accept", value = "application/vnd.api+json" },
    }

    local result, responseHeaders = LrHttp.get(url, headers)

    if responseHeaders.status >= 400 then
        error("API error: " .. responseHeaders.status)
    end

    return json.decode(result)
end
```

---

### Export Settings Specification

```lua
exportPresetFields = {
    { key = "only35_roll_id", default = nil },
    { key = "only35_roll_name", default = nil },
    { key = "only35_create_new_roll", default = true },
},

-- Default export/render settings
hideSections = { "exportLocation", "fileNaming" },  -- Hide irrelevant sections

exportServiceExportSettings = {
    LR_format = "JPEG",
    LR_jpeg_quality = 0.92,
    LR_jpeg_useLimitSize = false,
    LR_size_doConstrain = true,
    LR_size_maxWidth = 4096,
    LR_size_maxHeight = 4096,
    LR_size_resizeType = "longEdge",
    LR_outputSharpeningOn = true,
    LR_outputSharpeningMedia = "screen",
    LR_outputSharpeningLevel = 2,
    LR_useWatermark = false,
    LR_metadata_keywordOptions = "lightroomHierarchical",
    LR_embeddedMetadataOption = "all",
    LR_export_colorSpace = "sRGB",
},
```

---

### UI Dialog Specification

#### Settings Dialog (sectionsForTopOfDialog)

```lua
sectionsForTopOfDialog = function(viewFactory, propertyTable)
    local LrBinding = import 'LrBinding'

    return {
        {
            title = "Only35 Account",
            synopsis = LrBinding.bind("loginStatusSynopsis"),

            viewFactory:row {
                viewFactory:static_text {
                    title = "Status:",
                    width = 80,
                },
                viewFactory:static_text {
                    title = LrView.bind("loginStatus"),
                    fill_horizontal = 1,
                },
            },

            viewFactory:row {
                viewFactory:push_button {
                    title = LrView.bind("loginButtonTitle"),  -- "Login" or "Logout"
                    action = function(button)
                        if propertyTable.isLoggedIn then
                            Only35Auth.logout(propertyTable)
                        else
                            Only35Auth.startOAuthFlow(propertyTable)
                        end
                    end,
                },
            },
        },
    }
end
```

#### Collection Settings (viewForCollectionSettings)

```lua
viewForCollectionSettings = function(viewFactory, propertyTable, info)
    local LrBinding = import 'LrBinding'

    return viewFactory:column {
        viewFactory:row {
            viewFactory:static_text {
                title = "Roll:",
                width = 80,
            },
            viewFactory:popup_menu {
                items = LrView.bind("availableRolls"),
                value = LrView.bind("only35_roll_id"),
                width = 200,
            },
            viewFactory:push_button {
                title = "Refresh",
                action = function()
                    Only35API.refreshRolls(propertyTable)
                end,
            },
        },
        viewFactory:row {
            viewFactory:checkbox {
                title = "Create new roll if none selected",
                value = LrView.bind("only35_create_new_roll"),
            },
        },
    }
end
```

#### OAuth Code Entry Dialog

```lua
local function showCodeEntryDialog()
    local LrDialogs = import 'LrDialogs'
    local LrFunctionContext = import 'LrFunctionContext'

    return LrFunctionContext.callWithContext("codeEntry", function(context)
        local propertyTable = LrBinding.makePropertyTable(context)
        propertyTable.authCode = ""

        local result = LrDialogs.presentModalDialog({
            title = "Enter Authorization Code",
            contents = viewFactory:column {
                viewFactory:static_text {
                    title = "Please paste the authorization code from your browser:",
                },
                viewFactory:edit_field {
                    value = LrView.bind("authCode"),
                    width = 300,
                },
            },
            actionVerb = "Submit",
        })

        if result == "ok" then
            return propertyTable.authCode
        end
        return nil
    end)
end
```

---

### OAuth Flow Implementation

```lua
-- Only35Auth.lua

local LrHttp = import 'LrHttp'
local LrDialogs = import 'LrDialogs'
local LrTasks = import 'LrTasks'
local LrPrefs = import 'LrPrefs'

local Only35Auth = {}

local CLIENT_ID = "lightroom"
local REDIRECT_URI = "https://only35.com/oauth/success"
local AUTH_URL = "https://only35.com/oauth/authorize"
local TOKEN_URL = "https://api.only35.com/oauth/token"
local SCOPES = "photos:read photos:write rolls:read rolls:write"

function Only35Auth.startOAuthFlow(propertyTable)
    LrTasks.startAsyncTask(function()
        -- Generate state for CSRF protection
        local state = Only35Utils.generateRandomString(32)

        -- Build authorization URL
        local authUrl = AUTH_URL .. "?" ..
            "client_id=" .. CLIENT_ID ..
            "&redirect_uri=" .. LrHttp.urlEncode(REDIRECT_URI) ..
            "&response_type=code" ..
            "&scope=" .. LrHttp.urlEncode(SCOPES) ..
            "&state=" .. state

        -- Open browser
        LrHttp.openUrlInBrowser(authUrl)

        -- Show code entry dialog
        local code = showCodeEntryDialog()
        if not code or code == "" then
            return  -- User cancelled
        end

        -- Exchange code for tokens
        local tokens = Only35Auth.exchangeCodeForTokens(code)
        if tokens then
            Only35Auth.storeTokens(tokens)
            propertyTable.isLoggedIn = true
            propertyTable.loginStatus = "Logged in as " .. tokens.userId
            propertyTable.loginButtonTitle = "Logout"
        end
    end)
end

function Only35Auth.exchangeCodeForTokens(code)
    local body = "grant_type=authorization_code" ..
        "&code=" .. code ..
        "&client_id=" .. CLIENT_ID ..
        "&redirect_uri=" .. LrHttp.urlEncode(REDIRECT_URI)

    local headers = {
        { field = "Content-Type", value = "application/x-www-form-urlencoded" },
    }

    local result, responseHeaders = LrHttp.post(TOKEN_URL, body, headers)

    if responseHeaders.status == 200 then
        return json.decode(result)
    else
        LrDialogs.showError("Authentication failed. Please try again.")
        return nil
    end
end

function Only35Auth.refreshAccessToken()
    local prefs = LrPrefs.prefsForPlugin()
    local refreshToken = prefs.only35_refresh_token

    if not refreshToken then
        return false
    end

    local body = "grant_type=refresh_token" ..
        "&refresh_token=" .. refreshToken ..
        "&client_id=" .. CLIENT_ID

    local headers = {
        { field = "Content-Type", value = "application/x-www-form-urlencoded" },
    }

    local result, responseHeaders = LrHttp.post(TOKEN_URL, body, headers)

    if responseHeaders.status == 200 then
        local tokens = json.decode(result)
        Only35Auth.storeTokens(tokens)
        return true
    else
        Only35Auth.clearTokens()
        return false
    end
end

return Only35Auth
```

---

### Constants and Configuration

```lua
-- Only35Utils.lua

local Only35Utils = {}

Only35Utils.API_BASE_URL = "https://api.only35.com"
Only35Utils.WEB_BASE_URL = "https://only35.com"
Only35Utils.CLIENT_ID = "lightroom"
Only35Utils.REDIRECT_URI = "https://only35.com/oauth/success"

-- Scopes
Only35Utils.SCOPES = {
    "photos:read",
    "photos:write",
    "rolls:read",
    "rolls:write",
}

-- API Endpoints
Only35Utils.ENDPOINTS = {
    AUTHORIZE = "/oauth/authorize",
    TOKEN = "/oauth/token",
    REVOKE = "/oauth/revoke",
    UPLOAD_URL = "/photographs/upload-url",
    PHOTOGRAPHS = "/photographs",
    ROLLS = "/rolls",
}

function Only35Utils.generateRandomString(length)
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local result = ""
    for i = 1, length do
        local idx = math.random(1, #chars)
        result = result .. chars:sub(idx, idx)
    end
    return result
end

return Only35Utils
```

---

## API Contract Summary

### Required Endpoints (implemented by Only35 API)

| Endpoint | Method | Purpose |
|----------|--------|---------|
| /oauth/authorize | GET | Start authorization flow (browser) |
| /oauth/token | POST | Exchange code/refresh tokens |
| /oauth/revoke | POST | Revoke tokens on logout |
| /photographs/upload-url | POST | Get pre-signed S3 URL |
| /photographs | POST | Create photograph record |
| /photographs/{id} | PATCH | Update photograph (re-publish) |
| /rolls | GET | List rolls for roll selection |
| /rolls | POST | Create new roll |

### Required Scopes

| Scope | Description |
|-------|-------------|
| photos:read | Read photograph data |
| photos:write | Create/update photographs |
| rolls:read | Read roll data |
| rolls:write | Create/update rolls |

### Metadata Mapping

| Lightroom Field | Only35 Field | Notes |
|-----------------|--------------|-------|
| rating (0-5) | stars | Direct mapping |
| pickStatus | selected | flagged->true, else->false |
| keywords | keywords[] | Array of strings |
| caption | description | Optional |
| dateCreated | capturedAt | EXIF date |
| gps | location | Latitude/longitude |
