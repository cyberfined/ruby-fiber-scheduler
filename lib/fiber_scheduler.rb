# frozen_string_literal: true

require 'nio4r'
require_relative 'bheap'

class FiberScheduler
  WaitFiber = Struct.new(:fiber, :events, :timer)

  Timer = Struct.new(:io, :priority, :bheap_idx) do
    alias_method :scheduled_at, :priority
  end

  def initialize
    @timers = BHeap.new
    @selector = NIO::Selector.new
    @fibers = {}.compare_by_identity
    @mutex = Mutex.new
    @ready = []
    @unblocked = []
  end

  def fiber(&)
    fiber = Fiber.new(blocking: false, &)
    fiber.resume
    fiber
  end

  def io_wait(io, events, timeout)
    timer =
      if timeout
        cur_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @timers.push(Timer.new(io, cur_time + timeout))
      end

    mode =
      if events.anybits?(IO::READABLE)
        events.anybits?(IO::WRITABLE) ? :rw : :r
      elsif events.anybits?(IO::WRITABLE)
        :w
      else
        raise 'Wrong events mask'
      end
    @selector.register(io, mode)
    @fibers[io] = WaitFiber.new(Fiber.current, events, timer)

    Fiber.yield
  end

  def block(_blocker, timeout = nil)
    wait_fiber = WaitFiber.new(Fiber.current, nil, nil)
    @fibers[wait_fiber.fiber] = wait_fiber
    return Fiber.yield unless timeout

    cur_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    timer = @timers.push(Timer.new(wait_fiber.fiber, cur_time + timeout))
    wait_fiber.timer = timer

    Fiber.yield
  end

  def unblock(_blocked, fiber)
    @mutex.synchronize do
      @unblocked << fiber
      @selector.wakeup
    end
  end

  def kernel_sleep(duration = nil)
    block(:sleep, duration)
  end

  def close
    while @fibers.any? || @ready.any?
      running, @ready = @ready, []
      running.each do |fiber|
        fiber.resume if fiber.alive?
      end

      running, @unblocked = @unblocked, []
      running.each do |fiber|
        resume_fiber(fiber, nil)
      end

      timeout = min_timeout
      timeout = 0 if timeout&.negative? || @ready.any?

      if @selector.empty?
        sleep(timeout) if @ready.empty? && timeout&.positive?
      else
        @selector.select(timeout) do |monitor|
          resume_fiber(monitor.io, monitor.readiness)
        end
      end

      process_timers
    end
  ensure
    @selector.close
  end

  def schedule(fiber)
    @ready << fiber
  end

  def yield
    @ready << Fiber.current
    Fiber.yield
  end

  private

  def min_timeout
    timer = @timers.peek_min
    return unless timer

    cur_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    timer.scheduled_at - cur_time
  end

  def process_timers
    loop do
      timer = @timers.peek_min
      break unless timer

      cur_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      timeout = timer.scheduled_at - cur_time
      break if timeout.positive?

      resume_fiber(timer.io, nil)
    end
  end

  def resume_fiber(io, mode)
    wait_fiber = @fibers.delete(io)
    return unless wait_fiber

    events = nil
    if wait_fiber.events
      events =
        case mode
        when :r then IO::READABLE
        when :w then IO::WRITABLE
        when nil then 0
        else IO::READABLE | IO::WRITABLE
        end
      events &= wait_fiber.events
      @selector.deregister(io)
    end
    @timers.delete(wait_fiber.timer) if wait_fiber.timer
    wait_fiber.fiber.resume(events) if wait_fiber.fiber.alive?
  end
end
