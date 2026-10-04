///|
pub(all) suberror CompileError {
  InvalidKeyword(path~ : String, reason~ : String)
  UnknownDialect(String)
  UnsupportedKeyword(path~ : String, keyword~ : String)
  UnsupportedPattern(path~ : String, pattern~ : String, reason~ : String)
  DepthLimit(Int)
} derive(Debug)

///|
pub(all) suberror EvaluationError {
  DepthLimit(Int)
  InvalidNumber(path~ : String)
} derive(Debug)

///|
pub(all) struct Fault {
  instance_path : String
  schema_path : String
  keyword : String
  message : String
} derive(Debug, Eq)

///|
pub extend CompileError with @debug.Debug::{to_repr}

///|
pub extend EvaluationError with @debug.Debug::{to_repr}

///|
pub extend Fault with @debug.Debug::{to_repr}

///|
pub extend Fault with Eq::{equal, not_equal}
