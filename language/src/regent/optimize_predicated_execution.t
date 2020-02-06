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

-- Regent Index Predicated Execution optimizer
--
-- In an if statement of the form if task1() then task2(), attempts to launch the two tasks
-- simultaneously only if both tasks are side-effect free

local ast = require("regent/ast")
local data = require("common/data")
local report = require("common/report")
local std = require("regent/std")

local optimize_predicated_execution = {}

function optimize_predicated_execution.entry(node)
  return node
end

optimize_predicated_execution.pass_name = "optimize_predicated_execution"

return optimize_predicated_execution
