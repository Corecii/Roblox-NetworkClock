local SyncedClock = require(script.SyncedClock)
local Promise = require(script.Parent.Promise)
local getTimeFromHttp = require(script.getTimeFromHttp)
local getTimeFromOsClock = require(script.getTimeFromOsClock)
local getTimeFromRemote = require(script.getTimeFromRemote)

local RunService = game:GetService("RunService")

local defaultNetworkClock, defaultNetworkClockNoHttp

local NetworkClock = {}
NetworkClock.__index = NetworkClock

NetworkClock.CREATE_REMOTE_FUNCTION = {}

local defaultSyncMode, defaultResyncOnSuccessInterval
if RunService:IsServer() then
	defaultSyncMode = "Http"
	defaultResyncOnSuccessInterval = 120
else
	defaultSyncMode = "RemoteFunction"
	defaultResyncOnSuccessInterval = 30
end

local defaultOptions = {
	name = false,
	remoteFunction = NetworkClock.CREATE_REMOTE_FUNCTION,
	timeSource = defaultSyncMode, -- "Http" | "OsClock" | "RemoteFunction"
	resyncOnSuccessInterval = defaultResyncOnSuccessInterval,
	resyncOnFailureInterval = 10,
	resyncLerpOffset = true,

	httpTimeout = 10,
	httpMinResults = 3,
	httpUrls = {
		"https://www.wikipedia.org",
		"https://www.microsoft.com",
		"https://stackoverflow.com",
		"https://www.amazon.com",
		"https://aws.amazon.com",
	},
}

function NetworkClock.new(newOptions)
	local self = setmetatable({}, NetworkClock)

	local options = {}
	for k, v in pairs(defaultOptions) do
		if newOptions and newOptions[k] ~= nil then
			options[k] = newOptions[k]
		else
			options[k] = v
		end
	end
	self.options = options

	assert(typeof(self.options.name) == "string", "expected string for options.name, got " .. typeof(self.options.name))
	if self.options.timeSource == "Remote" and not self.options.remoteFunction then
		error("When options.timeSource is \"RemoteFunction\", options.remoteFunction must be set")
	end

	self.name = self.options.name
	self.clock = SyncedClock.new({
		shouldLerp = self.options.resyncLerpOffset,
	})
	self.init = self:_Init()

	return self
end

function NetworkClock:_InitRemoteFunction()
	return Promise.try(function()
		if self.options.remoteFunction == NetworkClock.CREATE_REMOTE_FUNCTION then
			if RunService:IsServer() then
				local remoteFunction = Instance.new("RemoteFunction")
				remoteFunction.Name = "__NetworkClock:" .. self.name
				self.remoteFunction = remoteFunction
			else
				self.remoteFunction = game.ReplicatedStorage:WaitForChild("__NetworkClock:" .. self.name)
			end
		elseif typeof(self.options.remoteFunction) == "Instance" then
			self.remoteFunction = self.options.remoteFunction
		elseif Promise.is(self.options.remoteFunction) then
			self.remoteFunction = self.options.remoteFunction:expect()
		end
		if RunService:IsServer() then
			self.remoteFunction.OnServerInvoke = function()
				return self.clock:GetRawTime()
			end
		end
	end)
end

function NetworkClock:_AttemptSync()
	local syncPromise
	if self.options.timeSource == "Http" then
		syncPromise = getTimeFromHttp(self.options.httpUrls, self.options.httpTimeout, self.options.httpMinResults)
	elseif self.options.timeSource == "OsClock" then
		syncPromise = getTimeFromOsClock()
	elseif self.options.timeSource == "RemoteFunction" then
		syncPromise = getTimeFromRemote(self.remoteFunction)
	end
	assert(syncPromise, "Bad timeSource")

	return syncPromise:andThen(function(data)
		local now = os.clock()
		local offset = data.time - now
		self.clock:TrySetOffset(offset, data.accuracy)
	end)
end

function NetworkClock:_AttemptSyncUntilSuccess()
	return Promise.try(function()
		while true do
			local success, err = self:_AttemptSync():await()
			if success then
				return
			end
			warn("[NetworkClock] " .. tostring(self.options.timeSource) .. " sync failed because: " .. tostring(err))
			Promise.delay(self.options.resyncOnFailureInterval):expect()
		end
	end)
end

function NetworkClock:_SyncPersistentlyInBackground()
	return Promise.try(function()
		while true do
			local success, err = self:_AttemptSyncUntilSuccess():await()
			if not success then
				warn("[NetworkClock] " .. tostring(self.options.timeSource) .. " persistent sync failed because: " .. tostring(err))
				warn("[NetworkClock] Stopping background sync. This clock (" .. tostring(self.name) .. ") may drift out of sync.")
				error(err)
			end
			Promise.delay(self.options.resyncOnSuccessInterval):expect()
		end
	end)
end

function NetworkClock:_Init()
	return Promise.try(function()
		self:_InitRemoteFunction():expect()

		self:_AttemptSyncUntilSuccess():expect()

		if RunService:IsServer() and self.options.remoteFunction == NetworkClock.CREATE_REMOTE_FUNCTION then
			self.remoteFunction.Parent = game.ReplicatedStorage
		end

		if self.options.resyncOnSuccessInterval > 0 then
			self:_SyncPersistentlyInBackground()
		end

		return self
	end):catch(function(err)
		warn("[NetworkClock] Init failed because: " .. tostring(err))
		return Promise.reject(err)
	end)
end

function NetworkClock:GetInitalizedPromise()
	return Promise.try(function()
		return self.init:expect()
	end)
end

function NetworkClock:WaitUntilInitialized()
	return self.init:expect()
end

function NetworkClock:GetTime()
	return self.clock:GetTime()
end

function NetworkClock:GetAccuracy()
	return self.clock:GetAccuracy()
end

function NetworkClock:__call()
	return self.clock:GetTime()
end

function NetworkClock.Default()
	if not defaultNetworkClock then
		defaultNetworkClock = NetworkClock.new({name = "NetworkClock:Default"})
	end
	return defaultNetworkClock
end

function NetworkClock.DefaultNoHttp()
	if not defaultNetworkClockNoHttp then
		if RunService:IsServer() then
			defaultNetworkClockNoHttp = NetworkClock.new({
				name = "NetworkClock:DefaultNoHttp",
				timeSource = "OsClock",
				resyncOnSuccessInterval = 0,
			})
		else
			defaultNetworkClockNoHttp = NetworkClock.new({
				name = "NetworkClock:DefaultNoHttp",
				timeSource = "RemoteFunction",
				resyncOnSuccessInterval = 30,
			})
		end
	end
	return defaultNetworkClockNoHttp
end

return NetworkClock