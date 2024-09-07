//// This module encodes a list of command line arguments as a `dynamic.Dynamic` and
//// provides primitives to build a `dynamic.Decoder` to decode records from command line
//// arguments.
////
//// Arguments are parsed from long names (`--name`) or short names (`-n`).
//// Values are decoded in the form `--name value` or `--name=value`.
//// Boolean flags do not need an explicit value. If the flag exists it is `True`,
//// and `False` if it is missing. (i.e. `--verbose`)
////
//// # Examples
////
//// ## Encoding
////
//// All of the following get encoded the same:
////
//// ```sh
//// --name Lucy --count 3 --verbose
//// --name Lucy --count 3 --verbose true
//// --name=Lucy --count=3 --verbose=true
//// ```
////
//// ```gleam
//// // {"--name": "Lucy", "--count": 3, "--verbose": true}
//// ```
////
//// Clad encodes the arguments without any knowledge of your target record. Therefore
//// missing Bool arguments are not encoded at all:
////
//// ```sh
//// --name Lucy --count 3
//// ```
//// ```gleam
//// // {"--name": "Lucy", "--count": 3}
//// ```
////
//// There is no way to know that a long name and a short name are the same argument when encoding.
//// So they are encoded as separate fields:
////
//// ```sh
//// --name Lucy -n Joe
//// ```
//// ```gleam
//// // {"--name": "Lucy", "-n": "Joe"}
//// ```
////
//// ## Decoding Fields
////
//// Clad provides decoders for `String`, `Int`, `Float`, and `Bool` fields.
////
//// Clad's `bool` decoder assumes missing Bool arguments are `False`:
////
//// ```sh
//// --name Lucy --count 3
//// ```
//// ```gleam
//// use verbose <- clad.bool(long_name: "verbose", short_name: "v")
//// // -> False
//// ```
////
//// Clad's decoders decode the long name first, then the short name
//// if the long name is missing:
//// ```sh
//// --name Lucy -n Joe
//// ```
//// ```gleam
//// use name <- clad.string(long_name: "name", short_name: "n")
//// // -> "Lucy"
//// ```
////
//// It's common for CLI's to have default values for arguments. Clad provides `_with_default` functions for this:
////
//// ```sh
//// --name Lucy
//// ```
//// ```gleam
//// use count <- clad.int_with_default(
////   long_name: "count",
////   short_name: "c",
////   default: 1,
//// )
//// // -> 1
//// ```
//// ## Decoding Records
//// Clad's API is heavily inspired by (read: copied from) [toy](https://github.com/Hackder/toy).
//// ```gleam
//// fn arg_decoder() {
////   use name <- clad.string("name", "n")
////   use count <- clad.int_with_default("count", "c", 1)
////   use verbose <- clad.bool("verbose", "v")
////   clad.decoded(Args(name:, count:, verbose:))
//// }
//// ```
////
//// And use it to decode the arguments:
//// ```gleam
//// // arguments: ["--name", "Lucy", "--count", "3", "--verbose"]
////
//// let args =
////   arg_decoder()
////   |> clad.decode(arguments)
//// let assert Ok(Args("Lucy", 3, True)) = args
//// ```
////
//// Here are a few examples of arguments that would decode the same:
////
//// ```sh
//// --name Lucy --count 3 --verbose
//// --name=Lucy -c 3 -v=true
//// -n=Lucy -c=3 -v
//// ```
//// # Errors
////
//// Clad returns the first error it encounters. If  multiple fields have errors, only the first one will be returned.
////
//// ```gleam
//// // arguments: ["--count", "three"]
////
//// let args =
////   arg_decoder()
////   |> clad.decode(arguments)
//// let assert Error([DecodeError("field", "nothing", ["--name"])]) = args
//// ```
////
//// If a field has a default value, but the argument is supplied with the incorrect type, an error will be returned rather than falling back on the default value.
////
//// ```gleam
//// // arguments: ["-n", "Lucy" "-c", "three"]
////
//// let args =
////   arg_decoder()
////   |> clad.decode(arguments)
//// let assert Error([DecodeError("Int", "String", ["-c"])]) = args
//// ```

