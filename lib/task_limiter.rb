# frozen_string_literal: true

require_relative 'notification'

class TaskLimiter
  def initialize(limit)
    @limit = limit
    @count = 0
    @notification = Notification.new
  end

  def schedule(&block)
    @notification.wait if @count >= @limit

    @count += 1
    Fiber.schedule do
      block.call
    ensure
      @count -= 1
      @notification.notify
    end
  end
end
