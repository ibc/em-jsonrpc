require "eventmachine"
require "yajl"
require "securerandom"

require "em-jsonrpc/version"
require "em-jsonrpc/constants"


module EventMachine::JsonRPC

  class Client < EM::Connection
    DEFAULT_REQUEST_TIMEOUT = 2

    attr_reader :pending_requests
    
    def initialize(host, port, request_timeout = nil, parser_options = {})
      @host = host
      @port = port
      @request_timeout = request_timeout || DEFAULT_REQUEST_TIMEOUT
      @parser_options = parser_options
           
      if parser_options and parser_options[:symbolize_keys]
        @key_jsonrpc = :jsonrpc
        @key_id = :id
        @key_result = :result
        @key_error = :error
        @key_code = :code
        @key_message = :message
      else
        @key_jsonrpc = KEY_JSONRPC
        @key_id = KEY_ID
        @key_result = KEY_RESULT
        @key_error = KEY_ERROR
        @key_code = KEY_CODE
        @key_message = KEY_MESSAGE
      end
      
      @pending_requests = {}
      @connected = false
    end

    def post_init
      puts "--- post_init(), @connected = #{@connected}"
      @encoder = Yajl::Encoder.new
    end

    def connection_completed
      puts "--- connection_completed()"
      @connected = true
      @parser = Yajl::Parser.new  @parser_options
      @parser.on_parse_complete = method(:obj_parsed)
      @state = :data
      ready
    end

    def unbind
      puts "--- unbind(), @connected = #{@connected}"
      @pending_requests.clear

      if @connected
        connection_terminated
      else
        connection_failed
      end
      @connected = false
    end

    def connected?
      @connected
    end

    def ready
    end

    def connection_failed
    end

    def connection_terminated
    end

    def connect_again
      reconnect @host, @port
    end

    def send_request(method, params=nil)
      puts "--- send_request()"
      id = SecureRandom.hex 4
      request = Request.new self, id
      request.timeout @request_timeout
      @pending_requests[id] = request

      jsonrpc_request = {
        KEY_JSONRPC => VALUE_VERSION,
        KEY_ID => id,
        KEY_METHOD => method
      }
      jsonrpc_request[KEY_PARAMS] = params if params
      send_data @encoder.encode jsonrpc_request
      
      return request
    end

    def receive_data(data)
      case @state
      when :data
        parse_data(data)
      when :ignore
        nil
      end    
    end
    
    def parse_data(data)
      begin
        @parser << data
      rescue Yajl::ParseError => e
        close_connection
        @connected = false
        @state = :ignore
        parsing_error
        cancel_pending_requests "response parsing error"
      end
    end

    def obj_parsed(obj)
      case obj
      when Hash
        process(obj)
      when Array
        # Do nothing, just ignore.
      end
    end

    def process(obj)
      return unless (id = obj[@key_id]) and id.is_a? String
      return unless request = @pending_requests[id]

      request.delete
      
      unless obj[@key_jsonrpc] == "2.0"
        request.fail :invalid_response, "invalid response: doesn't include \"jsonrpc\": \"2.0\""
        return
      end

      if obj.has_key? @key_result
        request.succeed obj[@key_result]
        return
      elsif error = obj[@key_error]
        if error.is_a? Hash and (code = error[@key_code]) and (message = error[@key_message])
          request.fail :error, error
          return
        else
          request.fail :invalid_response, "invalid response: \"error\" is not a valid object"
          return
        end
      else
        request.fail :invalid_response, "invalid response: not valid \"result\" or \"error\""
        return
      end
    end

    def parsing_error
    end
    
    def cancel_pending_requests description
      @pending_requests.each_value do |request|
        request.fail :canceled, "request canceled: #{description}"
      end
      @pending_requests.clear
    end


    class Request
      include EM::Deferrable

      def initialize(client, id)
        @client = client
        @id = id
      end

      def delete
        @client.pending_requests.delete @id
      end
      
      # Override EM::Deferrable#timeout method so the errback is executed passing
      # a :request_timeout single argument.
      # Also, the request is removed from the list of pending requests.
      def timeout seconds
        cancel_timeout
        me = self
        @deferred_timeout = EM::Timer.new(seconds) do
          me.delete
          me.fail :request_timeout
        end
      end
    end  # class Request

  end  # class Client


  class ConnectionError < StandardError ; end


  def self.connect_tcp(host, port, handler, request_timeout=nil, parser_options={}, &block)
    raise Error, "EventMachine is not running" unless EM.reactor_running?

    EM.connect(host, port, handler, host, port, request_timeout, parser_options, &block)
  end

end


