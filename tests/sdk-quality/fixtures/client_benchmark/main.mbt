///|
async fn main {
  let url = @env.get_env_var("MCP_BENCH_URL").unwrap_or(
    "http://127.0.0.1:3000/mcp",
  )
  let client = @mcp.MCPClient::connect_http(
    url=url,
    name="colmugx-mcp-throughput-client",
    version="0.18.4",
  )
  defer @async.protect_from_cancel(() => client.close())

  let requests_per_worker = 500
  for concurrency in [1, 4, 16, 64] {
    let failures = Ref(0)
    let started = @env.now()
    @async.with_task_group(group => {
      for _ in 0..<concurrency {
        ignore(group.spawn(async fn() {
          for _ in 0..<requests_per_worker {
            try
              ignore(
                client.call_tool(
                  "bench_echo",
                  arguments="{\"message\":\"mcp-benchmark\"}",
                ),
              )
            catch {
              _ => failures.val = failures.val + 1
            } noraise {
              _ => ()
            }
          }
        }))
      }
    })
    let elapsed_ms = (@env.now() - started).to_double()
    let total = concurrency * requests_per_worker
    let throughput = if elapsed_ms > 0.0 {
      total.to_double() * 1000.0 / elapsed_ms
    } else {
      0.0
    }
    println(
      "{\"concurrency\":\{concurrency},\"requests\":\{total},\"elapsed_ms\":\{elapsed_ms},\"throughput_rps\":\{throughput},\"errors\":\{failures.val}}",
    )
  }
}
