# NetworkClock

This module provides synchronized network time for the server and client.

**This module has not undergone rigorous or complete testing, and has not reached a stable version. Use at your own risk!**

# How To (With The Default Clock)

1. Add this module to your project
2. Add the Promise library (any version 3.x.x) to your project
2. Initialize the default network clock as part of starting your game. The clock *must* be initialized before you use it or it will error.
```lua
local NetworkClock = require(game.ReplicatedStorage.NetworkClock)

NetworkClock.Default():WaitUntilInitialized()
```
3. Use your clock in your project
```lua
local Clock = require(game.ReplicatedStorage.NetworkClock).Default()

print("The current timestamp is:", Clock:GetTime())
print("The timestamp's accuracy relative to the source is:", Clock:GetAccuracy())

print("The current time is:", Clock()) -- This works too
```

That's it!

# Stable API

```lua
NetworkClock.new(NetworkClockOptions) --> NetworkClock
-- Creates a new network clock with the given options

NetworkClock:GetInitializedPromise() --> Promise<self>
-- Returns a promise that resolve once the clock is synchronized and useable

NetworkClock:WaitUntilInitialized() --> self
-- Waits for the clock to be initialized
-- Sugar for NetworkClock:GetInitializedPromise():expect()

NetworkClock:GetTime() --> number
-- Returns the current decimal-precision timestamp from this clock
-- This will error if the clock is not initialized.

NetworkClock() -- > number
-- Sugar for NetworkClock:GetTime()

NetworkClock:GetAccuracy() --> number
-- Returns how far off at maximum the time could be from the source
-- For http time on the server, "the source" is unix time
-- For remote time on the client, "the source" is the server's time

NetworkClock.CREATE_REMOTE_FUNCTION
-- A constant representing that NetworkClock should handle creating/waiting for remote functions

NetworkClock.Default()
-- Returns a default network clock that can safely be used between different projects and modules

NetworkClock.DefaultNoHttp()
-- Returns a default, server os.clock-based network clock that can safely be used between different projects and modules
```

```lua
NetworkClockOptions
	name: string
	-- The name of this network clock -- typically your project's owner:name

	remoteFunction?: CREATE_REMOTE_FUNCTION | RemoteFunction | Promise<RemoteFunction> | false
	-- Default: CREATE_REMOTE_FUNCTION
	-- The remote function to use or handle
	-- If set to CREATE_REMOTE_FUNCTION, NetworkClock will create a remote function in ReplicatedStorage on the server, and wait for one on the client

	syncMode: "Http" | "OsClock" | "RemoteFunction"
	-- How to sync the time
	-- OsTime is meant to be used for testing in studio. OsTime can vary multiple minutes between servers!
	-- OsClock is meant for when you only need synchronized time between server and client and not between server
	-- Default: "Http" on server, "RemoteFunction" on client

	resyncOnSuccessInterval: number
	-- Default: 120 on server, 30 on client
	-- How often to resync time. Set to 0 to sync only once at the start of the game.

	resyncOnFailureInterval: number
	-- Default: 10
	-- How often to re-attempt sync when sync fails.

	resyncLerpOffset: boolean
	-- Default: true
	-- Whether to lerp the time offset to prevent discontinuous time jumps after resyncs

	httpTimeout: number
	-- Default: 10
	-- Max time an http request can take
	httpMinResults: number
	-- Default: 3
	-- Minimum number of results for this clock to be "confident" in its http-retrieved network time
	httpUrls: Array<string>
	-- Urls to retrieve time from
	-- Urls are requested as url/?nocache={GUID}
	-- All given urls are requested at once on every sync
	-- This is done to detect and avoid misconfigured and out-of-sync servers
	-- Default: {
	--  "https://www.wikipedia.org",
	--  "https://www.microsoft.com",
	--  "https://stackoverflow.com",
	--  "https://www.amazon.com",
	--  "https://aws.amazon.com",
	-- }
```

# How To (With Your Own Clock)

1. Add this module to your project
2. Add the Promise library (any version 3.x.x) to your project
2. Create modules to initialize your project's network clock. You should wait for your clock to initialize before using it.
```lua
-- MyNetworkClock.lua
local NetworkClock = require(game.ReplicatedStorage.NetworkClock)

local myClock = NetworkClock.new({name = "Me:MyGame"})
myClock:WaitUntilInitialized()

return myClock
```
3. Use your clock in your project
```lua
local Clock = require(game.ReplicatedStorage.MyNetworkClock)

print("The current timestamp is:", Clock:GetTime())
print("The timestamp's accuracy relative to the source is:", Clock:GetAccuracy())

print("The current time is:", Clock()) -- This works too
```

That's it!

# Design and Implementation

### Instanced Clocks

Everyone might not want the same clock behavior: some developers might not want http time, some might want to fetch time from different urls, some others might want to change the resync intervals.

With instanced clocks, you can safely depend on other modules that use NetworkClock. In one codebase, two modules can use two different clock settings without conflict.

### Avoiding Misconfigured Http Time Results

NetworkClock pulls its http time from the `Date` headers of popular websites. In a rare case, a web server could be misconfigured and report a bad Date. By pulling the Date headers from multiple websites, we can remove outliers.

### Accuracy

Pulling time from remote sources is inherently inaccurate: data has to travel a variable amount of time, and there's no way of knowing the exact one-way-trip-time. Even worse, time from http servers only has 1-second precision.

By storing the "accuracy" with the current time offset we can:
* know when we've found a more accurate time
* know when our accurate time is more out of date than its accuracy

On the server with http the accuracy is `1.5 + round_trip_time`. On the client with remotes the accuracy is `round_trip_time`.

When retrieving the time, estimated one-way-trip-time is accounted for.

###  Offset Lerp

We resync time because we can end up with a "better" network time for a variety of reasons:
* the new network time is more accurate (smaller round trip time)
* the old network time was wrong (misconfigured servers)
* the local time-keeping mechanism is bad (that is, when 1 second elapsed irl is not 1 second elapsed in the computer)

When we end up with a better network time we should ideally switch to it. Switching to it instantly can cause a jump or discontinuity in the local time, however small. This means time could jump forward unreasonably fast or it could *move backwards*.

To keep time moving smoothly and prevent backwards jumps we lerp between the old and new time offsets when a better network time is found.