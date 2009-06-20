require 'rubygems'
require "httparty"

class GithubApi
  include HTTParty
  base_uri "https://github.com/api/v2/yaml"
  
  attr_accessor :format, :login, :token, :repo, :base_uri

  def initialize(login = nil, token = nil, format = "yaml")
    @format = format
    if login
      @login = login
      @token = token
    end
  end

  def create_repo(params)
    uri = uri = "#{self.class.base_uri}/repos/create"
    post_params = {"login"=>@login, "token"=>@token}
    self.class.post(uri, :query=>post_params.merge(params))
  end
  
  def add_collaborator(user)
    uri = "#{self.class.base_uri}/repos/collaborators/#{@repo}/add/#{user}"
    post_params = {"login"=>@login, "token"=>@token}
    self.class.post(uri, :query=>post_params)
  end
  
  def add_key(params)
    uri = "#{self.class.base_uri}/repos/key/#{@repo}/add"
    post_params = {"login"=>@login, "token"=>@token}
    params = post_params.merge(params)
    self.class.post(uri, :query=>post_params.merge(params))
  end
  
  def create_issue(params)
    uri = "#{self.class.base_uri}/issues/open/#{@login}/#{@repo}"
    post_params = {"login"=>@login, "token"=>@token}
    params = post_params.merge(params)
    self.class.post(uri, :query=>post_params.merge(params))
  end

end
 
