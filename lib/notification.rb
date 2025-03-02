# frozen_string_literal: true

class Notification
  def initialize
    @fiber = Fiber.current
  end

  def wait
    @wait = true
    Fiber.yield
  end

  def notify
    return unless @wait

    @wait = false
    Fiber.scheduler.schedule(@fiber)
  end
end
