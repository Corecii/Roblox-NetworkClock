local Promise = require(script.Parent.Parent.Promise)

local HttpService = game:GetService("HttpService")

local HTTP_DISABLED_STRING = "http requests are not enabled"

local monthLookup = {Jan=1,Feb=2,Mar=3,Apr=4,May=5,Jun=6,Jul=7,Aug=8,Sep=9,Oct=10,Nov=11,Dec=12}

local function unixTimeFromDateHeader(dateString) --> unixTime: number
	local day, monthStr, year, hour, min, sec = dateString:match("%w+, (%d+) (%w+) (%d+) (%d+):(%d+):(%d+)")
	local month = monthLookup[monthStr]

	return os.time({year = year, month = month, day = day, hour = hour, min = min, sec = sec})
end

local function getUnixTimeFromUrl(url) --> Promise<{timestamp: number, rtt: number, accuracy: number}>
	return Promise.new(function(resolve)
		local timerStart = os.clock()
		local response = HttpService:RequestAsync({
			Url = url .. "/?nocache=" .. HttpService:GenerateGUID(),
		})
		local rtt = os.clock() - timerStart

		local date = response.Headers.date
		local timestamp = unixTimeFromDateHeader(date)

		resolve({
			timestamp = timestamp,
			rtt = rtt,
			accuracy = 1.5 + rtt,
		})
	end)
end

local function getModeResultWithMinAccuracy(results)
	local timestampCounts = {}
	local timestampResultMinAccuracy = {}
	for _, result in ipairs(results) do
		timestampCounts[result.timestamp] = (timestampCounts[result.timestamp] or 0) + 1
		if not timestampResultMinAccuracy[result.timestamp] or result.accuracy < timestampResultMinAccuracy[result.timestamp].accuracy then
			timestampResultMinAccuracy[result.timestamp] = result
		end
	end

	local mostCommonTimestamp
	local mostCommonTimestampCount = 0
	for timestamp, count in pairs(timestampCounts) do
		if count > mostCommonTimestampCount then
			mostCommonTimestamp = timestamp
		end
	end

	return timestampResultMinAccuracy[mostCommonTimestamp]
end

local function getTimeFromHttp(urls, timeout, minResults) --> Promise<{time: number, accuracy: number, offset: number}>
	timeout = timeout or 10
	minResults = math.max(1, minResults or 3)

	return Promise.new(function(resolve, reject)
		local promises = {}
		local results = {}
		for _, url in ipairs(urls) do
			local promise = getUnixTimeFromUrl(url):timeout(timeout):andThen(
				function(result)
					table.insert(results, result)
				end,
				function(err)
					if Promise.Error.isKind(err, Promise.Error.Kind.TimedOut) then
						warn("[NetworkClock] Request to " .. url .. " timed out (" .. timeout .."s)")
					elseif tostring(err):lower():find(HTTP_DISABLED_STRING) then
						warn("[NetworkClock] Http requests are disabled!")
					else
						warn("[NetworkClock] Request to " .. url .. " failed: " .. tostring(err))
					end
				end
			)
			table.insert(promises, promise)
		end

		Promise.allSettled(promises):await()

		if #results < minResults then
			reject("TooFewResults")
			return
		end

		local modeResult = getModeResultWithMinAccuracy(results)

		local unixTime = modeResult.timestamp + modeResult.rtt/2
		local now = os.clock()
		local offset = unixTime - now
		resolve({
			time = unixTime,
			accuracy = modeResult.accuracy,
			osset = offset,
		})
	end)
end

return getTimeFromHttp