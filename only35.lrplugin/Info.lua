--[[----------------------------------------------------------------------------
    Only35 Lightroom Plugin

    Publish Service plugin for uploading photos to Only35.
    Supports OAuth 2.0 authentication and metadata sync.
------------------------------------------------------------------------------]]

return {
    -- SDK version requirements
    LrSdkVersion = 13.0,
    LrSdkMinimumVersion = 10.0,

    -- Plugin identification
    LrToolkitIdentifier = "app.only35.lightroom",
    LrPluginName = "Only35",
    LrPluginIcon = "icon.png",

    -- Export/Publish Service registration
    LrExportServiceProvider = {
        title = "Only35",
        file = "Only35PublishServiceProvider.lua",
    },

    -- Plugin info provider for About dialog
    LrPluginInfoProvider = "Only35InfoProvider.lua",

    -- Version information
    VERSION = {
        major = 1,
        minor = 1,
        revision = 0,
        build = 1,
        display = "1.1.0",
    },
}
