--[[----------------------------------------------------------------------------
    Only35 Plugin Info Provider

    Provides plugin information for Lightroom's Plugin Manager.
------------------------------------------------------------------------------]]

return {
    sectionsForBottomOfDialog = function(viewFactory, propertyTable)
        local LrHttp = import 'LrHttp'

        return {
            {
                title = "About Only35",

                viewFactory:row {
                    viewFactory:static_text {
                        title = "Only35 Lightroom Plugin v1.0.0",
                        font = "<system/bold>",
                    },
                },

                viewFactory:row {
                    viewFactory:static_text {
                        title = "Publish your photos directly to Only35.",
                    },
                },

                viewFactory:row {
                    viewFactory:push_button {
                        title = "Visit Only35",
                        action = function()
                            -- LrHttp.openUrlInBrowser("https://only35.test:3801")
                            LrHttp.openUrlInBrowser("https://only35.app")
                        end,
                    },
                    viewFactory:push_button {
                        title = "Get Help",
                        action = function()
                            -- LrHttp.openUrlInBrowser("https://only35.test:3801/help/lightroom")
                            LrHttp.openUrlInBrowser("https://only35.app/help/lightroom")
                        end,
                    },
                },
            },
        }
    end,
}
