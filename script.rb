# frozen_string_literal: true

require 'nokogiri'
require 'httparty'
require 'set'

# Sitemap
class Sitemap
  def initialize(base, file_path)
    @visitados = Set.new
    @data_url_host = get_data_url(base)
    @site_map = {}
    get_references(base)
    save!(file_path)
  end

  def get_data_url(url)
    rs = {}
    begin
      uri = URI(url)
      rs = { 'base': uri.host, 'path': uri.path, 'protocol': uri.scheme,
             'fragment': uri.fragment }
    rescue
      return {}
    end

    rs
  end

  def get_hash_name(data_url)
    name = data_url[:path].split('/')[0..-2].join('/')
    return '/' if name.empty?

    name
  end

  def local?(host, data_url)
    host == data_url[:base]
  end

  def build_full_url(base_url, url)
    return url if %r{^https?:/{2}}.match? url

    begin
      URI.join(base_url, url).to_s
    rescue URI::InvalidURIError
      return nil
    end
  end

  def get_links(url)
    response = HTTParty.get(url)
    begin
      html = Nokogiri::HTML(response)
    rescue
      return []
    end
    html.css('a')
  end

  def get_references(base_url)
    get_links(base_url).each do |o|
      next unless o['href']

      url = build_full_url(base_url, o['href'])
      data_url = get_data_url(url)
      next unless url
      next if @visitados.include? data_url[:path]
      next unless local?(@data_url_host[:base], data_url)
      next if data_url[:fragment]

      puts url
      visit(url, data_url)
    end
  end

  def visit(url, data_url)
    @visitados.add(data_url[:path])
    field_hash(data_url)
    get_references url
  end

  def field_hash(data_url)
    path = data_url[:path].split('/')
    hash = @site_map
    path.each do |o|
      field_name = '/' + o
      hash[field_name] = {} unless hash[field_name]
      hash = hash[field_name]
    end

    hash
  end

  def save!(file_path)
    @file = File.open(file_path + '/result.json', 'w')
    @file.puts(@site_map.to_json)
    @file.close
  end
end

Sitemap.new(ENV['site'], ENV['path'])
