# frozen_string_literal: true

class BHeap
  def initialize
    @heap = []
  end

  def peek_min
    @heap[0]
  end

  def pop_min
    return if @heap.empty?

    top = @heap[0]

    if @heap.length == 1
      @heap.pop
    else
      @heap[0] = @heap.pop
      move_down(0)
    end

    top
  end

  def push(elem)
    @heap << elem
    move_up(@heap.size - 1)
    elem
  end

  def delete(elem)
    tmp = @heap.pop
    return if @heap.empty? || elem.bheap_idx >= @heap.length

    @heap[elem.bheap_idx] = tmp
    move_down(elem.bheap_idx)

    nil
  end

  def increase(elem)
    move_down(elem.bheap_idx)
  end

  def decrease(elem)
    move_up(elem.bheap_idx)
  end

  def size
    @heap.length
  end

  def empty?
    @heap.empty?
  end

  private

  def move_up(i)
    until i.zero?
      p = (i - 1) / 2
      break if @heap[p].priority <= @heap[i].priority

      @heap[p], @heap[i] = @heap[i], @heap[p]
      @heap[i].bheap_idx = i
      i = p
    end

    @heap[i].bheap_idx = i
  end

  def move_down(i)
    while i < @heap.length
      l = 2 * i + 1
      break if l >= @heap.length

      min_i = i
      r = l + 1

      min_i = l if @heap[l].priority < @heap[i].priority
      min_i = r if r < @heap.length && @heap[r].priority < @heap[min_i].priority
      break if min_i == i

      @heap[min_i], @heap[i] = @heap[i], @heap[min_i]
      @heap[i].bheap_idx = i
      i = min_i
    end

    @heap[i].bheap_idx = i
  end
end
