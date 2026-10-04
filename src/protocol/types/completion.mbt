///|
pub(all) enum CompletionReference {
  Prompt(name~ : String, title~ : String?, extensions~ : Map[String, Json])
  Resource(uri~ : String, extensions~ : Map[String, Json])
} derive(Eq, Debug)

///|
pub fn CompletionReference::prompt(
  name : String,
  title? : String,
) -> CompletionReference {
  Prompt(name~, title~, extensions=Map([]))
}

///|
pub fn CompletionReference::resource(uri : String) -> CompletionReference {
  Resource(uri~, extensions=Map([]))
}

///|
pub fn CompletionReference::from_json(
  value : Json,
) -> CompletionReference raise MCPError {
  let fields = wire_object(value)
  match wire_string(fields, "type") {
    "ref/prompt" =>
      Prompt(
        name=wire_string(fields, "name"),
        title=wire_optional_string(fields, "title"),
        extensions=wire_extensions(fields, ["type", "name", "title"]),
      )
    "ref/resource" =>
      Resource(
        uri=wire_string(fields, "uri"),
        extensions=wire_extensions(fields, ["type", "uri"]),
      )
    _ => raise InvalidParams("Unknown completion reference type")
  }
}

///|
pub impl ToJson for CompletionReference with fn to_json(self) {
  match self {
    Prompt(name~, title~, extensions~) => {
      let fields = wire_extensions(extensions, ["type", "name", "title"])
      fields.set("type", "ref/prompt")
      fields.set("name", Json::string(name))
      wire_put_string(fields, "title", title)
      Json::object(fields)
    }
    Resource(uri~, extensions~) => {
      let fields = wire_extensions(extensions, ["type", "uri"])
      fields.set("type", "ref/resource")
      fields.set("uri", Json::string(uri))
      Json::object(fields)
    }
  }
}

///|
pub(all) struct CompletionArgument {
  name : String
  value : String
  extensions : Map[String, Json]
} derive(Eq, Debug)

///|
pub fn CompletionArgument::new(
  name : String,
  value : String,
) -> CompletionArgument {
  { name, value, extensions: Map([]), }
}

///|
pub(all) struct CompletionContext {
  arguments : Map[String, String]?
  extensions : Map[String, Json]
} derive(Eq, Debug)

///|
pub fn CompletionContext::new(
  arguments? : Map[String, String],
) -> CompletionContext {
  { arguments, extensions: Map([]), }
}

///|
pub(all) struct CompleteRequestParams {
  reference : CompletionReference
  argument : CompletionArgument
  context : CompletionContext?
  meta : Map[String, Json]?
  extensions : Map[String, Json]
} derive(Eq, Debug)

///|
pub fn CompleteRequestParams::new(
  reference : CompletionReference,
  argument : CompletionArgument,
  context? : CompletionContext,
  meta? : Map[String, Json],
) -> CompleteRequestParams {
  { reference, argument, context, meta, extensions: Map([]), }
}

///|
pub fn CompleteRequestParams::from_json(
  value : Json,
) -> CompleteRequestParams raise MCPError {
  let fields = wire_object(value)
  let reference = CompletionReference::from_json(
    fields.get("ref").unwrap_or(Json::null()),
  )
  let argument = wire_object(fields.get("argument").unwrap_or(Json::null()))
  let context = match fields.get("context") {
    None => None
    Some(value) => {
      let context_fields = wire_object(value)
      let arguments = match context_fields.get("arguments") {
        None => None
        Some(value) => {
          let values = wire_object(value)
          let arguments : Map[String, String] = Map([])
          for key, value in values {
            guard value is String(value) else {
              raise InvalidParams(
                "Completion context arguments must be strings",
              )
            }
            arguments.set(key, value)
          }
          Some(arguments)
        }
      }
      Some({
        arguments,
        extensions: wire_extensions(context_fields, ["arguments"]),
      })
    }
  }
  {
    reference,
    argument: {
      name: wire_string(argument, "name"),
      value: wire_string(argument, "value"),
      extensions: wire_extensions(argument, ["name", "value"]),
    },
    context,
    meta: wire_optional_object(fields, "_meta"),
    extensions: wire_extensions(fields, ["ref", "argument", "context", "_meta"]),
  }
}

