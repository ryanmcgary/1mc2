Rainbows! do
  use :EventMachine
  keepalive_timeout  3600*12
  worker_connections 128_000
  client_max_body_size nil
  client_header_buffer_size 512
end

worker_processes 8
stderr_path "./logs/error.log"
stdout_path "./logs/output.log"
