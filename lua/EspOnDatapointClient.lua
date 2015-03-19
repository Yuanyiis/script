local moduleName = ...
local M = {}
_G[moduleName] = M

local conn = nil
local devicekey = nil
local server = '115.29.202.58' -- iot.espressif.cn
local port = 8000

local datapointMapFunc = {}

local keepAliveTime = 60000
local isConnected = false
local buffer = ''

local function getStr(str, key)
    for k in string.gmatch(str, '.*"'..key..'" *: *"([^"]+)".*') do
        if k ~= nil then
            return k
        end
    end
    return nil
end

local function getNumber(str, key)
    for k in string.gmatch(str, '.*"'..key..'" *: *(%d+).*') do
        if k ~= nil then
            return k
        end
    end
    return nil
end

local function identify()
    local identifystr = '{"path": "/v1/device/identify/", "method": "POST", "meta": {"Authorization": "token '..devicekey..'"}}\n'
    if isConnected == true then
        conn:send(identifystr)
    end
end

local function route(response)
    buffer = buffer..response
    local i, j = string.find(buffer, '\n')
    if i == nil then
        return false
    end
    local line = string.sub(buffer, 1, i-1)
    buffer = string.sub(buffer, i+1, -1)
    local path = getStr(line, 'path')
    if path == nil then
        return
    end
    local nonce = getNumber(line, 'nonce')
    local datastreamName = string.gmatch(path, '/v1/datastreams/([a-z-_.]+)/datapoint/?')()
    if datastreamName then
        func = datapointMapFunc[datastreamName]
        if func == nil then
            func = datapointMapFunc['*']
        end
        if func ~= nil then
            local datapoint = {}
            datapoint['x'] = getNumber(line, 'x')
            datapoint['y'] = getNumber(line, 'y')
            datapoint['z'] = getNumber(line, 'z')
            datapoint['k'] = getNumber(line, 'k')
            datapoint['l'] = getNumber(line, 'l')
            local result = func(datastreamName, datapoint)
            if result and nonce then
                conn:send('{"status": 200, "deliver_to_device": true, "nonce": '..nonce..'}\n')
            end
        end
        return true
    end

    print('unsupport command')
    return false
end

local function connect()
    conn = net.createConnection(net.TCP, false)
    conn:on('connection', function(sck, response)
        isConnected = true
        identify()
    end)
    conn:on('disconnection', function(sck, response)
        isConnected = false
        connect()
    end)
    conn:on('receive', function(sck, response)
        route(response)
    end)
    conn:on('sent', function(sck, response)
    end)
    conn:connect(port, server)
end

local function keepAlive()
    local pingstr = '{"path": "/v1/ping/", "method": "GET", "meta": {"Authorization": "token '..devicekey..'"}}\n'
    if isConnected == true then
        conn:send(pingstr)
    else
        connect()
    end
end
----
function M.init(key)
    if key == nil or key == '' then
        assert(false, 'need key')
    end
    devicekey = key
end

function M.run()
    connect()
    tmr.alarm(1, keepAliveTime, 1, function() 
        keepAlive()
    end)
end

----
function M.onDatapoint(datastreamName, datapointFunc)
    datapointMapFunc[datastreamName] = datapointFunc
end

