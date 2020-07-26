
local function get_optional(options, name, default)
	if not options or options[name] == nil then
		return default
	else
		return options[name]
	end
end

local SyncedClock = {}
SyncedClock.__index = SyncedClock

function SyncedClock.new(options)
	local self = {
		shouldLerp = get_optional(options, "shouldLerp", true),

		offset = nil,

		offsetAccuracy = nil,

		offsetLerpClockStart = nil,
		offsetLerpClockEnd = nil,
		offsetLerpValueStart = nil,
		offsetLerpValueDiff = nil,
	}
	setmetatable(self, SyncedClock)
	return self
end

function SyncedClock:GetOffset(now)
	now = now or os.clock()
	if self.offsetLerpClockEnd then
		if self.offsetLerpClockEnd < now then
			self.offsetLerpClockStart = nil
			self.offsetLerpClockEnd = nil
			self.offsetLerpValueStart = nil
			self.offsetLerpValueDiff = nil
		elseif self.offsetLerpClockStart > now then
			return self.offsetLerpValueStart
		else
			local lerpPct = (now - self.offsetLerpClockStart) / (self.offsetLerpClockEnd - self.offsetLerpClockStart)
			local offset = self.offsetLerpValueStart + self.offsetLerpValueDiff * lerpPct
			return offset
		end
	end

	return self.offset
end

function SyncedClock:GetTime(now)
	assert(self.offset, "[NetworkClock] Time not synced yet")
	now = now or os.clock()
	return now + self:GetOffset(now)
end

function SyncedClock:GetRawTime(now)
	assert(self.offset, "[NetworkClock] Time not synced yet")
	now = now or os.clock()
	return now + self.offset
end

function SyncedClock:GetAccuracy()
	return self.offsetAccuracy
end

function SyncedClock:IsNewOffsetPreferred(offset, accuracy)
	if not self.offset then
		return true
	end
	if accuracy < self.offsetAccuracy then
		return true
	end
	if math.abs(offset - self.offset) > (self.offsetAccuracy + accuracy)/2 then
		return true
	end
	return false
end

function SyncedClock:TrySetOffset(offset, accuracy)
	accuracy = accuracy or 0

	if not self:IsNewOffsetPreferred(offset, accuracy) then
		return
	end

	if self.offset and self.shouldLerp then
		local now = os.clock()

		-- Calculate the lerp time:
		-- Typically, lerping for the amount of time the offset changed is okay
		-- When the offset moves backwards, we have to lerp twice as long or time "stops"
		local baseOffset = self:GetOffset(now)
		local offsetDiff = offset - baseOffset
		if offsetDiff < 0 then
			local minTime = math.abs(offsetDiff)*1.1
			local maxTime = math.max(60, minTime)
			self.offsetLerpClockEnd = now + math.min(math.abs(offsetDiff)*2, maxTime)
		else
			self.offsetLerpClockEnd = now + math.abs(offsetDiff)
		end

		self.offsetLerpClockStart = now
		self.offsetLerpValueStart = baseOffset
		self.offsetLerpValueDiff = offset - baseOffset
	end

	self.offset = offset
	self.offsetAccuracy = accuracy
end

function SyncedClock:__call()
	return self:GetTime()
end

return SyncedClock