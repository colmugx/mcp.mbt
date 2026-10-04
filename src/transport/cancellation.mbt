///|
/// Do not relabel task cancellation as a transport failure: callers need its identity to unwind.
fn transport_read_error(error : Error, prefix : String) -> Error {
  if @async.is_being_cancelled() {
    error
  } else {
    @types.ReadError(prefix + error.to_string())
  }
}

///|
fn transport_write_error(error : Error, prefix : String) -> Error {
  if @async.is_being_cancelled() {
    error
  } else {
    @types.WriteError(prefix + error.to_string())
  }
}
