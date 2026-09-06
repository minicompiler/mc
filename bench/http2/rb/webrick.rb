# Ruby stdlib WEBrick: a thread per connection, HTTP/1.1 keep-alive. Zero dependencies.
require 'webrick'
server = WEBrick::HTTPServer.new(BindAddress: '127.0.0.1', Port: ARGV[0].to_i,
                                 AccessLog: [], Logger: WEBrick::Log.new(File::NULL))
server.mount_proc('/') do |req, res|
  res.status = 200
  res['Content-Type'] = 'text/plain'
  res['Content-Length'] = '13'
  res.body = "hello, world\n"
end
trap('TERM') { server.shutdown }
server.start
