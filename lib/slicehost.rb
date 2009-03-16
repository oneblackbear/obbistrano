require 'rubygems'
require 'activeresource'
 
TTL = 86400
API_PASSWORD = fetch "slicehost_api_key", false

class Record < ActiveResource::Base
  self.site = "https://#{API_PASSWORD}@api.slicehost.com/" 
end
 
class Zone < ActiveResource::Base
  self.site = "https://#{API_PASSWORD}@api.slicehost.com/" 
end
 
class Slice < ActiveResource::Base
  self.site = "https://#{API_PASSWORD}@api.slicehost.com/" 
end