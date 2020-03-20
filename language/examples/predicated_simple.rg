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

local c = regentlib.c

task condition1()
  c.usleep(500000)
  return true
end

task condition2()
  c.usleep(600000)
  return true
end

task body1()
  c.usleep(700000)
  return 1 + 1
end

task body2()
  c.usleep(800000)
  return 1 + 1
end

task toplevel()
  var t0 = c.legion_get_current_time_in_micros()
  if condition1() then
    body1()
  end
  if condition2() then
    body2()
  end
  var tf = c.legion_get_current_time_in_micros()
  c.printf("%7.3f\n", 1e-6 * (tf - t0))
end

task main()
  toplevel()
end

do
  regentlib.start(main)
end
