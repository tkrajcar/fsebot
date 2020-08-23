require 'discordrb/webhooks'
require 'dotenv/load'
require 'nokogiri'
require 'open-uri'
require './util'
require 'bigdecimal/util'
require 'money'
require 'monetize'

I18n.enforce_available_locales = false

Money.default_currency = 'USD'

client = Discordrb::Webhooks::Client.new(url: ENV['WEBHOOK_URL'])

FileUtils.cp("data.json.dist","data.json") unless File.exists?("data.json")

data = JSON.parse(File.read("data.json"))
newd = {}
messages = []
puts "Reading data from #{data["timestamp"]}."

# check $ balances
doc = Nokogiri::XML(open(fse_url('statistics')))

unless doc.css("Bank_balance").text.empty? || doc.css("Personal_balance").text.empty?
  newd["funds"] = (doc.css("Bank_balance").text.to_money + doc.css("Personal_balance").text.to_money)

  old_funds = data["funds"].to_money
  if newd["funds"] != old_funds
    diff = newd["funds"] - old_funds
    messages.push "Funds #{diff > 0 ? 'increased' : 'decreased'} by #{diff.abs.format} to #{newd["funds"].format}."
  end
end

# check aircraft location
doc = Nokogiri::XML(open(fse_url('aircraft')))
doc.css("Aircraft").each do |ac|
  reg = ac.css("Registration").text
  old_location = data["#{reg}_location"] || "Who Knows"
  new_location = ac.css("Location").text
  newd["#{reg}_location"] = new_location
  rented_by = ac.css("RentedBy").text
  if old_location != new_location
    if new_location == "In Flight"
      messages.push "#{reg} departed #{old_location}, flown by #{rented_by}."
    elsif old_location == "In Flight"
      messages.push "#{reg} arrived at #{new_location}."
    else
      messages.push "#{reg} is now located at #{new_location} instead of #{old_location}."
    end
  end
end

messages.each do |msg|
  client.execute do |builder|
    # builder.avatar_url = ENV['BOT_AVATAR_URL'] if ENV['BOT_AVATAR_URL']
    # builder.username = ENV['BOT_NAME'] || "FSEBot"
    builder.content = msg
  end
end

newd["timestamp"] = DateTime.now

# save out data
out_file = File.new("data.json", "w")
out_file.puts newd.to_json
out_file.close


