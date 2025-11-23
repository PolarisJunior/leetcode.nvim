---@module 'plenary'

local log = require("leetcode.logger")
local interpreter = require("leetcode.api.interpreter")
local config = require("leetcode.config")
local Judge = require("leetcode.logger.spinner.judge")
local utils = require("leetcode.utils")
local Job = require("plenary.job")
local Path = require("plenary.path")

---@type Path
local leetbody = config.storage.cache:joinpath("body")
leetbody:touch()

---@class lc.Runner
---@field question lc.ui.Question
local Runner = {}
Runner.__index = Runner

Runner.running = false

---@param self lc.Runner
---@param submit boolean
Runner.run = vim.schedule_wrap(function(self, submit)
    if Runner.running then
        return log.warn("Runner is busy")
    end

    local ok, err = pcall(Runner.handle, self, submit)
    if not ok then
        self:stop()
        log.error(err)
    end
end)

Runner.stop = function()
    Runner.running = false
end

local GIT_DIRECTORY = "/home/pjkumlue/leetcode"

local function get_extension(lang)
    return "." .. utils.get_lang(lang).ft
end

---@param question lc.ui.Question
---@param source string
local function run_git_handler(question, source)
    local title_slug = question.q.title_slug
    local lang = question.lang
    local root = Path:new(GIT_DIRECTORY)
    local ext = get_extension(lang)

    local path = root:joinpath(lang)
    if not path:exists() then
        path:mkdir()
    end

    path = path:joinpath(question.q.difficulty)
    if not path:exists() then
        path:mkdir()
    end

    local file = path:joinpath(question.q.id .. "-" .. title_slug .. ext)
    file:write(source, "w", nil)

    local result, code = Job:new({
        command = "git",
        args = { "add", "-A" },
        cwd = GIT_DIRECTORY,
    }):sync()

    local message = "Updated " .. title_slug .. " in " .. lang
    result, code = Job:new({
        command = "git",
        args = { "commit", "-m", message },
        cwd = GIT_DIRECTORY,
    }):sync()

    result, code = Job:new({
        command = "git",
        args = { "push" },
        cwd = GIT_DIRECTORY,
    }):sync()

    vim.notify("Finished uploading submission to git", vim.log.levels.INFO)
end

function Runner:handle(submit)
    Runner.running = true
    local question = self.question

    local body = {
        lang = question.lang,
        typed_code = self.question:editor_submit_lines(submit),
        question_id = question.q.id,
        data_input = not submit and question.console.testcase:content(),
    }

    local judge = Judge:init()
    local function callback(item, state, err)
        if err or item then
            self:stop()
        end

        if item then
            if item._.success then
                run_git_handler(question, body.typed_code)
                judge:success(item.status_msg)
            else
                judge:error(item.status_msg)
            end
        elseif state then
            judge:from_state(state)
        elseif err then
            judge:error(err.msg or "Something went wrong")
        end

        if item then
            question.console.result:handle(item)
        end
    end

    leetbody:write(vim.json.encode(body), "w")
    interpreter.run(submit, question, leetbody:absolute(), callback)
end

---@param question lc.ui.Question
function Runner:init(question)
    return setmetatable({ question = question }, self)
end

return Runner
