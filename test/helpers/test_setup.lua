-- Common test setup for Only35 Lightroom Plugin tests
-- Initializes the mock registry and sets up paths

local TestSetup = {}

function TestSetup.init()
    -- Add plugin source to path
    package.path = package.path .. ";./only35.lrplugin/?.lua"
    package.path = package.path .. ";./test/mocks/?.lua"
    package.path = package.path .. ";./test/helpers/?.lua"

    -- Setup mock registry
    local MockRegistry = require("lr_mock_registry")
    local LrLoggerMock = require("LrLoggerMock")

    MockRegistry.register("LrLogger", LrLoggerMock)
    MockRegistry.setupGlobalImport()

    return MockRegistry
end

return TestSetup
