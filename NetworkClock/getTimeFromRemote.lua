local Promise = require(script.Parent.Parent.Promise)

local function getTimeFromRemote(remoteFunction)
	return Promise.new(function(resolve)
		local timerStart = os.clock()
		local serverTime = remoteFunction:InvokeServer()
		local timerFinish = os.clock()
		local rtt = timerFinish - timerStart

		local serverTimeAdjusted = serverTime + rtt/2
		local offset = serverTimeAdjusted - timerFinish

		resolve({
			time = serverTimeAdjusted,
			accuracy = rtt,
			offset = offset,
		})
	end)
end

return getTimeFromRemote