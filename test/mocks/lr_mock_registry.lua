-- Mock Registry for Lightroom SDK
-- Intercepts the global `import` function to return mock objects

local MockRegistry = {}
MockRegistry._mocks = {}

function MockRegistry.setupGlobalImport()
    _G.import = function(moduleName)
        if MockRegistry._mocks[moduleName] then
            return MockRegistry._mocks[moduleName]
        end
        -- Return empty table for unregistered mocks (graceful fallback)
        return {}
    end
end

function MockRegistry.register(moduleName, mockModule)
    MockRegistry._mocks[moduleName] = mockModule
end

function MockRegistry.reset()
    MockRegistry._mocks = {}
end

return MockRegistry
