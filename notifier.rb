require 'rubygems'
require 'twitter/json_stream'
require 'json'
require 'yaml'

# sudo gem install twitter-stream -s http://gemcutter.org
# http://github.com/voloko/twitter-stream

# gather the rooms you are present in and and start the event loop for grabbing
# messages
def start
  rooms = get_rooms    
  lookup_table = get_room_lookup_table(rooms)
  EventMachine::run do
    rooms.each do |room_id|
      room_manager(room_id, lookup_table)
    end
  end
end


#Get the campfire configuration for the user, if it doesn't exist create it.
def get_config(config_file)  
  config = ""
  if !FileTest.exists?(config_file)
    print "What is your api key for campfire?\ndon't worry you only have to enter it once! :"
    token = gets
    print "What's the url you use for campfire chat? :"
    url = gets
    url = url.strip #get rid of \n
    url = url[0, url.length-1] if url[url.length-1, url.length] == "/" #make sure there isn't a trailing slash    
    token = token[0..token.length-2].strip  
    File.open("#{ENV['HOME']}/.campfirerc", "w") { |writer|
      writer.write("campfire_config:\n  API_KEY: #{token}")
      writer.write("\n  URL: #{url}")
    }
    config = YAML::load_file("#{ENV['HOME']}/.campfirerc")
  else 
    config = YAML::load_file(config_file)    
  end  
end

# the rooms the user is present parsed in a [[room_name,room_id]] format
def get_rooms  
  json_rooms = IO.popen("curl -u #{@config['campfire_config']['API_KEY']}:X #{@config['campfire_config']['URL']}/presence.json")  
  parsed_rooms = JSON.parse(json_rooms.readlines.first)["rooms"]
  rooms = parsed_rooms.collect {|room| [room["name"],room["id"]]}    
end

# this comes in handy when we get messages and they have a room_id but not a room name
def get_room_lookup_table(parsed_rooms)
  room_lookup = {}  
  parsed_rooms.each do |room|
    room_lookup[room[1]] = room.first
  end  
  room_lookup
end

# responsible for managing the different rooms in a separate thread as well as
# displaying errors
def room_manager(room, lookup_table)  
  Thread.new {  
    stream = Twitter::JSONStream.connect({:path => "/room/#{room[1]}/live.json", 
                                                               :host => "streaming.campfirenow.com",
                                                               :auth => "#{@config['campfire_config']['API_KEY']}:x"})           
    room_messager(stream, room, lookup_table)
    room_error(stream)
    room_max_reconnects(stream)
  }
end

#actually displays the message and relevant information through the gnome interface
def room_messager(stream, room, room_lookup)  
  stream.each_item do |item|
    begin
      message = JSON.parse(item)         
      message_content =  message["body"]
      author_id = message["user_id"]
      room_number = message["room_id"]
      room_name = room_lookup[room_number]      
      user = IO.popen("curl -u 5caa15e24a6a838aba12751b252559d093f4e172:X https://aghq.campfirenow.com/users/#{author_id}.json")
      user_name = JSON.parse(user.readlines.first)["user"]["name"]           
      system("notify-send " + %{"#{room_name}: #{user_name}"} + " " + %{" #{message_content}"})            
    rescue => e
      system("notify-send 'ERROR' '#{e.message.to_s}'")
      p e.message
    end
  end
end

def room_error(stream) 
  stream.on_error do |message|
    system("notify-send 'ERROR!!!!' '#{message.inspect}'")
    p "ERROR:#{message.inspect}"
  end
end

def room_max_reconnects(stream)
  stream.on_max_reconnects do |timeout, retries|
    system("notify-send 'ERROR' 'Tried #{retries} times to connect.'")
    p "'ERROR' 'Tried #{retries} times to connect.'"
    exit
  end  
end

# By default we create a .campfirerc for the configuration and always look there.
# grab the necessary info and lets go go go!
config_file = "#{ENV['HOME']}/.campfirerc"
@config = get_config(config_file)
start