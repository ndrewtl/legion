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

-- runs-with:
-- [
--   ["-verify", "-ll:cpu", "4", "-fflow", "0"],
--   ["-p", "1", "-verify", "-fflow", "0"]
-- ]

import "regent"

task condition(i: int)
  return i < 10
end

task body(i: int)
  return i + 1
end

task toplevel()
  var i = 0
  while condition(i) do
    i = body(i)
  end
end

regentlib.start(toplevel)
