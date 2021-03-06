#!usr/bin/env ruby

require "yaml"
require "socket"
require "timeout"
require "fileutils"

# SimpeIPC implements a simple process communication.
# @author Fabrizio Zendri
module SimpleIPC
  LOCALHOST = "127.0.0.1" 
  LENGTH_CODE = 'N'
  LENGTH_SIZE = [0].pack(LENGTH_CODE).size # E' come scrivere 4, ma faccio cosi' perche' potrebbe dipendere dalla macchina

  class Socket
    def initialize(args = {})
      @cfg = {
        :port => 5000,
        :host => LOCALHOST,
        :kind => :unix,
        :force => true 
      }
      @cfg.merge! args
      case @cfg[:kind]
      when :unix
        @socket_file = "/tmp/#{$0}.sok"
        @socket = nil
      when :udp
        @socket = UDPSocket.new
      else
        raise ArgumentError, "Either :unix or :udp allowed"
      end
      @open = false
    end
  
    def connect
      return false if @open
      case @cfg[:kind]
      when :unix
        @socket = UNIXSocket.open(@socket_file)
      when :udp
        @socket.connect(@cfg[:host],@cfg[:port])
      end
      @open = true
    end
  
    def print(string)
      @socket.print(string)
    end
  
    def listen
      case @cfg[:kind]
      when :unix
        @socket = UNIXServer.open(@socket_file).accept
      when :udp
        @socket.bind(LOCALHOST, @cfg[:port])
      end
    rescue Errno::EADDRINUSE # Cattura gli errori del tipo specificato "socket gia' in uso"
      if @cfg[:force] then
        FileUtils::rm(@socket_file)
        retry # Riprova ad eseguire il metodo
      else
        warn $! # "$!" contiene la descrizione dell'ultimo errore
      end
    end
  
    def recvfrom(bytes)
      @socket.recvfrom(bytes)
    end
  
    def recv_nonblock(bytes)
      @socket.recv_nonblock(bytes)
    end
  
    def close
      @socket.close
      @open = false
      FileUtils::rm(@socket_file) if @socket_file
    end
  
  end # Socket class

  # =====================================================================================

  class IPC
    attr_accessor :cfg
  
    def initialize(args = {})
      raise ArgumentError, "expecting an Hash" unless args.kind_of? Hash
      @cfg = {:port => 5000, :host => LOCALHOST, :timeout => 0}
      @cfg.merge! args
      @socket = Socket.new @cfg
    end
  
    # Sends something to the server
    # @param [Object] something an object
    def send(something)
      # payload e' la rappresentazione serializzata di quello che vogliamo trasferire
      if block_given? then
        payload = yield(something)
      else
        payload = YAML.dump(something)
      end
      length = [payload.size].pack(LENGTH_CODE)
    
      @socket.connect
      @socket.print length
      @socket.print payload
    
      return payload
    end
  
    def listen
      @socket.listen
    end
  
    def get
      result = nil
      begin
        if @cfg[:timeout] > 0 and !@cfg[:nonblock] then
          Timeout::timeout(@cfg[:timeout]) do |to|
            result = get_
          end
        else 
          result = get_
        end
      rescue Timeout::Error
        result = nil
      rescue Errno::EAGAIN # Riscatto l'errore nel caso NON mi arrivi un blocco
        return nil
      end

      if block_given? then
        return yield(result)
      else
        return YAML.load(result)
      end
    end
  
    def close
      @socket.close
    end
  
    # E' la versione semplice e la rendo privata, perche' mi serve un metodo un po' piu' complicata
    private
    def get_
      if @cfg[:nonblock] then
        msg, sender = @socket.recv_nonblock(LENGTH_SIZE)
      else
        msg = @socket.recvfrom(LENGTH_SIZE)[0]
      end
      length = msg.unpack(LENGTH_CODE)[0]
      msg, sender = @socket.recvfrom(length)
      return msg 
    end
  
  end # IPC Class
  
end # SimpleIPC module

# =====================================================================================
# =====================================================================================

if $0 == __FILE__ then
  
  if ARGV[0] == "server" then
    from_client = SimpleIPC::IPC.new :timeout => 10, :nonblock => true, :kind => :unix
    from_client.listen
    running = true
    while running != "stop" do
      running = from_client.get
      p running if running
      sleep 0.01
    end
  
    # p from_client.get
    # p from_client.get {|s| s.split(",").map {|v| v.to_f} }
    # p from_client.get {|s| s.unpack("N4") }
  else 
    to_server = SimpleIPC::IPC.new :kind => :unix
    to_server.send([1,2,3,"test"])
    to_server.send({:a => "test", :b => "prova"})
    to_server.send("stop")
  
    # to_server.send([1,2,3,4]) {|o| o * ","}
    # to_server.send([1,2,3,4]) {|o| o.pack("N4")}
    to_server.close
  end

  # 
  # si = SimpleIPC.new :port => 6000
  # p si
  # si.cfg[:port] = 5000
  # p si
  # 
  # obj = {:a => 1, :b => [1,2,"c"]}
  # puts si.send si

end