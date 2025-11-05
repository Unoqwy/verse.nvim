local Client = require("verse.workflow_server.client")
local proto = require("verse.workflow_server.protocol")

local verse = require("verse")
local debug_enabled = verse.debug_enabled
local notify = verse.create_notifier("Verse Workflow")
local log_level = vim.log.levels

local SERVER_STATE_PROPAGATION_LEEWAY_MS = 1500

--- The state of the workflow server.
--- @class verse.workflow_server.State
---
--- Current project build state.
--- @field build_state? verse.workflow_server.protocol.BuildState
--- Whether Push Verse Changes is available.
--- @field can_push_verse_changes? boolean
---
--- State of the in-progress Build Verse action.
--- @field building? verse.workflow_server.State.Building
--- State of the in-progress Push Changes action.
--- @field pushing_changes? verse.workflow_server.State.PushingChanges

--- @class verse.workflow_server.State.Building
---
--- @field was_notified boolean
--- @field done boolean
--- @field error? string
--- @field result? verse.workflow_server.State.Building.Result
---
--- @class verse.workflow_server.State.Building.Result
--- @field message string Build output
--- @field num_warnings integer Number of warnings
--- @field num_errors integer Number of errors

--- @class verse.workflow_server.State.PushingChanges
---
--- @field verse_only boolean
--- @field ending_game boolean
--- @field done boolean
--- @field error? string Error message
--- @field success? string Success message

local M = {}
local req_queue = {}

--- @type verse.workflow_server.State
local state = {}

--- Returns the current workflow server state.
--- @return verse.workflow_server.State
function M.get_state()
  return state
end

local function emit_state_update()
  vim.api.nvim_exec_autocmds("User", {
    pattern = "VerseWorkflowStateUpdate"
  })
end

--- Connects to the Verse Workflow Server.
function M.connect()
  if M._client ~= nil and M._client:is_alive() then
    notify("Already connected to Verse Workflow Server")
    return
  end

  local config = require("verse").get_config().workflow_server or {}
  local address = config.default_address or "127.0.0.1"
  local port = config.default_port or 1962

  req_queue = {}
  M._client = Client.connect_new(address, port, {
    on_connect = function()
      notify("Connected to Verse Workflow Server")

      require("verse")._init_workflow_integration()

      local reqs = req_queue
      req_queue = {}
      for _, req in ipairs(reqs) do
        M._process_request(req)
      end
    end,
    on_disconnect = function(err)
      state = {}
      emit_state_update()

      if err ~= nil then
        notify("Disconnected from Verse Workflow Server: " .. err, log_level.WARN)
      else
        notify("Disconnected from Verse Workflow Server")
      end
    end,
    on_notification = M._handle_notification,
  })
end

--- Disconnects from the Verse Workflow Server if connected.
function M.disconnect()
  if M._client ~= nil then
    M._client:shutdown()
  end
end

--- @class verse.workflow_server.Request
---
--- Command name
--- @field cmd string
--- Optional command parameters
--- @field params? any
--- Callback when the request was actually sent
--- @field on_send? fun()
--- Callback when the server sends a response
--- @field on_response? fun(err:any, result:any)

--- @param req verse.workflow_server.Request
function M._process_request(req)
  local on_response = nil
  if req.on_response ~= nil then
    on_response = vim.schedule_wrap(req.on_response)
  end
  local sent = M._client:send_message(proto.MessageType.Request, req.cmd, req.params, on_response)
  if req.on_send ~= nil and sent ~= nil then
    vim.schedule(req.on_send)
  end
end

--- Sends a request to the workflow server.
--- @param req verse.workflow_server.Request
function M._send_request(req)
  if M._client == nil or not M._client:is_alive() then
    local auto_connect = require("verse").get_config().workflow_server.auto_connect
    if not auto_connect then
      notify("Can't send request to Verse Workflow Server: client not connected", log_level.WARN)
    end

    M.connect()
  end
  if M._client.state == Client.ConnectionState.Connected then
    M._process_request(req)
  elseif M._client:is_alive() then
    table.insert(req_queue, req)
  end
end

--- @class verse.workflow_server.BuildOpts
--- @field callback? fun(built:boolean) Callback when building completes
--- @field no_request_print? boolean

