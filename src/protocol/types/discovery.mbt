///|
/// Full discovery result, including cache hints and server identity metadata.
pub(all) struct DiscoverResult {
  supported_versions : Array[String]
  capabilities : ServerCapabilities
  instructions : String?
  metadata : ResultMetadata
} derive(Debug, Eq)

///|
pub fn DiscoverResult::new(
  supported_versions : Array[String],
  capabilities : ServerCapabilities,
  instructions? : String,
  metadata? : ResultMetadata = ResultMetadata::empty(),
) -> DiscoverResult {
  { supported_versions, capabilities, instructions, metadata, }
}

///|
pub fn DiscoverResult::from_json(value : Json) -> DiscoverResult raise MCPError {
  let fields = wire_object(value)
  let supported_versions = wire_optional_strings(fields, "supportedVersions").unwrap_or_else(() => {
      raise InvalidParams("Missing supportedVersions")
    },
  )
  let capabilities = match fields.get("capabilities") {
    Some(value) => ServerCapabilities::from_json(value)
    None => raise InvalidParams("Missing capabilities")
  }
  {
    supported_versions,
    capabilities,
    instructions: wire_optional_string(fields, "instructions"),
    metadata: ResultMetadata::from_json(value, body_fields=[
      "supportedVersions", "capabilities", "instructions",
    ]),
  }
}

///|
pub impl ToJson for DiscoverResult with fn to_json(self) {
  let fields = self.metadata.to_fields()
  fields.set("supportedVersions", self.supported_versions.to_json())
  fields.set("capabilities", self.capabilities.to_json())
  fields.remove("instructions")
  wire_put_string(fields, "instructions", self.instructions)
  Json::object(fields)
}

///|
pub extend DiscoverResult with ToJson::{to_json}

///|
pub extend DiscoverResult with Eq::{equal, not_equal}

///|
pub extend DiscoverResult with @moonbitlang/core/debug.Debug::{to_repr}
