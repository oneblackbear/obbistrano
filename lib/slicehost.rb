require 'rubygems'
require 'activeresource'
 
TTL = 86400

class Record < ActiveResource::Base
  self.site = "https://#{SLICEHOST_API_PASSWORD}@api.slicehost.com/" 
end
 
class Zone < ActiveResource::Base
  self.site = "https://#{SLICEHOST_API_PASSWORD}@api.slicehost.com/" 
end
 
class Slice < ActiveResource::Base
  self.site = "https://#{SLICEHOST_API_PASSWORD}@api.slicehost.com/" 
end