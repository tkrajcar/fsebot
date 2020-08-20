def fse_url(param)
  "https://server.fseconomy.net/data?userkey=#{ENV['USER_KEY']}&format=xml&query=#{param}&search=key&readaccesskey=#{ENV['GROUP_KEY']}"
end
