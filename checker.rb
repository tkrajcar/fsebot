require 'discordrb/webhooks'
require 'dotenv/load'
require 'nokogiri'
require 'active_support/core_ext/hash'
require 'open-uri'
require './util'
require 'bigdecimal/util'
require 'money'
require 'monetize'

Money.locale_backend = :currency
Money.rounding_mode = BigDecimal::ROUND_HALF_EVEN
Money.default_currency = 'USD'

client = Discordrb::Webhooks::Client.new(url: ENV['WEBHOOK_URL'])

FileUtils.cp("data.json.dist","data.json") unless File.exists?("data.json")

data = JSON.parse(File.read("data.json"))
newd = data.clone
messages = []
puts "Reading data from #{data["timestamp"]}."

# check $ balances
doc = Nokogiri::XML(open(fse_url('statistics')))
bank_text = doc.css("Bank_balance").text
cash_text = doc.css("Personal_balance").text
unless bank_text.empty? || cash_text.empty?
  newd["funds"] = (bank_text.to_money + cash_text.to_money)

  old_funds = data["funds"].to_money
  puts "Old: #{old_funds}"
  puts "New: #{bank_text} bank and #{cash_text} cash"

  if newd["funds"] != old_funds
    diff = newd["funds"] - old_funds
    msg = ""
    msg += diff > 0 ? "📈 Funds increased " : "📉 Funds decreased "
    msg += "by #{diff.abs.format} to #{newd["funds"].format}."
    messages.push msg
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
      messages.push "🛫 #{reg} departed #{old_location}, flown by #{rented_by}."
    elsif old_location == "In Flight"
      messages.push "🛬 #{reg} arrived at #{new_location}."
    else
      messages.push "✈️ #{reg} is now located at #{new_location} instead of #{old_location}."
    end
  end
end

# check payments
xml = open(fse_url('payments')).read
#xml = open("payments.xml").read
payments_hash = Hash.from_xml(xml)
payments = payments_hash["PaymentsByMonthYear"]["Payment"]
old_payment_id = data["payment_id"].to_i || 0
new_payments = payments.select {|x| x["Id"].to_i > old_payment_id}

if new_payments.any?
  newd["payment_id"] = new_payments.first["Id"]

  # attempt to group simultaneous payments (i.e. ground crew fees) together
  new_payments_grouped = new_payments.group_by do |p|
    [
      p["Date"].to_datetime.strftime("%Y-%m-%d %H:%M"), # 0
      p["To"], # 1
      p["From"], # 2
      p["Reason"], # 3
      p["Location"], # 4
      p["Aircraft"], # 5
      p["Comment"], # 6
    ]
  end

  payment_messages = []
  new_payments_grouped.each do |g|
    amount = g[1].inject(0) {|sum,x| sum + x["Amount"].to_money}
    qty = g[1].count

    amount_string = "#{amount.format}"
    amount_string += " (#{qty} jobs)" if qty > 1

    values = g[0]

    msg = ""
    if values[1] == ENV["GROUP_NAME"] && values[2] == ENV["GROUP_NAME"]
      msg = "🔄 Self-paid #{amount_string}"
    elsif values[1] == ENV["GROUP_NAME"]
      msg = "💰 Received #{amount_string} from #{values[2]}"
    else
      msg = "💸 Paid #{amount_string} to #{values[1]}"
    end
    msg += " for #{values[3]}"
    msg += " in #{values[5]}" if (values[5] && values[5] != "")
    msg += " at #{values[4]}" if (values[4] && values[4] != "N/A" && values[4] != "null")
    msg += "."
    msg += " #{values[6]}" if values[6] != "null"

    payment_messages.push msg
  end

  messages.push payment_messages.first(15).reverse.join("\n")
end


begin
  messages.each do |msg|
    client.execute do |builder|
      # builder.avatar_url = ENV['BOT_AVATAR_URL'] if ENV['BOT_AVATAR_URL']
      # builder.username = ENV['BOT_NAME'] || "FSEBot"
      builder.content = msg
    end
  end
rescue RestClient::TooManyRequests
end

newd["timestamp"] = DateTime.now

# save out data
out_file = File.new("data.json", "w")
out_file.puts newd.to_json
out_file.close


