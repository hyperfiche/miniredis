require 'spec_helper'

describe 'Miniredis', :acceptance do
	it 'support hashes' do
		with_server do
			client.hset("myhash", "abc", "123")
			client.hset("myhash", "def", "456")
			expect(client.hmget("myhash", "abc", "def")).to eq(["123", "456"])
		end
	end
end