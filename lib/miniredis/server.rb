require 'socket'
require 'stringio'
require 'miniredis/protocol'
require 'miniredis/state'

module Miniredis
	class Server

		class Clock
			def now
				Time.now.to_f
			end

			def sleep(x)
				::Kernel.sleep x
			end
		end

		def initialize(port)
			@port = port
			@shutdown_pipe = IO.pipe
			@state = State.new(Clock.new)
		end

		def shutdown
			shutdown_pipe[1].close
		end

		def listen
			readable = []
			clients = {}
			running = true
			server = TCPServer.new(port)
			readable << server
			readable << shutdown_pipe[0]

			while running
				ready_to_read, _ = IO.select(readable + clients.keys)

				ready_to_read.each do |socket|
					case socket
					when server
						child_socket = socket.accept
						clients[child_socket] = Handler.new(child_socket)
					when shutdown_pipe[0]
						running = false
					else
						begin
							clients[socket].process!(@state)
						rescue EOFError
							clients.delete(socket)
							socket.close
						end
					end 
				end
			end
		ensure
			(readable + clients.keys).each do |socket|
				socket.close
			end
		end

		class Handler
			attr_reader :client

			def initialize(socket)
				@client = socket
				@buffer = ""
			end

			def process!(data)
				buffer << client.read_nonblock(1024)

				cmds, processed = unmarshal(buffer)
				@buffer = buffer[processed..-1]			
				# header = client.gets.to_s

				# return unless header[0] == '*'

				# num_args = header[1..-1].to_i

				# cmd = num_args.times.map do
				# 	len = client.gets[1..-1].to_i
				# 	client.read(len + 2).chomp
				# end

				cmds.each do |cmd|
					response = case cmd[0].downcase
					when 'ping' then :pong 
					when 'echo' then cmd[1]
					else state.apply_command(cmd)
					# when 'set' then state.set(*cmd[1..-1])
					# when 'get' then state.get(*cmd[1..-1])
					# when 'hset' then state.hset(*cmd[1..-1])
					# when 'hget' then state.hget(*cmd[1..-1])
					# when 'hmget' then state.hmget(*cmd[1..-1])		
					end

					client.write Miniredis::Protocol.marshal(response)
				end 
			end

			class ProtocolError < RuntimeError; end

			def unmarshal(data)
				io = StringIO.new(data)
				result = []
				processed = 0

				begin
					loop do
						header = safe_readline(io)

						raise ProtocolError unless header[0] == '*'

						n = header[1..-1].to_i

						result << n.times.map do
							raise ProtocolError unless io.readpartial(1) == '$'

							length = safe_readline(io).to_i
							safe_readpartial(io, length).tap do
								safe_readline(io)
							end
						end

						processed = io.pos
					end
				rescue ProtocolError
					processed = io.pos
				rescue EOFError
					# Incomplete command, ignore
				end

				[result, processed]
			end
		end

		def safe_readline(io)
			io.readline("\r\n").tap do |line|
				raise EOFError unless line.end_with?("\r\n")
			end
		end

		def safe_readpartial(io, length)
			io.readpartial(length).tap do |data|
				raise EOFError unless data.length == length
			end
		end

		private

		attr_reader :port

	end
end