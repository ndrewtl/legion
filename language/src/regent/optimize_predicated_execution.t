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

-- @param n the number of times to 'unroll' the loop
local function predicate(condition, body, n)
  -- only certain body statements can be predicated. For now, the only kind of expression that can
  -- be predicated is an assignment that assigns a Call, that is, something of the form:
  -- x = f(5), where f is a task
  -- should return a block

  -- default value of 1, so no unrolling
  n = n or 1

  -- this is our results object
  local stats = terralib.newlist()

  -- collect a list of new symbols
  local symbols = terralib.newlist()
  for i = 1,n do
    -- Initialize a new symbol
    -- TODO how to type the new symbol?
    symbols:insert(terralib.newsymbol(bool))
  end

  for i = n, 1, -1 do
    -- For each symbol, assign it the previous symbol's value. If it's the first symbol, give it
    -- the value of body
    if i == 1 then
      stats:insert(
        body.stats[1] {
          lhs = symbols[1],
          rhs = body.stats[1].rhs {
            predicate = condition
          }
        }
      )
    else
      stats:insert(
        ast.typed.stat.Assignment {
          lhs = symbols[i],
          rhs = ast.typed.stat.Expr {
            expr = ast.typed.expr.ID {
              value = symbols[i - 1],
              annotations = false,
              span = body.span,
              expr_type = body.stats[1].rhs.expr_type
            },
            annotations = false,
            span = body.span
          },
          metadata = false,
          annotations = false,
          span = body.span
        }
      )
    end
  end

  return {
    cond = ast.typed.stat.Expr {
      expr = condition.value,
      annotations = false, -- TODO figure out what goes here
      span = body.span
    },
    body = ast.typed.Block {
      stats = stats,
      span = body.span
    }
  }
end

-- analyze whether the given body can be predicated on the condition
-- currently: return true iff the body is a block with only assignments of calls and the condition
-- is a future
local function can_predicate(condition, body)
  return body:is(ast.typed.expr.Block) and
    table.getn(body.stats) == 1 and
    body.stats[1]:is(ast.typed.expr.Assignment) and
    body.stats[1].rhs:is(ast.typed.expr.Call) and
    condition:is(ast.typed.expr.FutureGetResult)
end

-- this is the meat of the optimization: Look at a statement, and if the condition and body meet
-- certain criteria, transform it into a predicated call
function optimize_predicated_execution.stat_if(cx, node)
  print(predicate(node.cond, node.then_block, 3).body)
  if can_predicate(node) then
    local predicated = node.then_block.stats[1].expr { predicate = node.cond.value }
    return ast.typed.stat.Expr {
      expr = predicated,
      span = node.span,
      annotations = node.annotations, -- TODO @ndrewtl confirm how to get these right
    }
    else
      return node
  end
end

local optimize_predicated_execution_stat_table = {
  [ast.typed.stat.If]        = optimize_predicated_execution.stat_if,
  [ast.typed.stat]        = do_nothing
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