--- Requests the server to build verse.
--- @param opts? verse.workflow_server.BuildOpts
function M.build(opts)
  if state.building and not state.building.done then
    notify("Already building Verse code")
    return
  end

  opts = opts or {}

  M._send_request({
    cmd = "compileProject",
    on_send = function()
      state.building = {
        was_notified = false,
        done = false,
      }
      emit_state_update()

      if opts.no_request_print ~= true then
        notify("Verse code build requested")
      end
    end,
    on_response = function(err, result)
      state.building.done = true
      state.building.error = err
      if result ~= nil then
        state.building.result = {
          message = result.message,
          num_errors = result["numErrors"] or 0,
          num_warnings = result["numWarnings"] or 0,
        }
      end
      emit_state_update()

      --- @diagnostic disable-next-line:redefined-local
      local result = state.building.result
      state.building = nil
      emit_state_update()

      if result == nil then
        notify("Verse code build failed: " .. err, log_level.WARN)
      elseif result.num_errors > 0 then
        notify("Verse code built with " .. result.num_errors .. " errors", log_level.WARN)
      elseif result.num_warnings > 0 then
        notify("Verse code built with " .. result.num_warnings .. " warnings", log_level.WARN)
      else
        notify("Verse code built successfully")
      end

      if opts.callback ~= nil then
        local built = result ~= nil and result.num_errors == 0
        opts.callback(built)
      end
    end,
  })
end

--- @class verse.workflow_server.PushChangesOpts
---
--- Whether to only push Verse changes. If false, pushes all changes.
--- @field verse_only? boolean
--- @field skip_prebuild? boolean

--- Requests the server to push changes
--- @param opts? verse.workflow_server.PushChangesOpts
function M.push_changes(opts)
  if state.pushing_changes and not state.pushing_changes.done then
    notify("Already pushing changes")
    return
  end

  opts = opts or {}
  local verse_only = true
  if type(opts.verse_only) == "boolean" then
    verse_only = opts.verse_only or false
  end

  local action_name
  if verse_only then
    action_name = "Push Verse Changes"
  else
    action_name = "Push Changes"
  end

  if not state.can_push_verse_changes then
    if not opts.skip_prebuild then
      local callback = function(built)
        if built then
          local timer = vim.uv.new_timer()
          if timer == nil then
            return
          end
          timer:start(SERVER_STATE_PROPAGATION_LEEWAY_MS, 0, function()
            timer:stop()
            timer:close()
            M.push_changes(vim.tbl_extend("force", opts, { skip_prebuild = true }))
          end)
        end
      end

      notify("Requesting Verse Build before " .. action_name)
      M.build({
        callback = callback,
        no_request_print = true,
      })
    else
      -- TODO : This requirement can be removed once the workflow server gets fixed and it
      --        starts consistently sending a response to pushChanges requests again.
      notify("Cannot " .. action_name .. " according to server", log_level.WARN)
    end
    return
  end

  M._send_request({
    cmd = "pushChanges",
    params = verse_only,
    on_send = function()
      state.pushing_changes = {
        verse_only = verse_only,
        ending_game = true,
        done = false,
      }
      emit_state_update()

      notify(action_name .. " requested")
    end,
    on_response = function(err, result)
      state.pushing_changes.ending_game = false
      state.pushing_changes.done = true
      state.pushing_changes.error = err
      state.pushing_changes.success = result
      emit_state_update()

      state.pushing_changes = nil
      emit_state_update()

      if err ~= nil then
        notify(action_name .. " failed: " .. err, log_level.WARN)
      else
        notify(action_name .. " done: " .. result)
      end
    end,
  })
end

--- @param command string
--- @param params any
function M._handle_notification(command, params)
  if command == "updateBuildState" and type(params) == "number" then
    state.build_state = params
    if state.build_state == proto.BuildState.Building then
      if state.building ~= nil and not state.building.was_notified then
        state.building.was_notified = true
      end
      if state.pushing_changes ~= nil then
        state.pushing_changes.ending_game = false
      end
    end
    emit_state_update()
  elseif command == "canPushVerseChanges" and type(params) == "boolean" then
    state.can_push_verse_changes = params
    if not state.can_push_verse_changes
      and state.pushing_changes ~= nil
      and M._client:get_connection_duration() > SERVER_STATE_PROPAGATION_LEEWAY_MS then
      -- because of a bug where the server doesn't send a response to the push request
      state.pushing_changes.ending_game = false
      state.pushing_changes.done = true
      state.pushing_changes = nil
    end
    emit_state_update()
  elseif debug_enabled() then
    notify("Unhandled Verse Workflow Server notification: " .. command .. "(" .. vim.inspect(params) .. ")", log_level.DEBUG)
  end
end

return M
