#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/http'
require_relative '../lib/fiber_scheduler'

Fiber.set_scheduler(FiberScheduler.new)

5.times do
  Fiber.schedule do
    Net::HTTP.get(URI('https://httpbin.org/delay/2'))
  end
end
