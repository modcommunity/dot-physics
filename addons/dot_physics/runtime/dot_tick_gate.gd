class_name DotTickGate
extends RefCounted

## Holds work heard between server ticks that queries the physics space, and runs it at the top of the next tick.
##
## With `physics/3d/run_on_separate_thread` (or a threaded engine) a ray or shape query is safe only
## inside the physics step, but console lines, chat and admin commands and network requests arrive in
## the idle frame. The rule is docs/threading.md's: a handler queues, the next tick answers.
##
## The server arms it and calls [method open] first thing in its tick. Unarmed (solo, a client, a
## suite driving a bare game) and inside a physics frame everything runs at once.
##
## [codeblock]
## gate.run(func() -> void: game.restart())
## await gate.reached()   # the coroutine resumes inside the next tick
## [/codeblock]

## Emitted by [method open] after the queued calls ran; an awaiting [method reached] resumes here.
signal opened

## True on a server whose tick calls [method open]. Off: [method run] and [method reached] never wait.
var armed := false

## Whether this is the physics step; a suite stands in for the engine's answer.
var in_step: Callable = func() -> bool: return Engine.is_in_physics_frame()

var _calls: Array[Callable] = []


## Runs [param fn] now when this is the tick (or the gate is unarmed), else at the top of the next tick.
func run(fn: Callable) -> void:
	if not waits():
		fn.call()
		return
	_calls.append(fn)


## A coroutine: returns at once in the tick or unarmed, else resumes inside the next tick.
func reached() -> void:
	if waits():
		await opened


## Whether a call made now would wait for the next tick.
func waits() -> bool:
	return armed and not bool(in_step.call())


## How many calls are queued for the next tick.
func pending() -> int:
	return _calls.size()


## The top of a server tick: the queued calls in arrival order, then whoever awaits [method reached].
## A call queued by one of them waits for the tick after.
func open() -> void:
	if not _calls.is_empty():
		var calls := _calls
		_calls = []
		for fn: Callable in calls:
			if fn.is_valid():
				fn.call()
	opened.emit()


## The server is going away: nothing queued runs, and whoever awaits [method reached] goes on now.
func disarm() -> void:
	armed = false
	_calls.clear()
	opened.emit()


func describe() -> Dictionary:
	return {"armed": armed, "pending": _calls.size()}
