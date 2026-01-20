-- Mock for Lightroom's LrLogger
-- Returns a logger factory that creates no-op loggers

local LrLoggerMock = {}

setmetatable(LrLoggerMock, {
    __call = function(self, name)
        return {
            enable = function() end,
            trace = function() end,
            debug = function() end,
            info = function() end,
            warn = function() end,
            error = function() end,
            fatal = function() end,
        }
    end
})

return LrLoggerMock
