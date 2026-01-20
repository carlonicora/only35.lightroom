--[[----------------------------------------------------------------------------
    Only35 Publish Service Provider

    Main publish service for exporting photos to Only35.
    Handles the complete publish workflow including UI, export, and upload.
------------------------------------------------------------------------------]]

local LrView = import 'LrView'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'
local LrApplication = import 'LrApplication'
local LrFileUtils = import 'LrFileUtils'
local LrFunctionContext = import 'LrFunctionContext'

local Only35Utils = require 'Only35Utils'
local Only35Auth = require 'Only35Auth'
local Only35API = require 'Only35API'

-- Module-level storage for collection settings propertyTable
-- Needed because updateCollectionSettings doesn't receive propertyTable
local currentCollectionPropertyTable = nil

--------------------------------------------------------------------------------
-- Export/Publish Service Provider Definition
--------------------------------------------------------------------------------

local publishServiceProvider = {
    -- Service identification
    title = "Only35",
    supportsIncrementalPublish = true,
    small_icon = "icon.png",

    -- Supported features
    canExportVideo = false,
    hideSections = { "exportLocation", "fileNaming", "fileSettings", "imageSettings", "outputSharpening", "video" },
    allowFileFormats = { "JPEG" },
    allowColorSpaces = { "sRGB" },

    -- Export settings presets (for publish service dialog)
    exportPresetFields = {
        { key = "isLoggedIn", default = false },
        { key = "loginStatus", default = "Not logged in" },
        { key = "loginButtonTitle", default = "Login" },
        { key = "availableRolls", default = {} },
    },

    -- Collection settings (per-collection persistence)
    collectionSettings = {
        { key = "only35_roll_id", default = nil },
        { key = "only35_roll_date", default = "" },
        { key = "only35_create_new_roll", default = true },
        { key = "date_year", default = nil },
        { key = "date_month", default = nil },
        { key = "date_day", default = nil },
    },
}

--------------------------------------------------------------------------------
-- Export Settings (applied at export time)
--------------------------------------------------------------------------------

function publishServiceProvider.updateExportSettings(exportSettings)
    -- Force export settings at export time (overrides UI values)
    exportSettings.LR_format = "JPEG"
    exportSettings.LR_jpeg_quality = 0.80
    exportSettings.LR_size_doConstrain = true
    exportSettings.LR_size_maxWidth = 1920
    exportSettings.LR_size_maxHeight = 1920
    exportSettings.LR_size_resizeType = "longEdge"
    exportSettings.LR_outputSharpeningOn = true
    exportSettings.LR_outputSharpeningMedia = "screen"
    exportSettings.LR_outputSharpeningLevel = 2
    exportSettings.LR_export_colorSpace = "sRGB"
end

--------------------------------------------------------------------------------
-- Dialog Initialization
--------------------------------------------------------------------------------

function publishServiceProvider.startDialog(propertyTable)
    -- Initialize login state
    if Only35Auth.isLoggedIn() then
        propertyTable.isLoggedIn = true
        propertyTable.loginStatus = "Logged in"
        propertyTable.loginButtonTitle = "Logout"

        local userId = Only35Auth.getUserId()
        if userId then
            propertyTable.loginStatus = "Logged in as user " .. userId
        end

        -- Fetch rolls
        LrFunctionContext.postAsyncTaskWithContext("fetchRolls", function(context)
            -- Silently ignore errors on initial load
            context:addFailureHandler(function() end)
            Only35API.refreshRolls(propertyTable)
        end)
    else
        propertyTable.isLoggedIn = false
        propertyTable.loginStatus = "Not logged in"
        propertyTable.loginButtonTitle = "Login"
    end
end

--------------------------------------------------------------------------------
-- UI: Top of Dialog (Login Section)
--------------------------------------------------------------------------------

