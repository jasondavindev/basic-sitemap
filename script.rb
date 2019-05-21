# frozen_string_literal: true

require 'nokogiri'
require 'httparty'
require 'set'

def red(text) puts "\e[31m#{text}\e[0m" end
def green(text) puts "\e[32m#{text}\e[0m" end

# Sitemap
class Sitemap
  def initialize(site_url:, output_path:, find_same_path: false, sleep_time: 0, name:)
    @data_url_host = get_data_url(site_url)
    @find_same_path = find_same_path
    @sleep_time = sleep_time.to_i
    @name = name
    bootstrap(site_url)
    save!(output_path)
  end

  def init_values
    @visiteds = Set.new
    @routes = {}
    @emails = Set.new
    @link_emails = {}
    @references_queue = []
  end

  def bootstrap(url)
    init_values
    data_url = get_data_url(url)
    enqueue_reference(url, data_url)
    start_find
  end

  def enqueue_reference(url, data_url)
    green("added URL ---> #{url}")
    @references_queue.push([url, data_url])
  end

  def get_data_url(url)
    rs = {}
    begin
      uri = URI(url)
      rs = { 'host': uri.host, 'path': uri.path, 'protocol': uri.scheme,
             'fragment': uri.fragment }
    rescue
      red("[ERROR] get data url -> #{url}")
      return {}
    end

    rs
  end

  def start_find
    while @references_queue.size.positive?
      reference = @references_queue.shift
      visit(*reference)
    end
  end

  def visit(url, data_url)
    puts url
    @visiteds.add(data_url[:path])
    create_route_hash(data_url)
    explore_url(url)
    sleep @sleep_time
  end

  def add_to_visiteds(href, path)
    @visiteds.add(href)
    @visiteds.add(path)
  end

  def explore_url(base_url)
    html = get_html(base_url)
    find_emails(base_url, html.to_s)

    get_links(html).each do |link|
      next unless link['href']

      href = link['href']
      url = build_full_url(base_url, href)
      data_url = get_data_url(url)
      next unless valid?(url, data_url, href)

      add_to_visiteds(href, data_url[:path])
      enqueue_reference(url, data_url)
    end
  end

  def create_route_hash(data_url)
    paths = data_url[:path].split('/')
    hash = @routes
    paths.each do |path|
      path_name = '/' + path
      hash[path_name] = {} unless hash[path_name]
      hash = hash[path_name]
    end
  end

  def local?(host, data_url)
    host == data_url[:host]
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
      red("[ERROR] build full url -> #{base_url} | #{url}")
      return nil
    end
  end

  def find_emails(url, content)
    emails = []
    begin
      emails = content.scan(/[\w+\.?]+@[a-z0-9]+[\.[a-z0-9]+]*\.[a-z]+/i)
    rescue
      red("[ERROR] find emails -> #{url}")
    end

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
      response = HTTParty.get(url, timeout: 5)
      return Nokogiri::HTML(response)
    rescue
      red("[ERROR] get html -> #{url}")
      return nil
    end
  end

  def media?(href)
    /jpeg|mp4|pdf|png|jpg/i.match? href.split('.')[-1]
  end

  def valid?(url, data_url, href)
    return false unless url
    return false if data_url.compact == {}
    return false if media?(href)
    return false if @visiteds.include?(href)
    return false if @visiteds.include?(data_url[:path])
    return false unless local?(@data_url_host[:host], data_url)
    return false if data_url[:fragment]
    return false if @find_same_path && !same_path?(data_url)

    true
  end

  def save!(output_path)
    save_in_file("#{output_path}/#{@name}_routes.json", @routes.to_json)
    save_in_file("#{output_path}/#{@name}_emails.json", @link_emails.to_json)
  end

  def save_in_file(path, content)
    file = File.open(path, 'w')
    file.puts(content)
    file.close
  end
end

Sitemap.new(
  site_url: ENV['site'],
  output_path: ENV['path'],
  find_same_path: ENV['same_path'],
  sleep_time: ENV['sleep_time'],
  name: ENV['name']
)