import clad/internal/args
import gleam/dict.{type Dict}
import gleam/dynamic.{
  type DecodeError, type DecodeErrors, type Decoder, type Dynamic, DecodeError,
}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// Run a decoder on a list of command line arguments, decoding the value if it
/// is of the desired type, or returning errors.
///
/// This function pairs well with the [argv package](https://github.com/lpil/argv).
///
/// # Examples
/// ```gleam
/// {
///   use name <- clad.string("name", "n")
///   use email <- clad.string("email", "e"),
///   clad.decoded(SignUp(name:, email:))
/// }
/// |> clad.decode(["-n", "Lucy", "--email=lucy@example.com"])
/// // -> Ok(SignUp(name: "Lucy", email: "lucy@example.com"))
/// ```
/// with argv:
/// ```gleam
/// {
///   use name <- clad.string("name", "n")
///   use email <- clad.string("email", "e"),
///   clad.decoded(SignUp(name:, email:))
/// }
/// |> clad.decode(argv.load().arguments)
/// ```
pub fn decode(
  decoder: Decoder(t),
  arguments: List(String),
) -> Result(t, DecodeErrors) {
  use arguments <- result.try(prepare_arguments(arguments))
  object(arguments)
  |> decoder
}

fn prepare_arguments(
  arguments: List(String),
) -> Result(List(#(String, Dynamic)), DecodeErrors) {
  let arguments =
    arguments
    |> args.split_equals
    |> args.add_bools
  let chunked = list.sized_chunk(arguments, 2)
  let chunked =
    list.map(chunked, fn(chunk) {
      case chunk {
        [k, v] -> Ok(#(k, parse(v)))
        _ -> fail("key/value pairs", "dangling arg")
      }
    })

  result.all(chunked)
}

/// A decoder that decodes String arguments.
/// # Examples
/// ```gleam
/// // data: ["--name", "Lucy"]
/// use name <- clad.string(long_name: "name", short_name: "n")
/// // -> "Lucy"
/// ```
pub fn string(
  long_name long_name: String,
  short_name short_name: String,
  then next: fn(String) -> Decoder(b),
) -> Decoder(b) {
  flag(long_name, short_name, dynamic.string, next)
}

/// A decoder that decodes String arguments. Assigns a default value if the
/// argument is missing.
/// # Examples
/// ```gleam
/// // data: []
/// use name <- clad.string(
///   long_name: "name",
///   short_name: "n",
///   default: "Lucy",
/// )
/// // -> "Lucy"
/// ```
pub fn string_with_default(
  long_name long_name: String,
  short_name short_name: String,
  default default: String,
  then next: fn(String) -> Decoder(b),
) -> Decoder(b) {
  flag_with_default(long_name, short_name, dynamic.string, default, next)
}

/// A decoder that decodes Int arguments.
/// # Examples
/// ```gleam
/// // data: ["-c", "2"]
/// use count <- clad.int(long_name: "count", short_name: "c")
/// // -> 2
/// ```
pub fn int(
  long_name long_name: String,
  short_name short_name: String,
  then next: fn(Int) -> Decoder(b),
) -> Decoder(b) {
  flag(long_name, short_name, dynamic.int, next)
}

/// A decoder that decodes Int arguments. Assigns a default value if the
/// argument is missing.
/// # Examples
/// ```gleam
/// // data: []
/// use count <- clad.int(
///   long_name: "count",
///   short_name: "c",
///   default: 2,
/// )
/// // -> 2
/// ```
pub fn int_with_default(
  long_name long_name: String,
  short_name short_name: String,
  default default: Int,
  then next: fn(Int) -> Decoder(b),
) -> Decoder(b) {
  flag_with_default(long_name, short_name, dynamic.int, default, next)
}

/// A decoder that decodes Float arguments.
/// # Examples
/// ```gleam
/// // data: ["--price", "2.50"]
/// use price <- clad.float(long_name: "price", short_name: "p")
/// // -> 2.5
/// ```
pub fn float(
  long_name long_name: String,
  short_name short_name: String,
  then next: fn(Float) -> Decoder(b),
) -> Decoder(b) {
  flag(long_name, short_name, dynamic.float, next)
}

/// A decoder that decodes Float arguments. Assigns a default value if the
/// argument is missing.
/// # Examples
/// ```gleam
/// // data: []
/// use price <- clad.float(
///   long_name: "price",
///   short_name: "p",
///   default: 2.50,
/// )
/// // -> 2.5
/// ```
pub fn float_with_default(
  long_name long_name: String,
  short_name short_name: String,
  default default: Float,
  then next: fn(Float) -> Decoder(b),
) -> Decoder(b) {
  flag_with_default(long_name, short_name, dynamic.float, default, next)
}

/// A decoder that decodes Bool arguments.
/// Missing Bool arguments default to `False`.
/// # Examples
/// ```gleam
/// // data: ["-v"]
/// use verbose <- clad.bool(long_name: "verbose", short_name: "v")
/// // -> True
/// ```
/// ```gleam
/// // data: []
/// use verbose <- clad.bool(long_name: "verbose", short_name: "v")
/// // -> False
/// ```
pub fn bool(
  long_name long_name: String,
  short_name short_name: String,
  then next: fn(Bool) -> Decoder(b),
) -> Decoder(b) {
  flag_with_default(long_name, short_name, dynamic.bool, False, next)
}

/// A decoder that decodes Bool arguments. Assigns a default value if the
/// argument is missing.
///
/// This function is only necessary if you want to assign the default value as `True`.
/// # Examples
/// ```gleam
/// // data: []
/// use verbose <- clad.bool(
///   long_name: "verbose",
///   short_name: "v",
///   default: True,
/// )
/// // -> True
/// ```
pub fn bool_with_default(
  long_name long_name: String,
  short_name short_name: String,
  default default: Bool,
  then next: fn(Bool) -> Decoder(b),
) -> Decoder(b) {
  flag_with_default(long_name, short_name, dynamic.bool, default, next)
}

/// A decoder that decodes List arguments.
/// # Examples
/// ```gleam
/// // data: ["--flavor", "vanilla", "--flavor", "chocolate"]
/// use flavors <- clad.list(long_name: "flavor", short_name: "f", of: dynamic.string)
/// // -> ["vanilla", "chocolate"]
/// ```
pub fn list(
  long_name long_name: String,
  short_name short_name: String,
  of inner: Decoder(t),
  then next: fn(List(t)) -> Decoder(b),
) -> Decoder(b) {
  fn(data) {
    let decoder = do_flag_list(long_name, short_name, inner)
    use l <- result.try(decoder(data))
    next(l)(data)
  }
}

/// Creates a decoder which directly returns the provided value.
/// Used to collect decoded values into a record.
/// # Examples
/// ```gleam
/// pub fn user_decoder() {
///   use name <- clad.string("name", "n")
///   clad.decoded(User(name:))
/// }
/// ```
pub fn decoded(value: a) -> Decoder(a) {
  fn(_) { Ok(value) }
}

fn flag(
  long_name long_name: String,
  short_name short_name: String,
  of decoder: Decoder(a),
  then next: fn(a) -> Decoder(b),
) -> Decoder(b) {
  fn(data) {
    let first = do_flag(long_name, short_name, decoder)
    use a <- result.try(first(data))
    next(a)(data)
  }
}

fn flag_with_default(
  long_name long_name: String,
  short_name short_name: String,
  of decoder: Decoder(a),
  default default: a,
  then next: fn(a) -> Decoder(b),
) -> Decoder(b) {
  fn(data) {
    let first = do_flag(long_name, short_name, decoder) |> with_default(default)
    use a <- result.try(first(data))
    next(a)(data)
  }
}

fn do_flag(
  long_name long_name: String,
  short_name short_name: String,
  of decoder: Decoder(t),
) -> Decoder(t) {
  fn(data) {
    case do_flag_list(long_name, short_name, decoder)(data) {
      Ok([a]) -> Ok(a)
      Ok([a, ..]) ->
        Error([
          DecodeError(dynamic.classify(dynamic.from(a)), "List", [
            "--" <> long_name,
          ]),
        ])
      Error([DecodeError(_, _, [n, "*"]) as err]) ->
        Error([DecodeError(..err, path: [n])])
      Error(e) -> Error(e)
      Ok([]) -> panic as "decoded empty list"
    }
  }
}

fn do_flag_list(
  long_name long_name: String,
  short_name short_name: String,
  inner decoder: Decoder(t),
) -> Decoder(List(t)) {
  fn(data) {
    let ln = long_name_list(long_name, decoder)(data)
    let sn = short_name_list(short_name, decoder)(data)

    case ln, sn {
      Ok(Some(a)), Ok(Some(b)) -> Ok(list.append(a, b))
      Ok(Some(a)), Ok(None) | Ok(None), Ok(Some(a)) -> Ok(a)
      Ok(None), Ok(None) -> missing_field_error(long_name)
      Error(e1), Error(e2) -> Error(list.append(e1, e2))
      Error(e), _ | _, Error(e) -> Error(e)
    }
  }
}

pub fn toggle(
  long_name long_name: String,
  short_name short_name: String,
) -> Decoder(Bool) {
  arg_with_default(long_name, short_name, dynamic.bool, False)
}

pub fn arg_with_default(
  long_name long_name: String,
  short_name short_name: String,
  using decoder: Decoder(t),
  default default: t,
) {
  fn(data) {
    let decoder = arg(long_name, short_name, dynamic.optional(decoder))
    case decoder(data) {
      Ok(value) -> Ok(option.unwrap(value, default))
      Error(e) -> Error(e)
    }
  }
}

type Arg {
  Arg(long_name: String, short_name: String)
  LongName(String)
  ShortName(String)
}

type DecodeResult =
  Result(Option(List(Dynamic)), List(DecodeError))

type ArgResults {
  ArgResults(
    long_name: String,
    short_name: String,
    long_result: DecodeResult,
    short_result: DecodeResult,
  )
  LongNameResults(long_name: String, long_result: DecodeResult)
  ShortNameResults(short_name: String, short_result: DecodeResult)
}

pub fn arg(
  long_name long_name: String,
  short_name short_name: String,
  using decoder: Decoder(t),
) -> Decoder(t) {
  fn(data) {
    let long_name = "--" <> long_name
    let short_name = "-" <> short_name
    do_arg(Arg(long_name, short_name), decoder)(data)
  }
}

pub fn short_name(short_name: String, decoder: Decoder(t)) {
  do_arg(ShortName("-" <> short_name), decoder)
}

pub fn long_name(long_name: String, decoder: Decoder(t)) {
  do_arg(LongName("--" <> long_name), decoder)
}

fn do_arg(arg: Arg, using decoder: Decoder(t)) -> Decoder(t) {
  fn(data) {
    let arg_res = case arg {
      Arg(long_name, short_name) -> {
        ArgResults(
          long_name,
          short_name,
          dynamic.optional_field(long_name, dynamic.shallow_list)(data),
          dynamic.optional_field(short_name, dynamic.shallow_list)(data),
        )
      }
      LongName(name) -> {
        LongNameResults(
          name,
          dynamic.optional_field(name, dynamic.shallow_list)(data),
        )
      }
      ShortName(name) -> {
        ShortNameResults(
          name,
          dynamic.optional_field(name, dynamic.shallow_list)(data),
        )
      }
    }

    case arg_res {
      ArgResults(l, s, lr, sr) -> do_arg_results(l, s, lr, sr, decoder)
      LongNameResults(n, r) -> do_single_name_results(n, r, decoder)
      ShortNameResults(n, r) -> do_single_name_results(n, r, decoder)
    }
  }
}

fn do_arg_results(
  long_name: String,
  short_name: String,
  long_result: DecodeResult,
  short_result: DecodeResult,
  decoder: Decoder(t),
) {
  case long_result, short_result {
    Ok(Some(a)), Ok(Some(b)) ->
      do_list(long_name, decoder)(dynamic.from(list.append(a, b)))
    Ok(Some([a])), Ok(None) -> do_single(long_name, decoder)(a)
    Ok(None), Ok(Some([a])) -> do_single(short_name, decoder)(a)
    Ok(Some(a)), Ok(None) -> do_list(long_name, decoder)(dynamic.from(a))
    Ok(None), Ok(Some(a)) -> do_list(short_name, decoder)(dynamic.from(a))
    Ok(None), Ok(None) ->
      do_single(long_name, decoder)(dynamic.from(None))
      |> result.replace_error(missing_field(long_name))
    Error(e1), Error(e2) -> Error(list.append(e1, e2))
    Error(e), _ | _, Error(e) -> Error(e)
  }
}

fn do_single_name_results(
  name: String,
  decode_result: DecodeResult,
  decoder: Decoder(t),
) {
  case decode_result {
    Ok(Some([a])) -> do_single(name, decoder)(a)
    Ok(Some(a)) -> do_list(name, decoder)(dynamic.from(a))
    Ok(None) ->
      do_single(name, decoder)(dynamic.from(None))
      |> result.replace_error(missing_field(name))
    Error(e) -> Error(e)
  }
}

fn do_single(name: String, decoder: Decoder(t)) -> Decoder(t) {
  fn(data) {
    use first_error <- result.try_recover(decoder(data))
    let decoder = do_list(name, decoder)
    use second_error <- result.map_error(decoder(dynamic.from([data])))
    case first_error {
      [DecodeError(..) as e] -> [DecodeError(..e, path: [name, ..e.path])]
      _ -> second_error
    }
  }
}

fn do_list(name: String, decoder: Decoder(t)) -> Decoder(t) {
  fn(data) {
    use error <- result.map_error(decoder(data))
    case error {
      [DecodeError(..) as e] -> [DecodeError(..e, path: [name, ..e.path])]
      _ -> error
    }
  }
}

fn with_default(decoder: Decoder(t), default: t) -> Decoder(t) {
  fn(data) {
    case decoder(data) {
      Ok(decoded) -> Ok(decoded)
      Error([DecodeError("field", "nothing", [_])]) -> Ok(default)
      errors -> errors
    }
  }
}

fn long_name_list(long_name: String, decoder: Decoder(t)) {
  dynamic.optional_field("--" <> long_name, dynamic.list(decoder))
}

fn short_name_list(short_name: String, decoder: Decoder(t)) {
  dynamic.optional_field("-" <> short_name, dynamic.list(decoder))
}

fn fail(expected: String, found: String) {
  Error([DecodeError(expected, found, [])])
}

fn parse(input: String) -> Dynamic {
  try_parse_float(input)
  |> result.or(try_parse_int(input))
  |> result.or(try_parse_bool(input))
  |> result.unwrap(dynamic.from(input))
}

fn try_parse_float(input: String) {
  float.parse(input)
  |> result.map(dynamic.from)
}

fn try_parse_int(input: String) {
  int.parse(input)
  |> result.map(dynamic.from)
}

fn try_parse_bool(input: String) {
  case input {
    "true" | "True" -> Ok(dynamic.from(True))
    "false" | "False" -> Ok(dynamic.from(False))
    _ -> Error(Nil)
  }
}

fn object(entries: List(#(String, Dynamic))) -> dynamic.Dynamic {
  do_object_list(entries, dict.new())
}

fn do_object_list(
  entries: List(#(String, Dynamic)),
  acc: Dict(String, Dynamic),
) -> Dynamic {
  case entries {
    [] -> dynamic.from(acc)
    [#(k, _), ..rest] -> {
      case dict.has_key(acc, k) {
        True -> do_object_list(rest, acc)
        False -> {
          let values = list.key_filter(entries, k)
          do_object_list(rest, dict.insert(acc, k, dynamic.from(values)))
        }
      }
    }
  }
}

fn failure(
  expected: String,
  found: String,
  path: List(String),
) -> Result(t, DecodeErrors) {
  Error([DecodeError(expected, found, path)])
}

fn missing_field_error(long_name: String) {
  failure("field", "nothing", ["--" <> long_name])
}

fn missing_field(name: String) {
  [DecodeError("field", "nothing", [name])]
}