///|
pub impl ToJson for CompleteRequestParams with fn to_json(self) {
  let fields = wire_extensions(self.extensions, [
    "ref", "argument", "context", "_meta",
  ])
  fields.set("ref", self.reference.to_json())
  let argument = wire_extensions(self.argument.extensions, ["name", "value"])
  argument.set("name", Json::string(self.argument.name))
  argument.set("value", Json::string(self.argument.value))
  fields.set("argument", Json::object(argument))
  if self.context is Some(context) {
    let context_fields = wire_extensions(context.extensions, ["arguments"])
    if context.arguments is Some(arguments) {
      let values : Map[String, Json] = Map([])
      for key, value in arguments {
        values.set(key, Json::string(value))
      }
      context_fields.set("arguments", Json::object(values))
    }
    fields.set("context", Json::object(context_fields))
  }
  wire_put_meta(fields, self.meta)
  Json::object(fields)
}

///|
/// Complete wire result, including open completion fields and result metadata.
pub(all) struct CompletionResult {
  values : Array[String]
  total : Double?
  has_more : Bool?
  completion_extensions : Map[String, Json]
  metadata : ResultMetadata
} derive(Eq, Debug)

///|
pub fn CompletionResult::new(
  values : Array[String],
  total? : Double,
  has_more? : Bool,
  metadata? : ResultMetadata = ResultMetadata::empty(),
) -> CompletionResult {
  { values, total, has_more, completion_extensions: Map([]), metadata, }
}

///|
pub fn CompletionResult::from_json(
  value : Json,
) -> CompletionResult raise MCPError {
  let fields = wire_object(value)
  let completion = wire_object(fields.get("completion").unwrap_or(Json::null()))
  let values = wire_optional_strings(completion, "values").unwrap_or_else(() => {
    raise InvalidParams("Missing completion values")
  })
  guard values.length() <= 100 else {
    raise InvalidParams("Completion values must not exceed 100 items")
  }
  let total = match completion.get("total") {
    None => None
    Some(Number(total, ..)) if !total.is_nan() && !total.is_inf() => Some(total)
    _ => raise InvalidParams("Invalid completion total")
  }
  {
    values,
    total,
    has_more: wire_optional_bool(completion, "hasMore"),
    completion_extensions: wire_extensions(completion, [
      "values", "total", "hasMore",
    ]),
    metadata: ResultMetadata::from_json(value, body_fields=["completion"]),
  }
}

///|
pub impl ToJson for CompletionResult with fn to_json(self) {
  let fields = self.metadata.to_fields()
  let completion = wire_extensions(self.completion_extensions, [
    "values", "total", "hasMore",
  ])
  completion.set("values", Json::array(self.values.map(Json::string)))
  if self.total is Some(total) {
    completion.set("total", Json::number(total))
  }
  wire_put_bool(completion, "hasMore", self.has_more)
  fields.set("completion", Json::object(completion))
  Json::object(fields)
}

///|
pub extend CompletionReference with Eq::{equal, not_equal}

///|
pub extend CompletionReference with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CompletionReference with ToJson::{to_json}

///|
pub extend CompletionArgument with Eq::{equal, not_equal}

///|
pub extend CompletionArgument with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CompletionContext with Eq::{equal, not_equal}

///|
pub extend CompletionContext with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CompleteRequestParams with Eq::{equal, not_equal}

///|
pub extend CompleteRequestParams with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CompleteRequestParams with ToJson::{to_json}

///|
pub extend CompletionResult with Eq::{equal, not_equal}

///|
pub extend CompletionResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CompletionResult with ToJson::{to_json}
