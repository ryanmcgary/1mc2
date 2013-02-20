
## Aim

### Handle 1 Million Concurrent Connections using Ruby

  - App should remain responsive and be able to process at least 100 requests per second
  
  - App should consume MAX 15GB of RAM and keep load under 10 on a 8 CPU machine
  
  - App should communicate to clients every 15 seconds without any lags

## Ruby Software

**[Espresso Framework](https://github.com/espresso/espresso)** - fast and easy to use.

**[Rainbows! Web Server](http://rainbows.rubyforge.org/)** - supports streaming and forking.

**[EventMachine](https://github.com/eventmachine/eventmachine)** - mature and stable I/O library for Ruby.


Rainbows! setup:

```ruby
Rainbows! do
  use :EventMachine
  keepalive_timeout  3600*12
  worker_connections 128_000
  client_max_body_size nil
  client_header_buffer_size 512
end

worker_processes 8
```

So connections will be handled concurrently by 8 Ruby processes - 1 process per core.

If you know a way to make a single Ruby process to handle 1 million connections, feel free to repeat this test with a single Rainbows! worker or using Thin web server.


The application code:

```ruby
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
```

[More on Streaming](http://espresso.github.com/Streaming.html)


## Ruby Version and Tunings

Used **MRI 1.9.3p385** installed/managed via [rbenv](https://github.com/sstephenson/rbenv).

To make Ruby a bit faster, applied these GarbageCollector tunings:

```
# The initial number of heap slots as well as the minimum number of slots allocated.
RUBY_HEAP_MIN_SLOTS=1000000

# The minimum number of heap slots that should be available after the GC runs.
# If they are not available then, ruby will allocate more slots.
RUBY_HEAP_FREE_MIN=100000

# The number of C data structures that can be allocated before the GC kicks in.
# If set too low, the GC kicks in even if there are still heap slots available.
RUBY_GC_MALLOC_LIMIT=80000000
```

This had a spectacular impact - performance increased by about 40%

Did not try `JRuby` cause:
  - i'm not aware of any easy to use and portable `JRuby` web-server with streaming support
  - `JRuby` would for sure consume much more than 15GB of RAM

Really wanted to have this test also completed on `Rubinius 2.0.0rc1 1.9mode`, but somehow it is always segfaults after ~10,000 connections because of some `libpthread` issues. Had no time to investigate this.



## Operating System

**Ubuntu 12.04** - really easy to make it accept 1 million connections.

The only files modified was `/etc/security/limits.conf`:

```
* - nofile 1048576
```

and `/etc/sysctl.conf`:

```
net.ipv4.netfilter.ip_conntrack_max = 1048576
```

## How to Repeat

### Prepare the Server

Clone this repo:

```bash
git clone https://github.com/slivu/1mc2
```

run bundler:

```
cd 1mc2/
bundle
rbenv rehash # in case you are using rbenv
```

start redis server on default port using config coming with this repo:

```
redis-server ./redis.conf
```

start app:

```
./run
```


### Prepare Clients

To generate the load i used 50 EC2 micro instances.

Special thanks to [@ashtuchkin](https://github.com/ashtuchkin) for creating a great tool to manage EC2 instances.

Using [ec2-fleet](https://github.com/ashtuchkin/ec2-fleet) it is really easy to manage any number of instances directly from terminal.

Follow there instructions to setup your AWS. After that done, start instances:

```
./aws.js start 50
```

wait about 2 minutes.
You can see what happens by typing `./aws.js status`.

When instances ready point them to tested host:

```
./aws.js set host <ip>
```

our app running on 5252 port:

```
./aws.js set port 5252
```

set the number of connections per instance:

```
./aws set n 20000
```

Now we have 50 instances that will generate 20,000 clients each, resulting in 1,000,000 connections.

The app should start accepting connections now.

To see what happens, open a `ServerSentEvents` enabled browser(any recent Chrome/Firefox/Safari/Opera) and type `http://localhost:5252/status`

You should see the number of established connections as well as requests per second and mean response time.

## Results

<img src="https://github.com/slivu/1mc2">

As you can see, all aims achieved:

  - App remaining responsive - it is able to process about 179 requests per second
  
  - App does communicate to clients every 15 seconds - see network usage, it is about 3MB/s in/out

  - RAM usage is under 15GB and load is under 10


After all connections established i kept clients connected for about one hour.

All clients remained connected and RAM not increased(read no memory leaks).

Some graphs:

<img src="https://github.com/slivu/1mc2">

Mean response time are calculated by sending a request every second, registering the time needed for response and calculating the median of last 60 requests:

<img src="https://github.com/slivu/1mc2">

Here you can see the progress - screenshots taken every 15 seconds(history starts at 12th slide):

https://speakerdeck.com/slivu/

<hr>

### Author - [Silviu Rusu](https://github.com/slivu).  License - [MIT](https://github.com/espresso/espresso/blob/master/LICENSE).







