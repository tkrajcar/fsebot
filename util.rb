def fse_url(param)
  if param == "payments"
    "https://server.fseconomy.net/data?userkey=#{ENV['USER_KEY']}&format=xml&query=payments&search=monthyear&readaccesskey=4F7F94E6CC6F11E3&month=#{Time.now.month}&year=#{Time.now.year}"
  else
    "https://server.fseconomy.net/data?userkey=#{ENV['USER_KEY']}&format=xml&query=#{param}&search=key&readaccesskey=#{ENV['GROUP_KEY']}"
  end
end
