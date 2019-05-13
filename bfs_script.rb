# frozen_string_literal: true

require 'nokogiri'
require 'httparty'
require 'set'

# Sitemap
class Sitemap
  def initialize(base, file_path, find_same_path = false, sleep_time = 0)
    @visiteds = Set.new
    @data_url_host = get_data_url(base)
    @site_map = {}
    @emails = Set.new
    @link_emails = {}
    @find_same_path = find_same_path
    @sleep_time = sleep_time.to_i
    @references_queue = []
    init(base)
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

  def init(url)
    data_url = get_data_url(url)
    @references_queue.push([url, data_url])
    run_search
  end

  def run_search
    while @references_queue.size.positive?
      reference = @references_queue.shift
      visit(*reference)
    end
  end

  def visit(url, data_url)
    puts url
    @visiteds.add(data_url[:path])
    field_hash(data_url)
    search url
    sleep @sleep_time
  end

  def search(base_url)
    html = get_html(base_url)
    find_emails(base_url, html.to_s)

    get_links(html).each do |o|
      next unless o['href']

      url = build_full_url(base_url, o['href'])
      data_url = get_data_url(url)
      next unless valid?(url, data_url)

      @visiteds.add(data_url[:path])
      puts "adicionado ---> #{url}"
      @references_queue.push([url, data_url])
    end
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
    rescue
      return nil
    end
  end

  def find_emails(url, content)
    emails = content.scan(/[\w+\.?]+@[a-z0-9]+[\.[a-z0-9]+]*\.[a-z]+/i)
    tmp_emails = Set.new(emails.reject { |o| @emails.include? o }).to_a
    @emails.merge(emails)
    @link_emails[url] = tmp_emails if tmp_emails.size.positive?
  end

  def get_links(html)
    return [] unless html

    html.css('a')
  end

  def get_html(url)
    begin
      response = HTTParty.get(url)
      return Nokogiri::HTML(response)
    rescue
      return nil
    end
  end

  def valid?(url, data_url)
    return false unless url
    return false if @visiteds.include? data_url[:path]
    return false unless local?(@data_url_host[:base], data_url)
    return false if data_url[:fragment]
    return false if @find_same_path && !same_path?(data_url)

    true
  end

  def save!(file_path)
    save_in_file(file_path + '/routes.json', @site_map.to_json)
    save_in_file(file_path + '/emails.json', @link_emails.to_json)
  end

  def save_in_file(path, content)
    file = File.open(path, 'w')
    file.puts(content)
    file.close
  end
end

Sitemap.new(ENV['site'], ENV['path'], ENV['same_path'], ENV['sleep_time'])
