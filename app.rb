require 'bundler/setup'
Bundler.require

EventMachine.set_max_timers 1_250_000

DB = Redis.new
DB.set :connections, 0

module FormatHelper
  def humanize_number n
    n.to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, '\\1,')
  end
  module_function :humanize_number
end

class App < E
  map '/'

  # index and status_watcher actions should return event-stream content type
  before :index, :status_watcher do
    content_type 'text/event-stream'
  end

  def index
    stream :keep_open do |stream|

      # communicate to client every 15 seconds
      timer = EM.add_periodic_timer(15) {stream << "\0"}

      stream.errback do      # when connection closed/errored:
        DB.decr :connections # 1. decrement connections amount by 1
        timer.cancel         # 2. cancel timer that communicate to client
      end
      
      # increment connections amount by 1
      DB.incr :connections
    end
  end

  # frontend for status watchers - http://localhost:5252/status
  def status
    render
  end

  # backend for status watchers
  def status_watcher
    stream :keep_open do |stream|
      # adding a timer that will update status watchers every second
      timer = EM.add_periodic_timer(1) do
        connections = FormatHelper.humanize_number(DB.get :connections)
        stream << "data: %s\n\n" % connections
      end
      stream.errback { timer.cancel } # cancel timer if connection closed/errored
    end
  end

  def get_ping
  end
end
