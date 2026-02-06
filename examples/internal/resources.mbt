///|
pub(all) struct NoteResource {
  storage : Storage
  title : String
}

///|
pub fn NoteResource::new(storage : Storage, title : String) -> NoteResource {
  { storage, title }
}

///|
pub impl @resource.Resource for NoteResource with name(_self : NoteResource) -> String {
  _self.title
}

///|
pub impl @resource.Resource for NoteResource with description(
  _self : NoteResource,
) -> String {
  "Note: " + _self.title
}

///|
pub impl @resource.Resource for NoteResource with uri(_self : NoteResource) -> String {
  "note://" + _self.title
}

///|
pub impl @resource.Resource for NoteResource with mime_type(
  _self : NoteResource,
) -> String {
  "text/markdown"
}

///|
async fn note_resource_read(
  _self : NoteResource,
) -> Result[@resource.ResourceReadResult, @types.MCPError] {
  match _self.storage.load_note(_self.title) {
    Err(msg) =>
      Err(@types.MCPError::InternalError("Failed to read note: \{msg}"))
    Ok(note) => {
      // Format note as markdown
      let tags_joined = note.tags.join(", ")
      let tags_str = if note.tags.length() > 0 {
        "Tags: \{tags_joined}"
      } else {
        "none"
      }
      let markdown = "# \{note.title}\n\n" +
        "**Tags:** \{tags_str}\n\n" +
        note.content
      Ok(@resource.ResourceReadResult::{
        uri: "note://" + _self.title,
        content: @resource.ResourceContent::Text(markdown),
      })
    }
  }
}

///|
pub impl @resource.Resource for NoteResource with read(_self) {
  note_resource_read(_self)
}

///|
pub(all) struct WeatherResource {
  city : String
}

///|
pub fn WeatherResource::new(city : String) -> WeatherResource {
  { city, }
}

///|
pub impl @resource.Resource for WeatherResource with name(
  _self : WeatherResource,
) -> String {
  _self.city
}

///|
pub impl @resource.Resource for WeatherResource with description(
  _self : WeatherResource,
) -> String {
  "Weather for " + _self.city
}

///|
pub impl @resource.Resource for WeatherResource with uri(
  _self : WeatherResource,
) -> String {
  "weather://" + _self.city
}

///|
pub impl @resource.Resource for WeatherResource with mime_type(
  _self : WeatherResource,
) -> String {
  "application/json"
}

///|
async fn weather_resource_read(
  _self : WeatherResource,
) -> Result[@resource.ResourceReadResult, @types.MCPError] {
  let url_weather = "https://goweather.herokuapp.com/weather/" + _self.city
  let (response, body) = @http.get(url_weather)
  if response.code != 200 {
    Err(
      @types.MCPError::InternalError(
        "Weather API returned error: \{response.code}",
      ),
    )
  } else {
    let json_content = body.text()
    Ok(@resource.ResourceReadResult::{
      uri: "weather://" + _self.city,
      content: @resource.ResourceContent::Text(json_content),
    })
  }
}

///|
pub impl @resource.Resource for WeatherResource with read(_self) {
  weather_resource_read(_self)
}

///|
pub fn register_resources(
  server : @mcp.MCPServer,
  _storage : Storage,
) -> @mcp.MCPServer {
  server
  |> s => { s.with_resource(WeatherResource::new("New York")) }
  |> s => { s.with_resource(WeatherResource::new("London")) }
  |> s => { s.with_resource(WeatherResource::new("Tokyo")) }
}
