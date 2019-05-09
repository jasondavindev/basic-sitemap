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
    @emails = Set.new
    get_references(base)
    save!(file_path)
    puts @emails.to_a.to_s
  end

  def get_data_url(url)
    rs = {}
    begin
      uri = URI(url)
      rs = { 'base': uri.host, 'path': uri.path, 'protocol': uri.scheme,
             'fragment': uri.fragment }
    rescue ArgumentError
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

  def same_path?(data_url)
    host_path = @data_url_host[:path].split('/')
    url_path = data_url[:path].split('/')
    return true if host_path.size.zero?

    host_path == url_path[0..host_path.size - 1]
  end

  def build_full_url(base_url, url)
    return url if %r{^https?:/{2}}.match? url

    begin
      URI.join(base_url, url).to_s
    rescue URI::InvalidURIError
      return nil
    end
  end

  def find_emails(content)
    emails = content.scan(/[a-zA-Z0-9.!\#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*/)
    @emails.merge(emails)
  end

  def get_links(html)
    return [] unless html

    html.css('a')
  end

  def get_html(url)
    response = HTTParty.get(url)

    begin
      return Nokogiri::HTML(response)
    rescue NoMethodError
      return nil
    end
  end

  def valid?(url, data_url)
    return false unless url
    return false if @visitados.include? data_url[:path]
    return false unless local?(@data_url_host[:base], data_url)
    return false if data_url[:fragment]
    return false unless same_path?(data_url)

    true
  end

  def get_references(base_url)
    html = get_html(base_url)
    get_links(html).each do |o|
      next unless o['href']

      url = build_full_url(base_url, o['href'])
      data_url = get_data_url(url)
      next unless valid?(url, data_url)
      find_emails(html.to_s)

      visit(url, data_url)
    end
  end

  def visit(url, data_url)
    puts url
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
