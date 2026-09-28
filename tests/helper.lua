-- A minimal test harness shared by tests/*_test.lua.
-- Each test file runs in its own `nvim -l`, and finish() sets the exit code.

package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path

local H = { pass_count = 0, fail_count = 0 }

function H.eq(actual, expected, msg)
  if actual == expected then
    H.pass_count = H.pass_count + 1
  else
    H.fail_count = H.fail_count + 1
    print("FAIL: " .. msg)
    print("  expected: " .. vim.inspect(expected))
    print("  actual:   " .. vim.inspect(actual))
  end
end

function H.test(name, fn)
  local ok, err = pcall(fn)
  if not ok then
    H.fail_count = H.fail_count + 1
    print("ERROR: " .. name .. ": " .. tostring(err))
  end
end

function H.finish()
  print(("%d passed, %d failed"):format(H.pass_count, H.fail_count))
  if H.fail_count > 0 then os.exit(1) end
end

return H
