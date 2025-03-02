#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/http'
require_relative '../lib/fiber_scheduler'

Fiber.set_scheduler(FiberScheduler.new)

mut = Mutex.new
cur_request = 0
num_requests = 100

t1 = Thread.new do
  loop do
    should_stop = mut.synchronize do
      puts "cur_request: #{cur_request}"
      cur_request >= num_requests
    end
    break if should_stop

    sleep(0.05)
  end
end

Fiber.schedule do
  t1.join
end

100.times do
  Fiber.schedule do
    puts Net::HTTP.get(URI('https://ifconfig.me/ip'))
    mut.synchronize do
      cur_request += 1
    end
  end
end
