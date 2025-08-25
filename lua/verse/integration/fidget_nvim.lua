local verse_ws = require("verse.workflow_server")
local proto = require("verse.workflow_server.protocol")

local M = {}

-- Building {{{
local build_handle

local function process_building()
  local state  = verse_ws.get_state()
  local building = (state.building ~= nil and not state.building.was_notified)
    or state.build_state == proto.BuildState.Building
  if building then
    local message
    if state.build_state == proto.BuildState.Building then
      message = "Building..."
    else
      message = "Requesting..."
    end
    if build_handle == nil then
      build_handle = require("fidget.progress.handle").create({
        title = "Build Verse",
        message = message,
        lsp_client = { name = "Verse Workflow" },
      })
    else
      build_handle:report({
        message = message
      })
    end
  elseif build_handle ~= nil then
    local messages = {
      [proto.BuildState.Errors] = "Failed",
      [proto.BuildState.NoBuild] = "Cancelled"
    }
    build_handle:report({
      message = messages[state.build_state] or "Done"
    })
    build_handle:finish()
    build_handle = nil
  end
end
--- }}}

-- Push Changes {{{
local PushChangesStage = {
  EndingGame = 0,
  Building = 1,
  UpdatingSession = 2,
}

local push_stage, push_handle

local function process_pushing_changes()
  local state  = verse_ws.get_state()
  local pushing_changes = state.pushing_changes
  if pushing_changes == nil or pushing_changes.done then
    if push_handle ~= nil then
      push_handle:report({
        message = "Done"
      })
      push_handle:finish()
      push_handle = nil
    end
    return
  end

  if pushing_changes.ending_game and push_stage ~= PushChangesStage.EndingGame then
    push_stage = PushChangesStage.EndingGame
    if push_handle ~= nil then
      push_handle:cancel()
    end
    local action_name
    if pushing_changes.verse_only then
      action_name = "Push Verse Changes"
    else
      action_name = "Push Changes"
    end
    push_handle = require("fidget.progress.handle").create({
      title = action_name,
      message = "Ending game...",
      lsp_client = { name = "Verse Workflow" },
    })
  elseif push_stage == PushChangesStage.EndingGame and not pushing_changes.ending_game then
    push_stage = PushChangesStage.Building
    push_handle:report({
      message = "Building..."
    })
  end

  if push_stage == PushChangesStage.Building and state.build_state ~= proto.BuildState.Building then
    push_stage = PushChangesStage.UpdatingSession
    push_handle:report({
      message = "Updating Session..."
    })
  end
end
-- }}}

function M.init()
  local augroup = vim.api.nvim_create_augroup("VerseIntegrationFidget", {
    clear = true,
  })
  vim.api.nvim_create_autocmd({ "User" }, {
    pattern = "VerseWorkflowStateUpdate",
    group = augroup,
    callback = function()
      process_building()
      process_pushing_changes()
    end,
  })
end

return M
