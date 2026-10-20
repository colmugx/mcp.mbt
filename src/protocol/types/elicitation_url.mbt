///|
fn url_hex(c : Char) -> Bool {
  c is ('0'..<='9' | 'a'..<='f' | 'A'..<='F')
}

///|
fn url_ipv6(host : String) -> Bool {
  let halves = host.split("::").to_array()
  if halves.length() > 2 {
    return false
  }
  let mut groups = 0
  let mut ipv4 = false
  for half in halves {
    if half.is_empty() {
      continue
    }
    for group in half.split(":") {
      if ipv4 {
        return false
      }
      if group.contains(".") {
        ipv4 = true
        if !host.has_suffix(group) {
          return false
        }
        let octets = group.split(".").to_array()
        if octets.length() != 4 {
          return false
        }
        for octet in octets {
          if octet.is_empty() ||
            octet.length() > 3 ||
            (octet.length() > 1 && octet.has_prefix("0")) {
            return false
          }
          for c in octet; value = 0 {
            if !(c is ('0'..<='9')) {
              return false
            }
            let value = value * 10 + c.to_int() - '0'.to_int()
            if value > 255 {
              return false
            }
            continue value
          }
        }
        groups += 2
      } else {
        if group.is_empty() || group.length() > 4 || !group.iter().all(url_hex) {
          return false
        }
        groups += 1
      }
    }
  }
  if halves.length() == 2 {
    groups < 8
  } else {
    groups == 8
  }
}

///|
fn url_port(port : String) -> Bool {
  for c in port; value = 0 {
    if !(c is ('0'..<='9')) {
      return false
    }
    let value = value * 10 + c.to_int() - '0'.to_int()
    if value > 65535 {
      return false
    }
    continue value
  } nobreak {
    true
  }
}

///|
// Syntax only: never fetch, normalize, or open a URL during decoding.
fn valid_elicitation_url(url : String) -> Bool {
  for c in url; escaped = 0 {
    if c <= ' ' ||
      c == '\u{7f}' ||
      c is ('\\' | '<' | '>' | '"' | '{' | '}' | '|' | '^' | '`') {
      return false
    }
    if escaped > 0 {
      if !url_hex(c) {
        return false
      }
      continue escaped - 1
    }
    continue if c == '%' { 2 } else { 0 }
  } nobreak {
    if escaped != 0 {
      return false
    }
  }
  guard url.split_once(":") is Some((scheme, rest)) &&
    !scheme.is_empty() &&
    !rest.is_empty() else {
    return false
  }
  let mut first = true
  for c in scheme {
    if first {
      if !(c is ('a'..<='z' | 'A'..<='Z')) {
        return false
      }
      first = false
    } else if !(c is ('a'..<='z' | 'A'..<='Z' | '0'..<='9' | '+' | '-' | '.')) {
      return false
    }
  }
  let network = ["http", "https", "ws", "wss", "ftp"].contains(
    scheme.to_lower().to_owned(),
  )
  if !rest.has_prefix("//") {
    return !network
  }
  let authority = StringBuilder()
  for c in rest[2:] {
    if c is ('/' | '?' | '#') {
      break
    }
    authority.write_char(c)
  }
  let authority = authority.to_string()
  let hostport = match authority.split_once("@") {
    Some((_, host)) => host
    None => authority
  }
  if hostport.contains("@") {
    return false
  }
  if hostport.is_empty() {
    return scheme.to_lower() == "file"
  }
  if hostport.has_prefix("[") {
    guard hostport.split_once("]") is Some((host, tail)) &&
      url_ipv6(host[1:].to_owned()) else {
      return false
    }
    return tail.is_empty() ||
      (tail.has_prefix(":") && url_port(tail[1:].to_owned()))
  }
  let host = match hostport.split_once(":") {
    Some((host, port)) => {
      if !url_port(port.to_owned()) {
        return false
      }
      host
    }
    None => hostport
  }
  !host.is_empty() && !host.contains("[") && !host.contains("]")
}
