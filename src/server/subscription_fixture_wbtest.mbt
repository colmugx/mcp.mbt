///|
fn test_subscription(
  filter : SubscriptionFilter,
  reply : @aqueue.Queue[String],
  subscription_id : String,
) -> ActiveSubscription {
  let cancellation_token = @runtime.CancellationToken::new()
  let cancellation_registration = cancellation_token.on_cancel(fn() { () })
  {
    filter,
    reply,
    subscription_id,
    cancellation_token,
    cancellation_registration,
  }
}
