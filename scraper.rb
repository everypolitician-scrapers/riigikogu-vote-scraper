
# Fetch voting information from riigikogu.ee

require 'json'
require 'scraperwiki'
require 'nokogiri'
require 'open-uri'
# require 'open-uri/cached'
# OpenURI::Cache.cache_path = '/tmp/open-uri'

@CALENDAR = 'http://www.riigikogu.ee/?year=2014&op=ems&page=haaletus_kalender&navbar=no&op2=print&year=%d'

def vote_dates(year)
  # Find links like ?op=ems&amp;page=haaletus_paev&amp;paev=2014-01-14&amp;
  doc = Nokogiri::HTML(open(@CALENDAR % year).read)
  doc.xpath("//a[contains(@href,'haaletus_paev')]").map { |link| link['href'][/paev=(\d{4}-\d{2}-\d{2})/, 1] }
end

@DAY = 'http://www.riigikogu.ee/index.php?op=ems&page=haaletus_paev&op2=print&paev=%s'
def day_votes(date)
  doc = Nokogiri::HTML(open(@DAY % date).read)
  doc.css('table.List tr').drop(1).map do |tr| 
    row = tr.css('td') 
    link = row[0].at('a')
    {
      time: link.text,
      id: link['href'][/hid=([\w\-]+)/,1],
      sisu: row[5].text,
      eelnou: row[6].text,
      oelnou_id: ((row[6].at('a') || {})['href'] || "")[/eid=([\w\-]+)/,1],
    }
  end
end

@ROLL = 'http://www.riigikogu.ee/index.php?op=ems&page=haaletus&hid=%s&op2=print'
def rollcall(id)
  doc = Nokogiri::HTML(open(@ROLL % id).read)
  doc.css('table.List tr').drop(1).map do |tr|
    row = tr.css('td')
    {
      voteid: id,
      voter: row[1].text,
      option: row[2].text,
      grouping: row[3].text,
    }
  end
end

def vote_option (str)
  return 'yes' if str == 'poolt'
  return 'no' if str == 'vastu'
  return 'abstain' if str == 'erapooletu'
  return 'absent' if str == 'puudub'
  return 'present' if str =~ /ei h.*letanud/
  raise "Unknown vote option: #{str}"
end

vote_dates(2014).sort.reverse.take(1).each do |day|
  day_votes(day).compact.each do |vote|

    unless (ScraperWiki.select('* FROM data WHERE voteid=?', vote[:id]).empty? rescue true) 
      puts "Skipping #{vote[:id]}"
      next
    end

    data = {
      voteid: vote[:id],
      time: "#{day} #{vote[:time]}",
      context: vote[:eelnou],
      context_src: vote[:eelnou_id],
      classification: vote[:sisu],
    }
    puts "Adding #{vote[:id]}"
    ScraperWiki.save_sqlite([:voteid], data)

    rollcall = rollcall(vote[:id])
    ScraperWiki.save_sqlite([:voteid,:voter], rollcall, 'vote')
  end
end


