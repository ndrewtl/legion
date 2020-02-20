-- Copyright 2020 Stanford University
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

-- Regent Index Launch Optimizer
--
-- Attempts to determine which loops can be transformed into index
-- space task launches.

local affine_helper = require("regent/affine_helper")
local ast = require("regent/ast")
local data = require("common/data")
local report = require("common/report")
local std = require("regent/std")

local optimize_predicated_execution = {}

-- Begin context code imported from optimize_index_launches
local context = {}

function context:__index (field)
  local value = context [field]
  if value ~= nil then
    return value
  end
  error ("context has no field '" .. field .. "' (in lookup)", 2)
end

function context:__newindex (field, value)
  error ("context has no field '" .. field .. "' (in assignment)", 2)
end

function context:new_local_scope()
  local cx = {
    constraints = self.constraints,
    loop_index = false,
    loop_variables = {},
    free_variables = terralib.newlist(),
  }
  return setmetatable(cx, context)
end

function context:new_task_scope(constraints)
  local cx = {
    constraints = constraints,
  }
  return setmetatable(cx, context)
end

function context.new_global_scope()
  local cx = {}
  return setmetatable(cx, context)
end

function context:set_loop_index(loop_index)
  assert(not self.loop_index)
  self.loop_index = loop_index
end

function context:add_loop_variable(loop_variable)
  assert(self.loop_variables)
  self.loop_variables[loop_variable] = true
end

function context:add_free_variable(symbol)
  assert(self.free_variables)
  self.free_variables:insert(symbol)
end

function context:is_free_variable(variable)
  assert(self.free_variables)
  for _, elem in ipairs(self.free_variables) do
    if elem == variable then
      return true
    end
  end
  return false
end

function context:is_loop_variable(variable)
  assert(self.loop_variables)
  return self.loop_variables[variable]
end

function context:is_loop_index(variable)
  assert(self.loop_index)
  return self.loop_index == variable
end
-- end context code

local function do_nothing(cx, node) return node end

local optimize_predicated_execution_stat_table = {
  -- [ast.typed.stat.ForNum]    = optimize_index_launch.stat_for_num,
  -- [ast.typed.stat.ForList]   = optimize_index_launch.stat_for_list,
  --
  -- [ast.typed.stat.While]     = optimize_index_launches.stat_block,
  -- [ast.typed.stat.Repeat]    = optimize_index_launches.stat_block,
  -- [ast.typed.stat.Block]     = optimize_index_launches.stat_block,
  -- [ast.typed.stat.MustEpoch] = optimize_index_launches.stat_block,
  -- [ast.typed.stat.While]     = optimize_index_launches.stat_block,
  -- [ast.typed.stat.If]        = optimize_index_launches.stat_if,
  -- [ast.typed.stat.Elseif]    = optimize_index_launches.stat_elseif,
  [ast.typed.stat]           = do_nothing,
}

local optimize_predicated_execution_stat = ast.make_single_dispatch(
  optimize_predicated_execution_stat_table, {})

function optimize_predicated_execution.stat(cx, node)
  return optimize_predicated_execution_stat(cx)(node)
end

function optimize_predicated_execution.block(cx, node)
  return node {
    stats = node.stats:map(function(stat)
      return optimize_predicated_execution.stat(cx, stat)
    end)
  }
end

function optimize_predicated_execution.top_task(cx, node)
  if not node.body then return node end

  local cx = cx:new_task_scope(node.prototype:get_constraints())
  local body = optimize_predicated_execution.block(cx, node.body)

  return node { body = body }
end

function optimize_predicated_execution.top(cx, node)
  if node:is(ast.typed.top.Task) and
     not node.config_options.leaf
  then
    return optimize_predicated_execution.top_task(cx, node)

  else
    return node
  end
end

function optimize_predicated_execution.entry(node)
  local cx = context.new_global_scope({})
  return optimize_predicated_execution.top(cx, node)
end

optimize_predicated_execution.pass_name = "optimize_predicated_execution"

return optimize_predicated_execution
