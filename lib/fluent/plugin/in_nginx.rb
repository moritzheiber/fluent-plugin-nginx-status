#
# Fluent
# 
# 
#
#
#
#
class NginxTimer < Fluent::Input
  # First, register the plugin. NAME is the name of this plugin
  # and identifies the plugin in the configuration file.
  Fluent::Plugin.register_input('nginx_status', self)

  # Load Modules
  require 'net/http'
  require 'uri'

  class TimerWatcher < Coolio::TimerWatcher
    def initialize(interval, repeat, log, &callback)
      @callback = callback
      @log = log
      super(interval, repeat)
    end

    def on_timer
      @callback.call

    rescue
      # TODO log?
      @log.error $!.to_s
      @log.error_backtrace
    end
  end

  # This method is called before starting.
  # 'conf' is a Hash that includes configuration parameters.
  # If the configuration is invalid, raise Fluent::ConfigError.
  def configure(conf)
    super
    # Send a info event to the output
    $log.info "Nginx status monitor initializing"

    # Default port is http
    @tag = conf['tag'] || 'nginx.status'

    # Nginx host
    @scheme = conf['scheme'] || 'http'

    # Nginx host
    @host = conf['host'] || 'localhost'

    # Default port is http
    @port = conf['port'] || 80

    # Nginz status page path
    @path = conf['path'] || 'nginx_status'

    #Interval for the timer object, defaults 1s
    @interval = conf['interval'] || 1
  end

  # This method is called when starting.
  # Open sockets or files and create a thread here.
  def start
    super

    # Create a new timer loop
    @loop = Coolio::Loop.new

    # Create a new timer entity
    @timer = TimerWatcher.new(@interval, true, log, &method(:on_timer))

    # Attach the timer to the looper
    @loop.attach(@timer)

    # Run the timer object within a new thread
    @thread = Thread.new(&method(:run))

    # Logging
    $log.info "Nginx status monitor starting"
  end

  # Sub-thread run method
  def run
    @loop.run
   rescue => e
    $log.error "unexpected error", :error=> e.to_s
    $log.error_backtrace
  end

  # On timer method
  def on_timer
    # Create a connection
    uri = URI.parse("http://127.0.0.1:80/nginx_status")
    connection = Net::HTTP.new(uri.host, uri.port)

    # # Are we going over ssl
    if @port == 443
    #   # Go over https, but we have not implemented cert validation
    #   # so skip verification.
      connection.use_ssl = true
      connection.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end

    # Fetch the response
    response = connection.get(uri.path)

    # Validate a response
    if response.code != "200"
      $log.error "Nginx status page failing, response code: " + response.code.to_s
      return
    end

    if m = response.body.to_s.match(/^[a-zA-Z\s]+\:\s([0-9]+?)\s\n[a-z\s]+([0-9]+)\s([0-9]+)\s([0-9]+)\s\n[a-zA-Z\:?]+\s([0-9]+)\s[a-zA-Z\:?]+\s([0-9]+)\s[a-zA-Z\:?]+\s([0-9]+)/)
      # m.captures[0] = active
      # m.captures[1] = accepted
      # m.captures[2] = handled
      # m.captures[3] = total
      # m.captures[4] = reading
      # m.captures[5] = writing
      # m.captures[6] = waiting
      
      record = {
        "active"   => m.captures[0],
        "accepted" => m.captures[1],
        "handled"  => m.captures[2],
        "total"    => m.captures[3],
        "reading"  => m.captures[4],
        "writing"  => m.captures[5],
        "waiting"  => m.captures[6],
      }

      Fluent::Engine.emit(@tag, Time.now.to_i, record)
    end

    # $log.info response.body
   rescue => e
    $log.error "Unable to fetch status page", :error=> e.to_s
  end

  # This method is called when shutting down.
  # Shutdown the thread and close sockets or files here.
  def shutdown
    @loop.watchers.each {|w| w.detach }
    @loop.stop
    @thread.join
    $log.info "shutdown nginx_status"
  end
end