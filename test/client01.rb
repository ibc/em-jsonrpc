#!/usr/bin/ruby
# coding: utf-8

### TMP
$LOAD_PATH.insert 0, File.expand_path(File.join(File.dirname(__FILE__), "../", "lib"))
require "em-jsonrpc/client"


class MyHandler < EM::JsonRPC::Client

  def do_request
    puts "--- my: do_request()"
    request = send_request "subtract", [42, 23]
    request.callback do |result|
      puts "INFO: result = #{result.inspect}"
      EM.add_timer(SecureRandom.random_number) { do_request }
    end
    request.errback do |error|
      puts "ERROR: result = #{error.inspect}"
      EM.add_timer(SecureRandom.random_number) { do_request }
    end
  end

  def connection_failed
    $stderr.puts "ERROR: connection failed"
    exit 1
  end

  def connection_terminated
    @connection_attemp ||= 0
    @connection_attemp  += 1
    $stderr.puts "WARN: connection terminated, reconnecting (#{@connection_attemp} attemp)..."
    EM.add_timer(0.5) { connect_again }
  end

  def parsing_error
    $stderr.puts "ERROR: parsing error"
  end

end


EM.set_max_timers 500000

EM.run do

  yajl_options = { :symbolize_keys => true }
  EM.connect "127.0.0.1", 8888, MyHandler, "127.0.0.1", 8888, nil, yajl_options do |conn|
    conn.do_request
    EM.add_periodic_timer(1) { puts "." }
    EM.add_periodic_timer(4) { puts "DEBUG: #{conn.pending_requests.size} pending requests" ; sleep 0.5 }
  end

end