#!/usr/bin/ruby
# coding: utf-8

require "test/unit"
require "rubygems"
require "yajl"
require "socket"
require "timeout"


class TestJsonRPC < Test::Unit::TestCase

  def initialize(*args)
    super
    @socket = TCPSocket.new "127.0.0.1", 8888
    @parser = Yajl::Parser.new
    @parser.on_parse_complete = method(:response_parsed)
    @encoder = Yajl::Encoder.new
  end

  def send_request(request)
    @response = nil
    @socket.send request, 0

    begin
      Timeout.timeout(0.2) do
        while true do
          begin
            data = @socket.recv_nonblock 1024
            @parser << data
            return @response if @response
          rescue IO::WaitReadable #Errno::EAGAIN
            IO.select([@socket])
            retry
          end
        end
      end
    rescue Timeout::Error
      return nil
    end
  end

  def response_parsed(response)
    @response = response
  end

  def test_01_rpc_call_with_positional_parameters
    reply = send_request '{"jsonrpc": "2.0", "method": "subtract", "params": [42, 23], "id": 1}'
    assert_equal( {"jsonrpc"=>"2.0", "result"=>19, "id"=>1}, reply )
  end

  def test_02_rpc_call_with_positional_parameters
    reply = send_request '{"jsonrpc": "2.0", "method": "subtract", "params": [23, 42], "id": 2}'
    assert_equal( {"jsonrpc"=>"2.0", "result"=>-19, "id"=>2}, reply )
  end

  def test_03_rpc_call_with_named_parameters
    reply = send_request '{"jsonrpc": "2.0", "method": "subtract", "params": {"subtrahend": 23, "minuend": 42}, "id": 3}'
    assert_equal( {"jsonrpc"=>"2.0", "result"=>19, "id"=>3}, reply )
  end

  def test_04_rpc_call_with_named_parameters
    reply = send_request '{"jsonrpc": "2.0", "method": "subtract", "params": {"minuend": 42, "subtrahend": 23}, "id": 4}'
    assert_equal( {"jsonrpc"=>"2.0", "result"=>19, "id"=>4}, reply )
  end

  def test_05_a_notification
    reply = send_request '{"jsonrpc": "2.0", "method": "update", "params": [1,2,3,4,5]}'
    assert_equal( nil, reply )
  end

  def test_06_rpc_call_of_non_existent_method
    reply = send_request '{"jsonrpc": "2.0", "method": "foobar", "id": "1"}'
    assert_equal( {"jsonrpc"=>"2.0", "error"=>{"code"=>-32601, "message"=>"method not found"}, "id"=>"1"}, reply )
  end

  def test_07_rpc_call_with_invalid_JSON
    reply = send_request '{"jsonrpc": "2.0", "method": "foobar, "params": "bar", "baz]'
    assert_equal( {"jsonrpc"=>"2.0", "error"=>{"code"=>-32700, "message"=>"invalid JSON"}, "id"=>nil}, reply )
  end

  def test_08_rpc_call_with_invalid_Request_object
    reply = send_request '{"jsonrpc": "2.0", "method": 1, "params": "bar"}'
    assert_equal( {"jsonrpc"=>"2.0", "error" =>{"code"=>-32600, "message"=>"invalid request: wrong method"}, "id"=>nil}, reply )
  end

  def test_09_rpc_call_Batch_invalid_JSON
    reply = send_request '[ {"jsonrpc": "2.0", "method": "sum", "params": [1,2,4], "id": "1"},{"jsonrpc": "2.0", "method" ]'
    assert_equal( {"jsonrpc"=>"2.0", "error"=>{"code"=>-32700, "message"=>"invalid JSON"}, "id"=>nil}, reply )
  end

# NOTE: Batch mode is not implemented so following tests don't make sense.
#
#   def test_10_rpc_call_with_an_empty_Array
#     reply = send_request '[]'
#     assert_equal( {"jsonrpc"=>"2.0", "error"=>{"code"=>-32600, "message"=>"invalid JSON"}, "id"=>nil}, reply )
#   end
# 
#   def test_11_rpc_call_with_an_invalid_Batch_but_not_empty
#     reply = send_request '[1]'
#     assert_equal( [{"jsonrpc"=>"2.0", "error"=>{"code"=>-32600, "message"=>"Invalid Request."}, "id"=>nil}], reply )
#   end
# 
#   def test_12_rpc_call_with_invalid_Batch
#     reply = send_request '[1,2,3]'
#     assert_equal( [
#         {"jsonrpc"=>"2.0", "error"=>{"code"=>-32600, "message"=>"invalid JSON"}, "id"=>nil},
#         {"jsonrpc"=>"2.0", "error"=>{"code"=>-32600, "message"=>"invalid JSON"}, "id"=>nil},
#         {"jsonrpc"=>"2.0", "error"=>{"code"=>-32600, "message"=>"invalid JSON"}, "id"=>nil}
#     ], reply )
#   end
# 
#   def test_13_rpc_call_Batch
#     reply = send_request '[
#       {"jsonrpc": "2.0", "method": "sum", "params": [1,2,4], "id": "1"},
#       {"jsonrpc": "2.0", "method": "notify_hello", "params": [7]},
#       {"jsonrpc": "2.0", "method": "subtract", "params": [42,23], "id": "2"},
#       {"foo": "boo"},
#       {"jsonrpc": "2.0", "method": "foo.get", "params": {"name": "myself"}, "id": "5"},
#       {"jsonrpc": "2.0", "method": "get_data", "id": "9"}
#     ]'
#     assert_equal( [
#       {"jsonrpc"=>"2.0", "result"=>7, "id"=>"1"},
#       {"jsonrpc"=>"2.0", "result"=>19, "id"=>"2"},
#       {"jsonrpc"=>"2.0", "error"=>{"code"=>-32600, "message"=>"invalid JSON"}, "id"=>nil},
#       {"jsonrpc"=>"2.0", "error"=>{"code"=>-32601, "message"=>"method not found."}, "id"=>"5"},
#       {"jsonrpc"=>"2.0", "result"=>["hello", 5], "id"=>"9"}
#     ], reply )
#   end
# 
#   def test_14_rpc_call_Batch_all_notifications
#     reply = send_request '[
#       {"jsonrpc": "2.0", "method": "notify_sum", "params": [1,2,4]},
#       {"jsonrpc": "2.0", "method": "notify_hello", "params": [7]}
#     ]'
#     assert_equal( nil, reply )
#   end

end