function publishServiceProvider.sectionsForTopOfDialog(viewFactory, propertyTable)
    return {
        {
            title = "Only35 Account",
            synopsis = LrView.bind("loginStatus"),

            viewFactory:row {
                spacing = viewFactory:control_spacing(),

                viewFactory:static_text {
                    title = "Status:",
                    width = 80,
                    alignment = "right",
                },

                viewFactory:static_text {
                    title = LrView.bind("loginStatus"),
                    fill_horizontal = 1,
                },
            },

            viewFactory:row {
                spacing = viewFactory:control_spacing(),

                viewFactory:static_text {
                    title = "",
                    width = 80,
                },

                viewFactory:push_button {
                    title = LrView.bind("loginButtonTitle"),
                    width = 100,
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

--------------------------------------------------------------------------------
-- UI: Collection Settings (Roll Selection)
--------------------------------------------------------------------------------

function publishServiceProvider.viewForCollectionSettings(viewFactory, propertyTable, info)
    Only35Utils.logInfo("viewForCollectionSettings called")

    -- Store reference for updateCollectionSettings callback
    currentCollectionPropertyTable = propertyTable

    -- Load existing settings from remoteUrl (stored as JSON)
    -- NOTE: info.collectionSettings does NOT work in Lightroom SDK
    -- We use remoteUrl as our persistence mechanism instead
    local collectionSettings = {}
    local publishedCollection = info.publishedCollection
    if publishedCollection then
        local remoteUrl = publishedCollection:getRemoteUrl()
        Only35Utils.logInfo("Loading settings from remoteUrl: " .. tostring(remoteUrl))

        if remoteUrl and remoteUrl ~= "" then
            local json = require 'json'
            local ok, decoded = pcall(json.decode, remoteUrl)
            if ok and decoded then
                collectionSettings = decoded
                Only35Utils.logInfo("Successfully loaded settings from remoteUrl")
            else
                Only35Utils.logWarn("Failed to parse remoteUrl as JSON")
            end
        end
    else
        Only35Utils.logInfo("No publishedCollection (new collection)")
    end

    -- Log existing values
    Only35Utils.logInfo("Existing only35_roll_date: " .. tostring(collectionSettings.only35_roll_date))
    Only35Utils.logInfo("Existing only35_roll_id: " .. tostring(collectionSettings.only35_roll_id))

    -- Initialize propertyTable with existing values or defaults
    propertyTable.only35_roll_id = collectionSettings.only35_roll_id or nil
    propertyTable.only35_create_new_roll = (collectionSettings.only35_create_new_roll ~= false) -- default true
    propertyTable.only35_roll_date = collectionSettings.only35_roll_date or ""
    propertyTable.date_year = collectionSettings.date_year or nil
    propertyTable.date_month = collectionSettings.date_month or nil
    propertyTable.date_day = collectionSettings.date_day or nil

    -- If we have a date string but no components, parse them
    if propertyTable.only35_roll_date ~= "" and not propertyTable.date_year then
        local year, month, day = propertyTable.only35_roll_date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
        propertyTable.date_year = year and tonumber(year) or nil
        propertyTable.date_month = month and tonumber(month) or nil
        propertyTable.date_day = day and tonumber(day) or nil
    end

    Only35Utils.logInfo("Initialized date_year: " .. tostring(propertyTable.date_year))
    Only35Utils.logInfo("Initialized date_month: " .. tostring(propertyTable.date_month))
    Only35Utils.logInfo("Initialized date_day: " .. tostring(propertyTable.date_day))

    -- Build year options (current year back to 1900)
    local currentYear = tonumber(os.date("%Y"))
    local yearItems = {{ title = "Year", value = nil }}
    for y = currentYear, 1900, -1 do
        table.insert(yearItems, { title = tostring(y), value = y })
    end
    propertyTable.yearItems = yearItems

    -- Build month options
    local monthNames = { "January", "February", "March", "April", "May", "June",
                         "July", "August", "September", "October", "November", "December" }
    local monthItems = {{ title = "Month", value = nil }}
    for m = 1, 12 do
        table.insert(monthItems, { title = monthNames[m], value = m })
    end
    propertyTable.monthItems = monthItems

    -- Build day options
    local dayItems = {{ title = "Day", value = nil }}
    for d = 1, 31 do
        table.insert(dayItems, { title = tostring(d), value = d })
    end
    propertyTable.dayItems = dayItems

    -- Initialize login state and available rolls
    if Only35Auth.isLoggedIn() then
        propertyTable.isLoggedIn = true
        propertyTable.availableRolls = {{ title = "Loading...", value = nil }}
        Only35Utils.logInfo("User is logged in, fetching rolls for collection dialog")

        -- Fetch rolls asynchronously
        LrFunctionContext.postAsyncTaskWithContext("fetchCollectionRolls", function(context)
            context:addFailureHandler(function(_, err)
                Only35Utils.logError("Failed to fetch rolls: " .. tostring(err))
                propertyTable.availableRolls = {{ title = "Error loading rolls", value = nil }}
            end)
            Only35API.refreshRolls(propertyTable)
        end)
    else
        propertyTable.isLoggedIn = false
        propertyTable.availableRolls = {{ title = "Please log in first", value = nil }}
        Only35Utils.logInfo("User is not logged in")
    end

    return viewFactory:column {
        bind_to_object = propertyTable,
        spacing = viewFactory:control_spacing(),

        viewFactory:row {
            spacing = viewFactory:control_spacing(),

            viewFactory:static_text {
                title = "Roll:",
                width = 80,
                alignment = "right",
            },

            viewFactory:popup_menu {
                items = LrView.bind("availableRolls"),
                value = LrView.bind("only35_roll_id"),
                width = 200,
                enabled = LrView.bind("isLoggedIn"),
            },

            viewFactory:push_button {
                title = "Refresh",
                enabled = LrView.bind("isLoggedIn"),
                action = function(button)
                    LrFunctionContext.postAsyncTaskWithContext("refreshRolls", function(context)
                        context:addFailureHandler(function(status, err)
                            LrDialogs.showError("Failed to refresh rolls: " .. tostring(err))
                        end)
                        Only35API.refreshRolls(propertyTable)
                    end)
                end,
            },
        },

        viewFactory:row {
            spacing = viewFactory:control_spacing(),

            viewFactory:static_text {
                title = "",
                width = 80,
            },

            viewFactory:checkbox {
                title = "Create new roll (uses collection name)",
                value = LrView.bind("only35_create_new_roll"),
                enabled = LrView.bind("isLoggedIn"),
            },
        },

        viewFactory:row {
            spacing = viewFactory:control_spacing(),

            viewFactory:static_text {
                title = "Date:",
                width = 80,
                alignment = "right",
            },

            viewFactory:popup_menu {
                items = LrView.bind("yearItems"),
                value = LrView.bind("date_year"),
                width = 70,
                enabled = LrView.bind({
                    keys = { "isLoggedIn", "only35_create_new_roll", "only35_roll_id" },
                    operation = function(binder, values, fromTable)
                        return values.isLoggedIn and values.only35_create_new_roll and not values.only35_roll_id
                    end,
                }),
            },

            viewFactory:popup_menu {
                items = LrView.bind("monthItems"),
                value = LrView.bind("date_month"),
                width = 90,
                enabled = LrView.bind({
                    keys = { "isLoggedIn", "only35_create_new_roll", "only35_roll_id" },
                    operation = function(binder, values, fromTable)
                        return values.isLoggedIn and values.only35_create_new_roll and not values.only35_roll_id
                    end,
                }),
            },

            viewFactory:popup_menu {
                items = LrView.bind("dayItems"),
                value = LrView.bind("date_day"),
                width = 50,
                enabled = LrView.bind({
                    keys = { "isLoggedIn", "only35_create_new_roll", "only35_roll_id" },
                    operation = function(binder, values, fromTable)
                        return values.isLoggedIn and values.only35_create_new_roll and not values.only35_roll_id
                    end,
                }),
            },
        },
    }
end

--------------------------------------------------------------------------------
-- Collection Settings Persistence
--------------------------------------------------------------------------------

function publishServiceProvider.updateCollectionSettings(publishSettings, info)
    -- This callback fires when user confirms the collection settings dialog
    -- IMPORTANT: publishedCollectionInfo.collectionSettings is NOT populated by Lightroom SDK
    -- So we use remoteUrl to store our settings as JSON instead

    Only35Utils.logInfo("updateCollectionSettings called")

    if not currentCollectionPropertyTable then
        Only35Utils.logError("No propertyTable reference available")
        return
    end

    local props = currentCollectionPropertyTable

    -- Build the date string
    local rollDate = ""
    if props.date_year and props.date_month and props.date_day then
        rollDate = string.format("%04d-%02d-%02d",
            props.date_year, props.date_month, props.date_day)
    end

    -- Create settings object
    local settings = {
        only35_roll_id = props.only35_roll_id,
        only35_roll_date = rollDate,
        only35_create_new_roll = props.only35_create_new_roll,
        date_year = props.date_year,
        date_month = props.date_month,
        date_day = props.date_day,
    }

    Only35Utils.logInfo("updateCollectionSettings: Saving settings via remoteUrl - date_year=" .. tostring(props.date_year) ..
        ", date_month=" .. tostring(props.date_month) ..
        ", date_day=" .. tostring(props.date_day) ..
        ", only35_roll_date=" .. rollDate)

    -- Store settings as JSON in the collection's remoteUrl
    local publishedCollection = info.publishedCollection
    if publishedCollection then
        local json = require 'json'
        local settingsJson = json.encode(settings)
        Only35Utils.logInfo("Storing settings JSON: " .. settingsJson)

        -- setRemoteUrl requires catalog write access
        local catalog = publishedCollection.catalog
        catalog:withWriteAccessDo("Save Collection Settings", function()
            publishedCollection:setRemoteUrl(settingsJson)
        end)
        Only35Utils.logInfo("Settings saved to remoteUrl successfully")
    else
        Only35Utils.logError("No publishedCollection available in updateCollectionSettings!")
    end
end

--------------------------------------------------------------------------------
-- Collection Behavior
--------------------------------------------------------------------------------

function publishServiceProvider.getCollectionBehaviorInfo(publishSettings)
    return {
        defaultCollectionName = "Only35 Photos",
        defaultCollectionCanBeDeleted = true,
        canAddCollection = true,
        maxCollectionSetDepth = 0, -- No collection sets, just collections
    }
end

--------------------------------------------------------------------------------
-- Metadata That Triggers Republish
--------------------------------------------------------------------------------

function publishServiceProvider.metadataThatTriggersRepublish(publishSettings)
    return {
        default = false,          -- Don't republish for most changes
        title = true,             -- Republish when title changes
        caption = true,           -- Republish when caption changes
        keywords = true,          -- Republish when keywords change
        gps = true,               -- Republish when GPS changes
        dateCreated = true,       -- Republish when date changes
        rating = true,            -- Republish when rating changes
        pickStatus = true,        -- Republish when pick status changes
    }
end

--------------------------------------------------------------------------------
-- Metadata Extraction Helper
--------------------------------------------------------------------------------

local function extractMetadata(photo)
    local metadata = {}

    -- Stars (rating 0-5)
    metadata.stars = photo:getRawMetadata("rating") or 0

    -- Selected (pick status)
    local pickStatus = photo:getRawMetadata("pickStatus")
    metadata.selected = (pickStatus == "flagged")

    -- Keywords (as array of strings)
    local keywords = photo:getRawMetadata("keywords") or {}
    local keywordStrings = {}
    for _, keyword in ipairs(keywords) do
        if type(keyword) == "string" then
            table.insert(keywordStrings, keyword)
        elseif keyword.getName then
            table.insert(keywordStrings, keyword:getName())
        end
    end
    metadata.keywords = keywordStrings

    -- Description (caption)
    metadata.description = photo:getFormattedMetadata("caption")

    -- Captured at (date)
    local dateCreated = photo:getRawMetadata("dateTimeOriginal")
    if dateCreated then
        metadata.capturedAt = dateCreated
    end

    -- Location (GPS)
    local gps = photo:getRawMetadata("gps")
    if gps and gps.latitude and gps.longitude then
        metadata.location = {
            latitude = gps.latitude,
            longitude = gps.longitude,
        }
    end

    return metadata
end

--------------------------------------------------------------------------------
-- Main Publish Function
--------------------------------------------------------------------------------

function publishServiceProvider.processRenderedPhotos(functionContext, exportContext)
    local exportSession = exportContext.exportSession
    local publishSettings = exportContext.propertyTable
    local collectionInfo = exportContext.publishedCollectionInfo
    local publishedCollection = exportContext.publishedCollection

    -- Read settings from remoteUrl (stored as JSON by updateCollectionSettings)
    local collectionSettings = {}
    if publishedCollection then
        local remoteUrl = publishedCollection:getRemoteUrl()
        Only35Utils.logInfo("Reading settings from remoteUrl: " .. tostring(remoteUrl))

        if remoteUrl and remoteUrl ~= "" then
            local json = require 'json'
            local ok, decoded = pcall(json.decode, remoteUrl)
            if ok and decoded then
                collectionSettings = decoded
                Only35Utils.logInfo("Successfully parsed settings from remoteUrl")
            else
                Only35Utils.logWarn("Failed to parse remoteUrl as JSON, using defaults")
            end
        else
            Only35Utils.logInfo("No remoteUrl set, using defaults")
        end
    end

    -- Log loaded settings
    Only35Utils.logInfo("=== Loaded Collection Settings ===")
    for k, v in pairs(collectionSettings) do
        Only35Utils.logInfo("  " .. tostring(k) .. " = " .. tostring(v))
    end
    Only35Utils.logInfo("=== End Collection Settings ===")

    -- Default create_new_roll to true if not explicitly set
    local createNewRoll = collectionSettings.only35_create_new_roll
    if createNewRoll == nil then
        createNewRoll = true
    end

    -- Get roll date from settings
    local rollDate = collectionSettings.only35_roll_date

    Only35Utils.logInfo("Collection settings: roll_id=" .. tostring(collectionSettings.only35_roll_id) ..
        ", create_new_roll=" .. tostring(createNewRoll) ..
        ", roll_date=" .. tostring(rollDate))

    -- Check authentication
    if not Only35Auth.isLoggedIn() then
        LrDialogs.showError("Please log in to Only35 before publishing.")
        return
    end

    -- Ensure we have a roll (read from collection settings first, then remoteId)
    local rollId = collectionSettings.only35_roll_id

    -- If no rollId from settings, try to get it from collection's remoteId (from previous publish)
    if not rollId then
        local publishedCollection = exportContext.publishedCollection
        if publishedCollection then
            rollId = publishedCollection:getRemoteId()
            if rollId then
                Only35Utils.logInfo("Using roll ID from collection remoteId: " .. rollId)
            end
        end
    end

    -- If still no rollId and we should create a new roll, do so
    if not rollId and createNewRoll then
        -- Create a new roll using the collection name
        local rollName = collectionInfo.name
        -- rollDate is already set above with fallback to components

        -- Validate required fields
        if not rollName or rollName == "" then
            LrDialogs.showError("Collection name is required for creating a roll.")
            return
        end

        if not rollDate or rollDate == "" then
            LrDialogs.showError("Please enter a roll date before publishing.")
            return
        end

        Only35Utils.logInfo("Creating new roll: " .. rollName .. " (" .. rollDate .. ")")

        local roll = Only35API.createRoll(publishSettings, rollName, rollDate)
        if roll and roll.id then
            rollId = roll.id
            Only35Utils.logInfo("Created roll with ID: " .. rollId)

            -- Store the roll ID in the collection's remoteId for future publishes
            local publishedCollection = exportContext.publishedCollection
            if publishedCollection then
                publishedCollection.catalog:withWriteAccessDo("Store Roll ID", function()
                    publishedCollection:setRemoteId(rollId)
                end)
                Only35Utils.logInfo("Stored roll ID as collection remoteId")
            end
        else
            LrDialogs.showError("Failed to create roll. Please try again.")
            return
        end
    end

    if not rollId then
        LrDialogs.showError("Please select a roll before publishing.")
        return
    end

    -- Set up progress
    local nPhotos = exportSession:countRenditions()
    local progressScope = exportContext:configureProgress({
        title = "Publishing to Only35",
    })

    Only35Utils.logInfo("Starting publish of " .. nPhotos .. " photos")

    -- Process each photo
    local successCount = 0
    local failureCount = 0
    local photoPosition = 0

    Only35Utils.logInfo("Entering renditions loop...")

    for i, rendition in exportSession:renditions() do
        Only35Utils.logInfo("Processing rendition " .. i)
        progressScope:setPortionComplete(i - 1, nPhotos)
        progressScope:setCaption("Publishing photo " .. i .. " of " .. nPhotos)

        if progressScope:isCanceled() then
            Only35Utils.logInfo("Publish cancelled by user")
            break
        end

        -- Wait for rendering to complete
        Only35Utils.logInfo("Waiting for render...")
        local success, pathOrMessage = rendition:waitForRender()
        Only35Utils.logInfo("Render complete: success=" .. tostring(success) .. ", path=" .. tostring(pathOrMessage))

        if success then
            local photo = rendition.photo

            -- Check if photo was previously published (use publish service's built-in tracking)
            local photoId = rendition.publishedPhotoId
            Only35Utils.logInfo("Existing photoId (from publishedPhotoId): " .. tostring(photoId))

            -- Note: Cannot use pcall here because LrHttp uses coroutines that cannot yield within pcall
            -- Instead, we use direct error checking and let errors propagate
            local publishSuccess = false
            local errorMessage = nil

            -- Step 1: Get upload URL
            Only35Utils.logInfo("Getting upload URL for roll " .. rollId)
            local uploadInfo = nil
            local getUrlOk, getUrlResult = LrTasks.pcall(function()
                return Only35API.getUploadUrl(publishSettings, {
                    rollId = rollId,
                    filename = LrPathUtils.leafName(pathOrMessage),
                    contentType = "image/jpeg",
                })
            end)

            if getUrlOk then
                uploadInfo = getUrlResult
            else
                errorMessage = "Failed to get upload URL: " .. tostring(getUrlResult)
                Only35Utils.logError(errorMessage)
            end

            -- Step 2: Upload to S3
            if uploadInfo then
                Only35Utils.logInfo("Got upload URL: " .. tostring(uploadInfo.url))
                Only35Utils.logInfo("Got photographId: " .. tostring(uploadInfo.photographId))
                Only35Utils.logInfo("Got s3Key: " .. tostring(uploadInfo.key))

                Only35Utils.logInfo("Uploading to S3...")
                local s3Ok, s3Err = LrTasks.pcall(function()
                    Only35API.uploadToS3(uploadInfo.url, pathOrMessage, uploadInfo.headers)
                end)

                if s3Ok then
                    Only35Utils.logInfo("S3 upload complete")

                    -- Extract metadata
                    local metadata = extractMetadata(photo)
                    Only35Utils.logInfo("Extracted metadata")

                    -- Step 3: Create or update photograph record
                    local recordOk, recordErr = LrTasks.pcall(function()
                        if photoId then
                            -- Update existing
                            Only35API.updatePhotograph(publishSettings, photoId, metadata)
                            Only35Utils.logInfo("Updated photo: " .. photoId)
                        else
                            -- Create new
                            photoPosition = photoPosition + 1
                            local newPhotoId = Only35API.createPhotograph(uploadInfo.photographId, {
                                rollId = rollId,
                                s3Key = uploadInfo.key,
                                filename = LrPathUtils.leafName(pathOrMessage),
                                position = photoPosition,
                            })

                            Only35Utils.logInfo("Created photo: " .. newPhotoId)
                            photoId = newPhotoId
                        end
                    end)

                    if recordOk then
                        -- Record as published
                        rendition:recordPublishedPhotoId(photoId)
                        successCount = successCount + 1
                        publishSuccess = true
                    else
                        errorMessage = "Failed to create photo record: " .. tostring(recordErr)
                        Only35Utils.logError(errorMessage)
                    end
                else
                    errorMessage = "Failed to upload to S3: " .. tostring(s3Err)
                    Only35Utils.logError(errorMessage)
                end
            end

            if not publishSuccess then
                rendition:uploadFailed(errorMessage or "Unknown error")
                failureCount = failureCount + 1
            end

            -- Clean up temporary file
            LrFileUtils.delete(pathOrMessage)
        else
            Only35Utils.logError("Render failed: " .. tostring(pathOrMessage))
            rendition:uploadFailed("Rendering failed")
            failureCount = failureCount + 1
        end
    end

    progressScope:done()

    -- Show summary
    if failureCount > 0 then
        LrDialogs.showError(
            "Published " .. successCount .. " photos to Only35.\n" ..
            failureCount .. " photos failed."
        )
    else
        Only35Utils.logInfo("Published " .. successCount .. " photos successfully")
    end
end

--------------------------------------------------------------------------------
-- Delete Photos
--------------------------------------------------------------------------------

function publishServiceProvider.deletePhotosFromPublishedCollection(publishSettings, arrayOfPhotoIds, deletedCallback, localCollectionId)
    for i, photoId in ipairs(arrayOfPhotoIds) do
        local ok, err = LrTasks.pcall(function()
            Only35API.deletePhotograph(publishSettings, photoId)
        end)

        if ok then
            Only35Utils.logInfo("Deleted photo: " .. photoId)
        else
            Only35Utils.logWarn("Failed to delete photo " .. photoId .. ": " .. tostring(err))
        end

        -- Always mark as deleted locally
        deletedCallback(photoId)
    end
end

--------------------------------------------------------------------------------
-- Collection Management
--------------------------------------------------------------------------------

function publishServiceProvider.renamePublishedCollection(publishSettings, info)
    -- Roll renaming would require an API call - for now, just update locally
    Only35Utils.logInfo("Collection renamed to: " .. info.name)
end

function publishServiceProvider.deletePublishedCollection(publishSettings, info)
    -- Could delete the roll on the server, but for safety just log
    Only35Utils.logInfo("Collection deleted: " .. info.name)
end

--------------------------------------------------------------------------------
-- Return the provider
--------------------------------------------------------------------------------

return publishServiceProvider
