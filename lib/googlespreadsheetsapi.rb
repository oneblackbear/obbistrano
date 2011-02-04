require 'rubygems'
require 'highline/import'
require 'net/https'
require 'gdata'
require 'pp'

class GSpreadsheetAPI 
  
  def initialize
    @email  = if defined? GOOGLE_EMAIL then GOOGLE_EMAIL else ask("Google Email Address:") { |q| q.echo = true } end
    @password = if defined? GOOGLE_PASSWD then GOOGLE_PASSWD else ask("Google account (#{@email}) password:") { |q| q.echo = "*" } end
    @search_term = if defined? GD_SEARCH_TERM then GD_SEARCH_TERM else ask("Search for:") { |q| q.echo = true } end
    @client_docs = GData::Client::DocList.new
    @client_docs.clientlogin(@email, @password)
    @spreadsheets = {}
  end
  
  def spreadsheets()    
    
    feed = @client_docs.get('http://docs.google.com/feeds/documents/private/full').to_xml
    feed.elements.each('entry') do |entry|
      if(entry.elements['title'].text.include? @search_term )
        @spreadsheets[entry.elements['id'].text] = {'id'=>entry.elements['id'].text, 'title'=>entry.elements['title'].text, 'updated'=> entry.elements['updated'].text}
        links = {}
        entry.elements.each('link') do |link|
          links[link.attribute('rel').value] = link.attribute('href').value
        end
        @spreadsheets[entry.elements['id'].text]['links'] = links
      end     
    end
    return @spreadsheets
  end

  

end


test = GSpreadsheetAPI.new
found = test.spreadsheets()