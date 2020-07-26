local Promise = require(script.Parent.Parent.Promise)

local function getTimeFromOsClock()
	return Promise.resolve({
		time = os.clock(),
		accuracy = 0,
	})
end

return getTimeFromOsClock