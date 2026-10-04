///|
/// Identity established by a trusted server-side authenticator, never by request metadata.
pub(all) struct Principal {
  id : String
  scopes : Array[String]
  attributes : Map[String, Json]
} derive(Eq, Debug)

///|
pub extend Principal with Eq::{equal, not_equal}

///|
pub extend Principal with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn Principal::new(
  id : String,
  scopes? : Array[String] = [],
  attributes? : Map[String, Json] = {},
) -> Principal {
  { id, scopes, attributes, }
}

///|
/// Request-local cooperative cancellation, shared with its transport and task owner.
pub struct CancellationToken {
  mut cancelled : Bool
  callbacks : Map[Int, () -> Unit]
  mut next_callback_id : Int
}

///|
pub fn CancellationToken::new() -> CancellationToken {
  { cancelled: false, callbacks: Map([]), next_callback_id: 0, }
}

///|
pub fn CancellationToken::is_cancelled(self : CancellationToken) -> Bool {
  self.cancelled
}

///|
/// Register runtime cleanup. Late registrations run immediately after cancellation.
pub fn CancellationToken::on_cancel(
  self : CancellationToken,
  callback : () -> Unit,
) -> CancellationRegistration {
  let id = self.next_callback_id
  self.next_callback_id += 1
  if self.cancelled {
    callback()
  } else {
    self.callbacks.set(id, callback)
  }
  { token: self, id, }
}

///|
/// Dispose registrations when their request/task completes to avoid retaining finished work.
pub struct CancellationRegistration {
  token : CancellationToken
  id : Int
}

///|
pub fn CancellationRegistration::dispose(
  self : CancellationRegistration,
) -> Unit {
  self.token.callbacks.remove(self.id)
}

///|
pub fn CancellationToken::cancel(self : CancellationToken) -> Unit {
  if self.cancelled {
    return
  }
  self.cancelled = true
  let callbacks = self.callbacks.values().to_array()
  self.callbacks.clear()
  for callback in callbacks {
    callback()
  }
}

///|
pub(all) suberror RequestCancelled {
  RequestCancelled
} derive(Debug)

///|
pub extend RequestCancelled with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn CancellationToken::throw_if_cancelled(
  self : CancellationToken,
) -> Unit raise RequestCancelled {
  if self.cancelled {
    raise RequestCancelled
  }
}

///|
/// Reports progress through the current request's transport; direct dispatch defaults to a no-op.
pub struct ProgressReporter {
  send : async (Double, Double?, String?) -> Unit
  cancellation_token : CancellationToken
}

///|
pub fn ProgressReporter::new(
  send : async (Double, Double?, String?) -> Unit,
  cancellation_token? : CancellationToken = CancellationToken::new(),
) -> ProgressReporter {
  { send, cancellation_token, }
}

///|
pub async fn ProgressReporter::report(
  self : ProgressReporter,
  progress : Double,
  total? : Double,
  message? : String,
) -> Unit {
  self.cancellation_token.throw_if_cancelled()
  (self.send)(progress, total, message)
}

///|
/// Runtime data stays separate from tool/prompt business arguments, including on MRTR retry.
pub(all) struct RequestContext {
  request_id : @types.RequestId
  meta : Map[String, Json]
  principal : Principal?
  input_responses : Map[String, Json]
  continuation_state : Json?
  cancellation_token : CancellationToken
  progress_reporter : ProgressReporter
}

///|
pub fn RequestContext::new(
  request_id : @types.RequestId,
  meta? : Map[String, Json] = {},
  principal? : Principal,
  input_responses? : Map[String, Json] = {},
  continuation_state? : Json,
  cancellation_token? : CancellationToken = CancellationToken::new(),
  progress_reporter? : ProgressReporter,
) -> RequestContext {
  {
    request_id,
    meta: meta.copy(),
    principal,
    input_responses: input_responses.copy(),
    continuation_state,
    cancellation_token,
    progress_reporter: progress_reporter.unwrap_or_else(fn() {
      ProgressReporter::new((_, _, _) => (), cancellation_token~)
    }),
  }
}
