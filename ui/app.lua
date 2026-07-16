-- On-screen application: dashboard, buffer picker, glasses setup.
--
-- Redraws the whole screen each frame. NIDAS kept every window in a GPU buffer
-- and bitblt'd them, which is faster but needs a Tier 3 GPU; at this refresh
-- rate (a few frames per second) a plain redraw is cheap enough and keeps the
-- hardware requirement down.

local component = require("component")

local graphics = require("lib.graphics.graphics")
local palette = require("lib.graphics.colors")
local text = require("lib.utils.text")

local configuration = require("config")
local monitorLib = require("core.monitor")
local sources = require("core.sources")

local format = require("ui.format")
local panel = require("ui.panel")
local widgets = require("ui.widgets")

local app = {}
app.__index = app

local SCALE_ORDER = {"fast", "medium", "slow"}

function app.new(monitor, config)
    return setmetatable({
        monitor = monitor,
        config = config,
        page = "dashboard",
        running = true,
        dirty = true,
        status = nil,
    }, app)
end

function app:notify(message)
    self.status = message
end

function app:nextScale()
    local current = self.config.screen.graphScale
    for i, scale in ipairs(SCALE_ORDER) do
        if scale == current then
            self.config.screen.graphScale = SCALE_ORDER[i % #SCALE_ORDER + 1]
            return
        end
    end
    self.config.screen.graphScale = "medium"
end

function app:save()
    local ok, err = configuration.save(self.config)
    self:notify(ok and "Settings saved" or ("Save failed: " .. tostring(err)))
end

-- Pages ---------------------------------------------------------------------

function app:drawDashboard(width, rows, theme)
    local view = self.monitor:resolve(self.config.screen.source)
    if not view then
        graphics.text(2, 4, "No buffers configured — open Buffers", theme.muted, true)
        return
    end
    panel.header(2, 1, width - 2, view, theme, palette)
    panel.rule(2, 2, width - 2, theme)
    panel.draw(2, 4, width - 3, rows - 6, view, theme, palette, self.config.screen.graphScale)
end

function app:drawBuffers(width, rows, theme)
    graphics.text(2, 1, "Buffers", theme.primary, true)
    graphics.text(10, 1, "· click to show on screen, [on/off] to monitor", theme.muted, true)
    panel.rule(2, 2, width - 2, theme)

    local row = 4
    local views = self.monitor:list()
    local selected = self.config.screen.source

    for _, view in ipairs(views) do
        if row > rows - 3 then break end

        local isAggregate = view.id == monitorLib.AGGREGATE_ID
        local isSelected = (selected == view.id) or (selected == nil and isAggregate)

        -- text.fit, not :sub — a byte-slice can cut a UTF-8 name mid-character.
        local caption = string.format("%s %10s  %12s",
            text.fit(view.name or "?", 28),
            format.percent(view.percent),
            format.rate(view.net))

        -- The aggregate and the virtual wireless views are not components, so
        -- there is nothing to enable or disable for them.
        local entry
        if not isAggregate and view.kind ~= "wireless" then
            for _, candidate in ipairs(self.config.buffers) do
                if candidate.address == view.address then entry = candidate break end
            end
        end

        widgets.listItem(2, row, width - 14, caption, theme, isSelected, function()
            self.config.screen.source = isAggregate and nil or view.id
            self.dirty = true
        end, nil, entry and entry.enabled)

        if entry then
            widgets.button(width - 11, row, entry.enabled ~= false and " on" or "off",
                theme, function()
                    entry.enabled = not (entry.enabled ~= false)
                    self.dirty = true
                end, nil, entry.enabled ~= false)
        end
        row = row + 1
    end

    row = row + 1
    widgets.button(2, row, "Rescan components", theme, function()
        configuration.syncBuffers(self.config, sources.discover())
        self:notify("Rescanned")
        self.dirty = true
    end, nil, true)
end

function app:drawGlasses(width, rows, theme)
    graphics.text(2, 1, "AR Glasses", theme.primary, true)
    graphics.text(13, 1, "· pick what each pair of glasses displays", theme.muted, true)
    panel.rule(2, 2, width - 2, theme)

    local row = 4
    local found = false
    for address, componentType in component.list("glasses") do
        found = true
        if row > rows - 3 then break end
        local settings = configuration.glassesFor(self.config, address)

        graphics.text(2, row, address:sub(1, 8), theme.text, true)
        widgets.button(12, row, settings.enabled and "on" or "off", theme, function()
            settings.enabled = not settings.enabled
            self.dirty = true
        end, nil, settings.enabled)

        -- Cycling rotates through every view; otherwise the glasses are pinned
        -- to one source chosen below.
        widgets.button(22, row, settings.cycle and "cycle" or "pinned", theme, function()
            settings.cycle = not settings.cycle
            self.dirty = true
        end, nil, settings.cycle)

        local current = self.monitor:resolve(settings.source)
        widgets.button(36, row, "source: " .. ((current and current.name) or "?"), theme, function()
            -- Step through the available views in order.
            local views = self.monitor:list()
            local index = 1
            for i, view in ipairs(views) do
                if view.id == (settings.source or monitorLib.AGGREGATE_ID) then index = i break end
            end
            local nextView = views[index % #views + 1]
            settings.source = (nextView.id ~= monitorLib.AGGREGATE_ID) and nextView.id or nil
            self.dirty = true
        end, nil, not settings.cycle)

        row = row + 1
    end

    if not found then
        graphics.text(2, 4, "No glasses component found.", theme.muted, true)
        graphics.text(2, 5, "Link a Terminal Glasses Bridge to this computer.", theme.muted, true)
    end
end

-- Frame ---------------------------------------------------------------------

function app:footer(width, rows, theme)
    local row = rows
    panel.rule(2, rows - 1, width - 2, theme)

    local x = 2
    x = x + widgets.button(x, row, "Dashboard", theme, function()
        self.page = "dashboard" self.dirty = true
    end, nil, self.page == "dashboard") + 1

    x = x + widgets.button(x, row, "Buffers", theme, function()
        self.page = "buffers" self.dirty = true
    end, nil, self.page == "buffers") + 1

    x = x + widgets.button(x, row, "Glasses", theme, function()
        self.page = "glasses" self.dirty = true
    end, nil, self.page == "glasses") + 1

    x = x + widgets.button(x, row, "Graph: " .. (panel.SCALE_LABELS[self.config.screen.graphScale] or "?"),
        theme, function() self:nextScale() self.dirty = true end, nil, false) + 1

    x = x + widgets.button(x, row, "Save", theme, function() self:save() end, nil, false) + 1
    widgets.button(x, row, "Quit", theme, function() self.running = false end, nil, false)

    if self.status then
        graphics.text(width - text.len(self.status) - 1, row, self.status, theme.muted, true)
    end
end

function app:draw()
    local context = graphics.context()
    local width, rows = context.width, context.height
    local theme = self.config.theme

    widgets.reset()
    graphics.clear()

    if self.page == "buffers" then
        self:drawBuffers(width, rows, theme)
    elseif self.page == "glasses" then
        self:drawGlasses(width, rows, theme)
    else
        self:drawDashboard(width, rows, theme)
    end

    self:footer(width, rows, theme)
end

function app:onTouch(x, row)
    self.status = nil
    widgets.dispatch(math.floor(x), math.floor(row))
end

return app
