local Promise = require(script.Parent.Parent.Promise)

local function getTimeFromRemote(remoteFunction)
	return Promise.new(function(resolve)
		local timerStart = os.clock()
		local serverTime = remoteFunction:InvokeServer()
		local rtt = os.clock() - timerStart

		local serverTimeAdjusted = serverTime + rtt/2

		resolve({
			time = serverTimeAdjusted,
			accuracy = rtt,
		})
	end)
end

return getTimeFromRemote