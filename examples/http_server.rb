#!/usr/bin/env ruby
# frozen_string_literal: true

require 'socket'
require 'net/http'
require 'pathname'
require_relative '../lib/fiber_scheduler'
require_relative '../lib/task_limiter'

class StaticServer
  OK = '200 OK'
  BAD_REQUEST = '400 Bad Request'
  NOT_FOUND = '404 Not Found'
  METHOD_NOT_ALLOWED = '405 Method Not Allowed'
  CONTENT_TOO_LARGE = '413 Content Too Large'
  URI_IS_TOO_LONG = '414 URI Too Long'
  INTERNAL_SERVER_ERROR = '500 Internal Server Error'
  HTTP_VERSION_NOT_SUPPORTED = '505 HTTP Version Not Supported'

  MIME_TYPES = { '.jpg' => 'image/jpeg', '.jpeg' => 'image/jpeg', '.gif' => 'image/gif',
                 '.png' => 'image/png', '.bmp' => 'image/bmp', '.wav' => 'audio/x-wav',
                 '.wave' => 'audio/x-wav', '.mp3' => 'audio/mpeg', '.mp4' => 'video/mp4',
                 '.aac' => 'audio/aac', '.txt' => 'text/plain', '.pdf' => 'application/pdf',
                 '.json' => 'application/json' }.freeze

  def initialize(addr:, port:, dir:, tasks_limit:, with_stats: false, max_body_size: 1024)
    @addr = addr
    @port = port
    @dir = dir
    @tasks_limit = tasks_limit
    @with_stats = with_stats
    @max_body_size = max_body_size
  end

  def serve
    if @with_stats
      Fiber.schedule do
        loop do
          fibers_count = 0
          ObjectSpace.each_object(Fiber) { |o| fibers_count += 1 if o.alive? && !o.blocking? }
          puts "Fibers count: #{fibers_count}"
          sleep(1)
        end
      end
    end

    accept_sock = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM)
    accept_sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
    accept_sock.bind(Addrinfo.tcp(@addr, @port))
    accept_sock.listen(1024)

    tasks_limter = TaskLimiter.new(@tasks_limit)
    loop do
      client_sock, = accept_sock.accept
      tasks_limter.schedule do
        handle_client(client_sock)
      rescue StandardError => e
        puts e.message
      end
    end
  end

  private

  def handle_client(sock)
    until sock.closed?
      body = sock.each_line(@max_body_size)
      request = parse_request(sock, body)
      return if request.nil?

      write_response(sock, request)

      # We call yield here, because we can't guarantee fiber will wait for an io
      # in the next iteration
      Fiber.scheduler.yield
    end
  rescue StandardError
    http_error(sock, INTERNAL_SERVER_ERROR)
  ensure
    sock.close
  end

  def parse_request(sock, body)
    request_line = body.next
    return http_error(sock, URI_IS_TOO_LONG) unless request_line.end_with?("\r\n")

    request_line.delete_suffix!("\r\n")
    toks = request_line.split(' ')
    error =
      if toks.length != 3
        BAD_REQUEST
      elsif toks[0].downcase != 'get'
        METHOD_NOT_ALLOWED
      elsif toks[2].downcase != 'http/1.1'
        HTTP_VERSION_NOT_SUPPORTED
      end
    return http_error(sock, error) if error

    request =
      begin
        URI.decode_www_form_component(toks[1])
      rescue StandardError
        http_error(sock, BAD_REQUEST)
        return
      end

    body_size = request_line.length
    loop do
      line = body.next
      body_size += line.length
      return http_error(sock, CONTENT_TOO_LARGE) if body_size > @max_body_size

      break if line == "\r\n"
    end

    request
  end

  def write_response(sock, request)
    req_path = Pathname.new(request)
    return http_error(sock, NOT_FOUND) unless req_path.absolute?

    content_type = MIME_TYPES.fetch(File.extname(request), 'application/octet-stream')
    File.open("#{@dir}#{request}", 'rb') do |f|
      stat = f.lstat
      return http_error(sock, NOT_FOUND) if stat.directory?

      sock.write("HTTP/1.1 #{OK}\r\n" \
                 "Content-Length: #{stat.size}\r\n" \
                 "Content-Type: #{content_type}\r\n" \
                 "Connection: keep-alive\r\n\r\n")
      IO.copy_stream(f, sock)
    end
  rescue Errno::ENOENT
    http_error(sock, NOT_FOUND)
  end

  def http_error(sock, message)
    sock.write("HTTP/1.1 #{message}\r\n" \
               "Content-Length: #{message.length}\r\n\r\n#{message}")
    sock.close
    nil
  end
end

Fiber.set_scheduler(FiberScheduler.new)

Fiber.schedule do
  server = StaticServer.new(
    addr: '127.0.0.1',
    port: 8088,
    dir: '/Users/user/Downloads',
    with_stats: false,
    tasks_limit: 100
  )
  server.serve
end
