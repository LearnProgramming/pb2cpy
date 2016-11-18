#!/usr/bin/env ruby

# tmp todo
# ban
# kick
# quiet
# unban
# unquiet
# add op
# remove op
# decloak

require 'cinch'
require 'net/http'
require 'json'

if ARGV[0] == nil then
    abort('usage: ./bot.rb [config file]')
end

config = JSON.parse(File.open(ARGV[0], 'r').read)
$factoids = {}
$admins = []
$channel_actions = {}

bot = Cinch::Bot.new do
    configure do |conf|
        conf.server = config['server']
        conf.port = config['port']

        conf.messages_per_second = config['messages_per_second']
        conf.sasl.username = config['username']
        conf.sasl.password = config['password']
        conf.ssl.use = config['ssl']
        conf.channels = config['channels']
        conf.nick = config['nick']
        conf.realname = config['realname']
        conf.user = config['user']
    end

    on :op do |msg, nick|
        if msg.user.nick == 'ChanServ' and nick == config['nick'] then
            for action in $channel_actions[msg.channel.name] do
                command, mask = action.split

                case command
                when 'ban'
                    Channel(msg.channel.name).ban(mask) unless mask == nil
                when 'quiet'
                    msg.bot.irc.send "MODE #{msg.channel.name} +q #{mask}"
                when 'kick'
                    Channel(msg.channel.name).kick(mask) unless mask == nil
                when 'unban'
                    Channel(msg.channel.name).unban(mask) unless mask == nil
                when 'unquiet'
                    msg.bot.irc.send "MODE #{msg.channel.name} -q #{mask}"
                end
            end

            $channel_actions[msg.channel.name] = []
            Channel(msg.channel.name).deop config['nick']
        end
    end

    on :message, /((http:\/\/)?pastebin\.com\/\S*)/ do |msg, pblink|
        uri = URI(pblink)
        paste = Net::HTTP.get(uri.host, "/raw#{uri.path}")

        if paste != '' then
            res = Net::HTTP.post_form(URI('https://cpy.pt/'), 'paste' => paste, 'raw' => 'false')
            token, link = res.body.chomp.split('|')
            puts "[] Delete: #{token}"
            msg.reply "repasted for #{msg.user.nick} at #{link.lstrip}"
        else
            msg.reply "God damn it #{msg.user.nick}. That link isn't valid."
        end
    end

    on :message, /\$set (\S*) is (.*)/ do |msg, factname, factvalue|
        $factoids[factname] = factvalue
        msg.reply "defined #{factname}"
    end

    on :message, /\$show (\S*)/ do |msg, factname|
        msg.reply "#{$factoids[factname]}"
    end

    on :message, /\$get (\S*)$/ do |msg, factname|
        if $factoids.key?(factname) then
            factopt = $factoids[factname].split(' | ')
            msg.reply "#{factopt[Random.rand(factopt.size)]}"
        end
    end

    on :message, /\$get (\S*) for (\S*)/ do |msg, factname, user|
        if $factoids.key?(factname) then
            factopt = $factoids[factname].split(' | ')
            msg.reply "#{user}: #{factopt[Random.rand(factopt.size)]}"
        end
    end

    on :message, /\$get rid of (\S*)/ do |msg, factname|
        factvalue = $factoids.delete factname
        msg.reply "Removed #{factname} -> #{factvalue}"
    end

    on :message, '$list' do |msg|
        msg.reply "My current factoids are: #{$factoids.collect { |key, value| key }.join ', '}"
    end

    on :message, /\$join (\S*)/ do |msg, channel|
        if $admins.include?(msg.user.authname) then
            Channel(channel).join
        end
    end

    on :message, /\$part (\S*)/ do |msg, channel|
        if $admins.include?(msg.user.authname) then
            Channel(channel).part
        end
    end

    # #<Cinch::Message @raw=":nchambers!nchambers@freenode/spooky-exception/bartender/learnprogramming.nchambers PRIVMSG ##eggnog :$kick nchambers" @params=["##eggnog", "$kick nchambers"] channel=#<Channel name="##eggnog"> user=#<User nick="nchambers">>

    on :message, /\$(ban|quiet|kick|unban|unquiet) (\S*)$/ do |msg, action, mask|
        if $admins.include?(msg.user.authname) then
            if not $channel_actions.key? msg.channel.name then
                $channel_actions[msg.channel.name] = []
            end

            $channel_actions[msg.channel.name].push "#{action} #{mask}"
            User('ChanServ').send("OP #{msg.channel.name}")
        end
    end

    on :message, /\$(ban|quiet|kick|unban|unquiet) (\S*) (\S*)/ do |msg, action, channel, mask|
        if $admins.include?(msg.user.authname) then
            if not $channel_actions.key? channel then
                $channel_actions[channel] = []
            end

            $channel_actions[channel].push "#{action} #{mask}"
            User('ChanServ').send("OP #{channel}")
        end
    end
end

raw_factoids = File.open('factoids.txt', 'r').read

for line in raw_factoids.lines do
    factname, factvalue = line.chomp.split ' ', 2
    $factoids[factname] = factvalue
end

$admins = File.open('admins.txt', 'r').read.lines.collect { |admin| admin.chomp }

at_exit do
    handle = File.open('factoids.txt', 'w')
    $factoids.each do |factname, factvalue|
        handle.puts "#{factname} #{factvalue}"
    end

    handle = File.open('admins.txt', 'w')
    $admins.each do |admin|
        handle.puts "#{admin}"
    end
end

bot.start
