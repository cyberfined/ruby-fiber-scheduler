#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/fiber_scheduler'

Fiber.set_scheduler(FiberScheduler.new)

10_000.times do |i|
  Fiber.schedule do
    sleep(2)
    puts i
  end
end
