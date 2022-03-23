local BasePlugin = require "kong.plugins.base_plugin"
local plugin_name = 'aggregator'

local plugin = BasePlugin:extend()

local responses = require "kong.tools.responses"
local utils = require "kong.tools.utils"
local http = require "resty.http"
local cjson = require "cjson.safe"
local ngx = ngx
local resty_http = require 'resty.http'
local re_match = ngx.re.match
local string_upper = string.upper
local table_concat = table.concat

local function do_request(url, params)
    local httpc = resty_http:new()
    local res, err = httpc:request_uri(url, params)

    if err then
        ngx.log(ngx.ERR, "Error")
        return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end

    if not res then
        ngx.log(ngx.ERR, "No response")
        return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end

    if res.status == 200 and re_match(string_upper(res.headers["content-type"]), '^APPLICATION/JSON') then
        body = cjson.decode(res.body)
        return nil, res.status, res.body, res.headers
    end

    return nil, 400, '{"message": "status is not 200 or content-type is not application/json"}', {}
end

local function set_header(header, value)
    if not ngx.header[header] then
        ngx.header[header] = value
    end
end

local function override_header(header, value)
    if ngx.header[header] then
        ngx.header[header] = nil
    end
    ngx.header[header] = value
end

local function generate_body(content, headers)
    local body = {}

    for i = 1, 2 do
        body = utils.table_merge(body, cjson.decode(content[i]["data"]))
    end
    body = cjson.encode(body)
    return body

    --body = table_concat(content, ", ")
    --local b = {}
    --for i = 1, #content do
    --    h = cjson.encode(headers[i])
    --    b[i] = table_concat({ '[{ "headers": ', h, '}, {"body": ', content[i], '}]' })
    --    if i < #content then
    --        local a = b[i]
    --        b[i] = table_concat({ a, ', ' })
    --    end
    --end
    --s = table_concat(b)
    --body = table_concat({ '[', s, ']' })
    --return body
end

local function send(content, headers)
    ngx.status = 200
    body = generate_body(content, headers)

    set_header('Content-Length', #body)
    override_header('Content-Type', 'application/json')

    ngx.say(body)

    return ngx.exit(ngx.status)
end

function plugin:new()
    plugin.super.new(self, plugin_name)
end

function plugin:access()
    plugin.super.access(self)

    local upstream_uri = ngx.var.upstream_uri == "/" and "" or ngx.var.upstream_uri
    local user_id = upstream_uri:sub(2)
    local token = ngx.req.get_headers["Authorization"];

    local urls = { 'http://localhost:8080/addresses/user', 'http://localhost:8081/events' }
    local params = '{"ssl_verify": false, "headers": {"content-type": "application/json", "Authorization": ' .. token .. ' " }, "method": "GET"'

    local err = {}
    local status = {}
    local content = {}
    local headers = {}

    for i = 1, #urls do
        err[i], status[i], content[i], headers[i] = do_request(urls[i] .. upstream_uri, params)
    end

    return send(content, headers)
end

plugin.PRIORITY = 750
plugin.VERSION = "0.1-1"

return plugin