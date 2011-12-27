require "./lib/em-jsonrpc/version"

Gem::Specification.new do |spec|
  spec.name = "em-jsonrpc"
  spec.version = EventMachine::JsonRPC::VERSION
  spec.date = Time.now
  spec.authors = ["Iñaki Baz Castillo"]
  spec.email = "ibc@aliax.net"
  spec.summary = "JSON RCP 2.0 client and server for EventMachine over TCP or UnixSocket"
  spec.homepage = "https://github.com/ibc/em-jsonrpc"
  spec.description =
    "em-jsonrpc provides a JSON RPC 2.0 TCP/UnixSocket client and server to be integrated within EventMachine reactor"
  spec.required_ruby_version = ">= 1.8.7"
  spec.add_dependency "eventmachine"
  spec.add_dependency "yajl-ruby", ">= 0.8.0"
  spec.files = %w{
    lib/em-jsonrpc/version.rb
    lib/em-jsonrpc/constants.rb
    lib/em-jsonrpc/server.rb
    lib/em-jsonrpc/client.rb
    test/test-em-jsonrpc-client.rb
    test/test-em-jsonrpc-server.rb
  }
  spec.has_rdoc = false
end
