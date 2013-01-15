module EventMachine::JsonRPC

  class Server < EM::Connection
    attr_reader :encoder

    def initialize(*options)
      parser_options = options.first || {}

      if parser_options[:symbolize_keys]
        @key_jsonrpc = :jsonrpc
        @key_id = :id
        @key_method = :method
        @key_params = :params
      else
        @key_jsonrpc = KEY_JSONRPC
        @key_id = KEY_ID
        @key_method = KEY_METHOD
        @key_params = KEY_PARAMS
      end

      @parser = Yajl::Parser.new parser_options
      @parser.on_parse_complete = method(:obj_parsed)

      @state = :data
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
        send_data PARSING_ERROR_RESPONSE
        close_connection_after_writing
        @state = :ignore
        parsing_error data, e
      end
    end

    def obj_parsed(obj)
      @encoder ||= Yajl::Encoder.new

      case obj
      # Individual request/notification.
      when Hash
        process(obj)
      # Batch: multiple requests/notifications in an array.
      # NOTE: Not implemented as it doesn't make sense using JSON RPC over pure TCP / UnixSocket.
      when Array
        send_data BATCH_NOT_SUPPORTED_RESPONSE
        close_connection_after_writing
        @state = :ignore
        batch_not_supported_error obj
      end
    end

    def process(obj)
      is_request = obj.has_key?(@key_id)
      id = obj[@key_id]

      if is_request
        unless id.is_a? String or id.is_a? Fixnum or id.is_a? NilClass
          invalid_request obj, CODE_INVALID_REQUEST, MSG_INVALID_REQ_ID
          reply_error nil, CODE_INVALID_REQUEST, MSG_INVALID_REQ_ID
          return false
        end
      end

      unless obj[@key_jsonrpc] == "2.0"
        invalid_request obj, CODE_INVALID_REQUEST, MSG_INVALID_REQ_JSONRPC
        reply_error id, CODE_INVALID_REQUEST, MSG_INVALID_REQ_JSONRPC
        return false
      end

      unless (method = obj[@key_method]).is_a? String
        invalid_request obj, CODE_INVALID_REQUEST, MSG_INVALID_REQ_METHOD
        reply_error id, CODE_INVALID_REQUEST, MSG_INVALID_REQ_METHOD
        return false
      end

      if (params = obj[@key_params])
        unless params.is_a? Array or params.is_a? Hash
          invalid_request obj, CODE_INVALID_REQUEST, MSG_INVALID_REQ_PARAMS
          reply_error id, CODE_INVALID_REQUEST, MSG_INVALID_REQ_PARAMS
          return false
        end
      end

      if is_request
        receive_request Request.new(self, id, method, params)
      else
        receive_notification method, params
      end
    end

    # This method must be overriden in the user's inherited class.
    def receive_request(request)
      puts "request received:\n#{request.inspect}"
    end

    # This method must be overriden in the user's inherited class.
    def receive_notification(method, params)
      puts "notification received (method: #{method.inspect}, params: #{params.inspect})"
    end

    def reply_error(id, code, message)
      send_data @encoder.encode({
        KEY_JSONRPC => VALUE_VERSION,
        KEY_ID => id,
        KEY_ERROR => {
          KEY_CODE => code,
          KEY_MESSAGE => message
        }
      })
    end

    # This method could be overriden in the user's inherited class.
    def parsing_error(data, exception)
      $stderr.puts "parsing error:\n#{exception.message}"
    end

    # This method could be overriden in the user's inherited class.
    def batch_not_supported_error(obj)
      $stderr.puts "batch request received but not implemented"
    end

    # This method could be overriden in the user's inherited class.
    def invalid_request(obj, code, message=nil)
      $stderr.puts "error #{code}: #{message}"
    end


    class Request
      attr_reader :rpc_method, :params, :id

      def initialize(conn, id, rpc_method, params)
        @conn = conn
        @id = id
        @rpc_method = rpc_method
        @params = params
      end

      def reply_result(result)
        return nil if @conn.error?

        response = {
          KEY_JSONRPC => VALUE_VERSION,
          KEY_ID => @id,
          KEY_RESULT => result
        }

        # Send the response in chunks (good in case of a big response).
        begin
          @conn.encoder.encode(response) do |chunk|
            @conn.send_data(chunk)
          end
          return true
        rescue Yajl::EncodeError => e
          reply_internal_error "response encode error: #{e.message}"
          return false
        end
      end

      def reply_internal_error(message=nil)
        return nil if @conn.error?
        @conn.reply_error(@id, CODE_INTERNAL_ERROR, message || MSG_INTERNAL_ERROR)
      end

      def reply_method_not_found(message=nil)
        return nil if @conn.error?
        @conn.reply_error(@id, CODE_METHOD_NOT_FOUND, message || MSG_METHOD_NOT_FOUND)
      end

      def reply_invalid_params(message=nil)
        return nil if @conn.error?
        @conn.reply_error(@id, CODE_INVALID_PARAMS, message || MSG_INVALID_PARAMS)
      end

      def reply_custom_error(code, message)
        return nil if @conn.error?
        unless code.is_a? Integer and (-32099..-32000).include? code
          raise ArgumentError, "code must be an integer between -32099 and -32000"
        end
        @conn.reply_error(@id, code, message)
      end
    end  # class Request

  end  # class Server


  def self.start_tcp_server(addr, port, handler, options=nil, &block)
    raise Error, "EventMachine is not running" unless EM.reactor_running?
    EM.start_server addr, port, handler, options, &block
  end

  def self.start_unix_domain_server(filename, handler, options=nil, &block)
    raise Error, "EventMachine is not running" unless EM.reactor_running?
    EM.start_unix_domain_server filename, handler, options, &block
  end

end
